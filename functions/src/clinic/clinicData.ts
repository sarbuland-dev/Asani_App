import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions/v2';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { ACTIVE_STATUSES } from '../booking/rules';
import { claimsOf, id, input, int, logActivity, monthOf, optStr, requireClinic, str } from '../lib/access';
import { DAY_ID, WEEKDAYS, hhmmToMinutes, pktNow } from '../lib/dates';
import { callableOptions } from '../lib/options';
import { notifyClinicCancel } from '../queue/cancelNotice';
import { evaluateQueue } from '../queue/notify';
import { historyEntry, syncDay } from './queueAction';

const GENDERS = ['male', 'female', 'other'];
const RELATIONS = ['self', 'mother', 'father', 'spouse', 'son', 'daughter', 'brother', 'sister', 'other'];
const PHONE = /^\+923\d{9}$/;
const LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const PRINT_FORMATS = ['thermal80', 'a5', 'none'];

function writable(status: unknown) {
  if (status === 'suspended' || status === 'cancelled') {
    throw new HttpsError('failed-precondition', 'This clinic is suspended. The queue is read-only until the payment is recorded.', { code: 'suspended' });
  }
}

// ======================================================================
// C-06 walk-in token: same numbering as bookToken (BW-2), status Arrived.
// ======================================================================
export const clinicCreateWalkIn = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const d = input(request);
  const actor = await requireClinic(db, request);
  const doctorId = id(d, 'doctorId');
  const date = pktNow().date;
  const existingId = d.patientId ? id(d, 'patientId') : null;

  // New patient details (C-06 step 3).
  let fresh: Record<string, unknown> | null = null;
  if (!existingId) {
    const n = (d.newPatient ?? {}) as Record<string, unknown>;
    const phone = str(n, 'phone', 20);
    if (!PHONE.test(phone)) throw new HttpsError('invalid-argument', 'Enter a valid Pakistani mobile number.');
    const name = str(n, 'name', 60);
    if (name.length < 2) throw new HttpsError('invalid-argument', 'Enter the patient name.');
    const gender = str(n, 'gender', 10);
    if (!GENDERS.includes(gender)) throw new HttpsError('invalid-argument', 'Pick a gender.');
    const relation = (optStr(n, 'relation', 12) ?? 'other') as string;
    if (!RELATIONS.includes(relation)) throw new HttpsError('invalid-argument', 'Unknown relation.');
    const age = n.age === undefined || n.age === null ? null : int(n, 'age', 0, 120);
    // Visits show up in the app later if this phone has an account (C-06).
    const owner = await db.collection('patients').where('phone', '==', phone).where('ownerUid', '!=', null).limit(1).get();
    fresh = {
      phone,
      name,
      nameLower: name.toLowerCase(),
      birthYear: age === null ? null : new Date().getFullYear() - age,
      gender,
      relation,
      ownerUid: owner.empty ? null : owner.docs[0].data().ownerUid,
      patientPhone: null,
      status: 'active',
      createdBy: 'staff',
      clinicIds: [actor.clinicId],
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };
  }

  const clinicRef = db.collection('clinics').doc(actor.clinicId);
  const doctorRef = db.collection('doctors').doc(doctorId);
  const dayRef = doctorRef.collection('days').doc(date);
  const patientRef = existingId ? db.collection('patients').doc(existingId) : db.collection('patients').doc();
  const tokenRef = db.collection('tokens').doc();

  const result = await db.runTransaction(async (tx) => {
    const [clinicSnap, doctorSnap, daySnap, patientSnap] = await tx.getAll(clinicRef, doctorRef, dayRef, patientRef);
    writable(clinicSnap.data()?.status);
    const doctor = doctorSnap.data();
    if (!doctor || doctor.clinicId !== actor.clinicId || doctor.active === false) throw new HttpsError('not-found', 'Doctor not found.');
    const day = daySnap.data();
    if (day?.sessionStatus === 'ended') throw new HttpsError('failed-precondition', "Today's session has ended for this doctor.", { code: 'session-ended' });
    const last = Number(day?.lastTokenNumber ?? 0);
    const max = Number(doctor.maxTokensPerDay ?? 40);
    if (last >= max) throw new HttpsError('failed-precondition', `All ${max} tokens for today are used.`, { code: 'tokens-full' });

    let patient: Record<string, any>;
    if (existingId) {
      patient = patientSnap.data() ?? {};
      // A profile from another clinic (D-22 lookup) may be used only when the
      // clinic also sends that profile's full phone number.
      const here = (patient.clinicIds ?? []).includes(actor.clinicId);
      if (patient.status !== 'active' || (!here && (typeof d.phone !== 'string' || d.phone !== patient.phone))) {
        throw new HttpsError('not-found', 'Patient not found.');
      }
      // BR-5: one active token per profile per doctor per day.
      const dup = await tx.get(
        db.collection('tokens').where('patientId', '==', existingId).where('doctorId', '==', doctorId).where('date', '==', date).where('status', 'in', ACTIVE_STATUSES).limit(1),
      );
      if (!dup.empty) {
        const t = dup.docs[0].data();
        throw new HttpsError('failed-precondition', `${patient.name} already has token ${t.tokenPrefix ?? 'A'}-${t.number} today.`, { code: 'duplicate-token' });
      }
    } else {
      patient = fresh!;
      tx.set(patientRef, fresh!);
    }

    const number = last + 1;
    const now = new Date();
    const ts = FieldValue.serverTimestamp();
    tx.set(tokenRef, {
      clinicId: actor.clinicId,
      doctorId,
      date,
      number,
      tokenPrefix: doctor.tokenPrefix ?? 'A',
      patientId: patientRef.id,
      patientSnapshot: { name: patient.name, birthYear: patient.birthYear ?? null, gender: patient.gender, relation: patient.relation, phone: patient.phone },
      bookedByUserId: null,
      patientOwnerUid: patient.ownerUid ?? null,
      source: 'walkIn',
      status: 'arrived',
      notified: {},
      followUpId: null,
      createdAt: ts,
      arrivedAt: now,
      calledAt: null,
      completedAt: null,
      cancelledAt: null,
      cancelledBy: null,
      waitMinutes: null,
      history: [historyEntry('Walk-in created · Arrived', actor)],
      updatedAt: ts,
    });
    tx.set(
      dayRef,
      {
        clinicId: actor.clinicId,
        doctorId,
        date,
        ...(day ? {} : { sessionStatus: 'notStarted', currentToken: 0 }),
        lastTokenNumber: number,
        bookedCount: Number(day?.bookedCount ?? 0) + 1,
        updatedAt: ts,
      },
      { merge: true },
    );
    if (existingId) tx.update(patientRef, { clinicIds: FieldValue.arrayUnion(actor.clinicId), updatedAt: ts });
    tx.set(clinicRef.collection('stats').doc(monthOf(date)), { walkIn: FieldValue.increment(1), tokens: FieldValue.increment(1) }, { merge: true });
    return { tokenId: tokenRef.id, number, label: `${doctor.tokenPrefix ?? 'A'}-${number}` };
  });

  await syncDay(db, doctorId, date);
  await evaluateQueue(db, getMessaging(), doctorId, date).catch((e) => logger.warn('notify after walk-in', e));
  return result;
});

// ======================================================================
// C-08: typo fixes on a patient of this clinic (Q-W07 open; logged).
// ======================================================================
export const clinicUpdatePatient = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const d = input(request);
  const actor = await requireClinic(db, request);
  const ref = db.collection('patients').doc(id(d, 'patientId'));
  const p = (await ref.get()).data();
  if (!p || !(p.clinicIds ?? []).includes(actor.clinicId)) throw new HttpsError('not-found', 'Patient not found.');
  const name = str(d, 'name', 60);
  const gender = str(d, 'gender', 10);
  if (!GENDERS.includes(gender)) throw new HttpsError('invalid-argument', 'Pick a gender.');
  const age = d.age === undefined || d.age === null ? null : int(d, 'age', 0, 120);
  await ref.update({
    name,
    nameLower: name.toLowerCase(),
    gender,
    birthYear: age === null ? (p.birthYear ?? null) : new Date().getFullYear() - age,
    updatedAt: FieldValue.serverTimestamp(),
  });
  await logActivity(db, actor, actor.clinicId, 'edited patient details', name);
  return { ok: true };
});

// ======================================================================
// C-09: set follow-up from a Called/Completed token.
// ======================================================================
export const setFollowUp = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const d = input(request);
  const actor = await requireClinic(db, request);
  const tokenRef = db.collection('tokens').doc(id(d, 'tokenId'));
  const t = (await tokenRef.get()).data();
  if (!t || t.clinicId !== actor.clinicId) throw new HttpsError('not-found', 'Token not found.');
  const dueDate = str(d, 'dueDate', 10);
  if (!DAY_ID.test(dueDate) || dueDate <= pktNow().date) throw new HttpsError('invalid-argument', 'Pick a date after today.');
  const note = optStr(d, 'note', 40);
  const patient = (await db.collection('patients').doc(t.patientId).get()).data();

  // One pending follow-up per patient and doctor: update it instead of adding another.
  const pending = await db.collection('followUps').where('patientId', '==', t.patientId).where('doctorId', '==', t.doctorId).where('status', '==', 'pending').limit(1).get();
  const ref = pending.empty ? db.collection('followUps').doc() : pending.docs[0].ref;
  const ts = FieldValue.serverTimestamp();
  await ref.set(
    {
      clinicId: t.clinicId,
      doctorId: t.doctorId,
      patientId: t.patientId,
      ownerUid: patient?.ownerUid ?? null,
      sourceTokenId: tokenRef.id,
      dueDate,
      note,
      status: 'pending',
      bookedTokenId: null,
      remindersSent: 0,
      ...(pending.empty ? { createdAt: ts } : {}),
      updatedAt: ts,
    },
    { merge: true },
  );
  await tokenRef.update({ history: FieldValue.arrayUnion(historyEntry('Follow-up set', actor, dueDate)), updatedAt: ts });
  return { ok: true, followUpId: ref.id };
});

// ======================================================================
// C-11 (D-19): the clinic adds and manages its own doctors.
// ======================================================================
function readSchedule(v: unknown): Record<string, { start: string; end: string } | null> {
  const m = (v ?? {}) as Record<string, unknown>;
  const out: Record<string, { start: string; end: string } | null> = {};
  const hhmm = /^([01]\d|2[0-3]):[0-5]\d$/;
  for (const k of WEEKDAYS) {
    const s = m[k] as Record<string, unknown> | null | undefined;
    if (!s) {
      out[k] = null;
      continue;
    }
    const start = String(s.start ?? ''), end = String(s.end ?? '');
    if (!hhmm.test(start) || !hhmm.test(end) || hhmmToMinutes(end) <= hhmmToMinutes(start)) {
      throw new HttpsError('invalid-argument', `Check the ${k} timing: end must be after start.`);
    }
    out[k] = { start, end };
  }
  return out;
}

export const saveDoctor = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const d = input(request);
  const actor = await requireClinic(db, request);
  const name = str(d, 'name', 60);
  const fields = {
    name,
    speciality: str(d, 'speciality', 60),
    qualification: optStr(d, 'qualification', 60),
    avgConsultMinutes: int(d, 'avgConsultMinutes', 2, 120),
    maxTokensPerDay: int(d, 'maxTokensPerDay', 1, 300),
    bookingWindowDays: int(d, 'bookingWindowDays', 0, 60),
    schedule: readSchedule(d.schedule),
  };
  const ts = FieldValue.serverTimestamp();
  const doctorId = d.doctorId ? id(d, 'doctorId') : null;

  if (doctorId) {
    const ref = db.collection('doctors').doc(doctorId);
    const cur = (await ref.get()).data();
    if (!cur || cur.clinicId !== actor.clinicId) throw new HttpsError('not-found', 'Doctor not found.');
    await ref.update({ ...fields, updatedAt: ts });
    await logActivity(db, actor, actor.clinicId, 'updated doctor', name);
    return { doctorId };
  }

  // New: the letter is assigned here and never reused (BW-7).
  const clinicRef = db.collection('clinics').doc(actor.clinicId);
  const ref = db.collection('doctors').doc();
  const letter = await db.runTransaction(async (tx) => {
    const clinic = (await tx.get(clinicRef)).data() ?? {};
    const existing = await tx.get(db.collection('doctors').where('clinicId', '==', actor.clinicId));
    const used = existing.docs.map((x) => LETTERS.indexOf(String(x.data().tokenPrefix ?? 'A')));
    const next = Math.max(Number(clinic.nextDoctorLetter ?? 0), used.length ? Math.max(...used) + 1 : 0);
    if (next >= LETTERS.length) throw new HttpsError('resource-exhausted', 'No more doctor letters available.');
    const active = existing.docs.filter((x) => x.data().active !== false).length;
    tx.set(ref, { ...fields, clinicId: actor.clinicId, tokenPrefix: LETTERS[next], onLeaveDates: [], active: true, sortOrder: existing.size + 1, addedBy: 'clinic', createdAt: ts, updatedAt: ts });
    tx.update(clinicRef, { nextDoctorLetter: next + 1, doctorCount: active + 1, updatedAt: ts });
    return LETTERS[next];
  });
  // D-19: shows up for the Super Admin (dashboard + activity).
  await logActivity(db, actor, actor.clinicId, 'added doctor', `${name} · ${fields.speciality}`);
  return { doctorId: ref.id, tokenPrefix: letter };
});

async function ownDoctor(db: FirebaseFirestore.Firestore, clinicId: string, doctorId: string) {
  const ref = db.collection('doctors').doc(doctorId);
  const doc = (await ref.get()).data();
  if (!doc || doc.clinicId !== clinicId) throw new HttpsError('not-found', 'Doctor not found.');
  return { ref, doc };
}

export const setDoctorActive = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const d = input(request);
  const actor = await requireClinic(db, request);
  const { ref, doc } = await ownDoctor(db, actor.clinicId, id(d, 'doctorId'));
  const active = d.active === true;
  await ref.update({ active, updatedAt: FieldValue.serverTimestamp() });
  const count = await db.collection('doctors').where('clinicId', '==', actor.clinicId).where('active', '==', true).count().get();
  await db.collection('clinics').doc(actor.clinicId).update({ doctorCount: count.data().count });
  await logActivity(db, actor, actor.clinicId, active ? 'reactivated doctor' : 'deactivated doctor', String(doc.name));
  return { ok: true };
});

/** Add/remove a leave date. Returns how many active tokens that date has. */
export const setDoctorLeave = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const d = input(request);
  const actor = await requireClinic(db, request);
  const { ref, doc } = await ownDoctor(db, actor.clinicId, id(d, 'doctorId'));
  const date = str(d, 'date', 10);
  if (!DAY_ID.test(date)) throw new HttpsError('invalid-argument', 'date must be yyyy-MM-dd.');
  const add = d.add !== false;
  await ref.update({ onLeaveDates: add ? FieldValue.arrayUnion(date) : FieldValue.arrayRemove(date), updatedAt: FieldValue.serverTimestamp() });
  await logActivity(db, actor, actor.clinicId, add ? 'added leave' : 'removed leave', `${doc.name} · ${date}`);
  const active = await db.collection('tokens').where('doctorId', '==', ref.id).where('date', '==', date).where('status', 'in', ACTIVE_STATUSES).count().get();
  return { activeTokens: active.data().count };
});

/** Bulk-cancel a doctor's tokens on a leave day, with a reason (C-11). */
export const cancelDoctorTokens = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const d = input(request);
  const actor = await requireClinic(db, request);
  const { ref, doc } = await ownDoctor(db, actor.clinicId, id(d, 'doctorId'));
  const date = str(d, 'date', 10);
  if (!DAY_ID.test(date)) throw new HttpsError('invalid-argument', 'date must be yyyy-MM-dd.');
  const reason = str(d, 'reason', 80);
  const snap = await db.collection('tokens').where('doctorId', '==', ref.id).where('date', '==', date).where('status', 'in', ACTIVE_STATUSES).get();
  const batch = db.batch();
  const now = new Date();
  for (const t of snap.docs) {
    batch.update(t.ref, {
      status: 'cancelled',
      cancelledAt: now,
      cancelledBy: 'clinic',
      cancelReason: reason,
      history: FieldValue.arrayUnion(historyEntry('Cancelled', actor, reason)),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  await syncDay(db, ref.id, date);
  await logActivity(db, actor, actor.clinicId, `cancelled ${snap.size} tokens`, `${doc.name} · ${date}`);
  // D-23: tell each patient; also re-check the queue for anyone left (review finding).
  await notifyClinicCancel(db, getMessaging(), snap.docs.map((t) => t.id)).catch((e) => logger.warn('cancel notice', e));
  await evaluateQueue(db, getMessaging(), ref.id, date).catch((e) => logger.warn('notify after bulk cancel', e));
  return { cancelled: snap.size };
});

// ======================================================================
// C-13 settings, C-14 export log, C-12 password, login touch.
// ======================================================================
export const updateClinicSettings = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const d = input(request);
  const actor = await requireClinic(db, request);
  const printFormat = str(d, 'printFormat', 12);
  if (!PRINT_FORMATS.includes(printFormat)) throw new HttpsError('invalid-argument', 'Unknown print format.');
  await db.collection('clinics').doc(actor.clinicId).update({
    address: str(d, 'address', 120),
    area: str(d, 'area', 60),
    phone: str(d, 'phone', 20),
    printFormat,
    updatedAt: FieldValue.serverTimestamp(),
  });
  await logActivity(db, actor, actor.clinicId, 'updated clinic settings', actor.name);
  return { ok: true };
});

export const logExport = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const actor = await requireClinic(db, request);
  await logActivity(db, actor, actor.clinicId, 'exported visits', str(input(request), 'range', 60));
  return { ok: true };
});

/** Called right after login: marks the invite accepted and the last login (A-02). */
export const clinicLoginTouch = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const c = claimsOf(request);
  if (c.role !== 'clinic') return { ok: true };
  const ref = db.collection('clinicAccounts').doc(c.uid);
  const acc = (await ref.get()).data();
  await ref.set({ lastLoginAt: FieldValue.serverTimestamp(), ...(acc?.status === 'invited' ? { status: 'active' } : {}) }, { merge: true });
  return { ok: true };
});

/** C-12: after the client changed the password, sign the clinic out everywhere else. */
export const clinicPasswordChanged = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const actor = await requireClinic(db, request);
  await getAuth().revokeRefreshTokens(actor.uid);
  await db.collection('clinicAccounts').doc(actor.uid).set({ passwordChangedAt: FieldValue.serverTimestamp() }, { merge: true });
  await logActivity(db, actor, actor.clinicId, 'changed clinic login password', request.auth?.token.email ?? '');
  return { ok: true };
});
