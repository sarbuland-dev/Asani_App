import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions/v2';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { callableOptions } from '../lib/options';
import { DAY_ID, pktNow } from '../lib/dates';
import { badInput, bookingError } from '../lib/errors';
import { evaluateQueue } from '../queue/notify';
import {
  ACTIVE_STATUSES,
  MAX_ACTIVE_TOKENS_PER_ACCOUNT,
  DayData,
  DoctorData,
  checkAvailability,
  withNumber,
} from './rules';

interface BookTokenInput {
  clinicId: string;
  doctorId: string;
  patientId: string;
  date: string;
}

function readInput(data: unknown): BookTokenInput {
  const d = (data ?? {}) as Record<string, unknown>;
  const str = (k: string) => {
    const v = d[k];
    if (typeof v !== 'string' || v.length === 0 || v.length > 128 || v.includes('/')) throw badInput(`${k} is required.`);
    return v;
  };
  const input = { clinicId: str('clinicId'), doctorId: str('doctorId'), patientId: str('patientId'), date: str('date') };
  if (!DAY_ID.test(input.date)) throw badInput('date must be yyyy-MM-dd.');
  return input;
}

/**
 * PRD F-04, ARCHITECTURE.md §3.2. Validates BR-1..BR-6 and assigns the next
 * number (BR-7) inside ONE transaction, so two bookings never share a number.
 *
 * It also adds the number to `day.activeNumbers`. The `onTokenWrite` trigger
 * (step 10) will recompute this; doing it here keeps the queue correct while
 * no trigger runs (emulator against the dev database).
 */
export const bookToken = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Please log in again.');
  const input = readInput(request.data);
  const db = getFirestore();
  const now = pktNow();

  const clinicRef = db.collection('clinics').doc(input.clinicId);
  const doctorRef = db.collection('doctors').doc(input.doctorId);
  const dayRef = doctorRef.collection('days').doc(input.date);
  const patientRef = db.collection('patients').doc(input.patientId);
  const tokenRef = db.collection('tokens').doc();

  const result = await db.runTransaction(async (tx) => {
    const [clinicSnap, doctorSnap, daySnap, patientSnap] = await tx.getAll(clinicRef, doctorRef, dayRef, patientRef);
    if (!clinicSnap.exists || !doctorSnap.exists) throw new HttpsError('not-found', 'Clinic or doctor not found.');
    const clinic = clinicSnap.data()!;
    const doctor = doctorSnap.data() as DoctorData & { tokenPrefix?: string };
    if (doctor.clinicId !== input.clinicId) throw badInput('This doctor is not at this clinic.');

    const patient = patientSnap.data();
    if (!patient || patient.ownerUid !== uid || patient.status !== 'active') {
      throw new HttpsError('permission-denied', 'You can only book for your own family profiles.');
    }

    const day = daySnap.exists ? (daySnap.data() as DayData & Record<string, unknown>) : undefined;

    // BR-1..BR-4
    const unavailable = checkAvailability({ clinicStatus: String(clinic.status), doctor, date: input.date, day, now });
    if (unavailable) throw bookingError(unavailable);

    // BR-5: one active token per profile per doctor per day.
    const duplicate = await tx.get(
      db
        .collection('tokens')
        .where('patientId', '==', input.patientId)
        .where('doctorId', '==', input.doctorId)
        .where('date', '==', input.date)
        .where('status', 'in', ACTIVE_STATUSES)
        .limit(1),
    );
    if (!duplicate.empty) {
      const t = duplicate.docs[0].data();
      throw bookingError('duplicate-token', { name: patient.name, label: `${t.tokenPrefix ?? 'A'}-${t.number}` });
    }

    // BR-6: max 5 active tokens per account.
    const mine = await tx.get(
      db
        .collection('tokens')
        .where('bookedByUserId', '==', uid)
        .where('status', 'in', ACTIVE_STATUSES)
        .limit(MAX_ACTIVE_TOKENS_PER_ACCOUNT),
    );
    if (mine.size >= MAX_ACTIVE_TOKENS_PER_ACCOUNT) throw bookingError('too-many-active');

    // PRD F-09: booking with this doctor fulfils the patient's pending follow-up.
    const followUp = await tx.get(
      db
        .collection('followUps')
        .where('patientId', '==', input.patientId)
        .where('doctorId', '==', input.doctorId)
        .where('status', '==', 'pending')
        .limit(1),
    );
    const followUpRef = followUp.empty ? null : followUp.docs[0].ref;

    // BR-7: sequential per doctor per day.
    const number = Number(day?.lastTokenNumber ?? 0) + 1;
    const activeNumbers = withNumber(day?.activeNumbers as number[] | undefined, number);
    const ts = FieldValue.serverTimestamp();

    tx.set(tokenRef, {
      clinicId: input.clinicId,
      doctorId: input.doctorId,
      date: input.date,
      number,
      tokenPrefix: doctor.tokenPrefix ?? 'A',
      patientId: input.patientId,
      patientSnapshot: {
        name: patient.name,
        birthYear: patient.birthYear ?? null,
        gender: patient.gender,
        relation: patient.relation,
        phone: patient.phone,
      },
      bookedByUserId: uid,
      patientOwnerUid: patient.ownerUid,
      source: followUpRef ? 'followUp' : 'app',
      status: 'booked',
      notified: {},
      followUpId: followUpRef?.id ?? null,
      createdAt: ts,
      arrivedAt: null,
      calledAt: null,
      completedAt: null,
      cancelledAt: null,
      cancelledBy: null,
      waitMinutes: null,
      updatedAt: ts,
    });

    tx.set(
      dayRef,
      {
        clinicId: input.clinicId,
        doctorId: input.doctorId,
        date: input.date,
        ...(day ? {} : { sessionStatus: 'notStarted', currentToken: 0 }),
        lastTokenNumber: number,
        bookedCount: Number(day?.bookedCount ?? 0) + 1,
        activeNumbers,
        waitingCount: activeNumbers.length,
        updatedAt: ts,
      },
      { merge: true },
    );

    if (followUpRef) tx.update(followUpRef, { status: 'booked', bookedTokenId: tokenRef.id, updatedAt: ts });

    return { tokenId: tokenRef.id, number };
  });

  // N-4: a token booked with 3 or fewer ahead gets the step that applies now.
  // Never fail the booking because a notification could not be sent.
  await evaluateQueue(db, getMessaging(), input.doctorId, input.date).catch((e) => logger.warn('notify after booking', e));
  return result;
});
