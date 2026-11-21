import { FieldValue, Firestore, Timestamp } from 'firebase-admin/firestore';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions/v2';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { WAITING_STATUSES } from '../booking/rules';
import { Actor, actorLabel, id, input, optStr, requireClinic } from '../lib/access';
import { pktNow } from '../lib/dates';
import { callableOptions } from '../lib/options';
import { notifyClinicCancel } from '../queue/cancelNotice';
import { evaluateQueue } from '../queue/notify';
import { notifySkipped } from '../queue/skipNotice';
import { turnRepeatOnSkip, turnRepeatOnUndo } from '../queue/steps';
import { NextCandidate, needsArrivalConfirm, pickNext } from './nextOrder';

/**
 * PRD-CLINIC-WEB C-02..C-04, BW-1..BW-4: every queue change from the clinic
 * web goes through here, so statuses stay correct and are logged in the
 * token's history. Writes only the fields of the ARCHITECTURE.md §10 contract,
 * so the patient app keeps working unchanged.
 */
const SESSION = ['start', 'pause', 'end', 'next', 'undo'] as const;
const TOKEN = ['arrive', 'callNow', 'skip', 'hold', 'backToQueue', 'cancel', 'noShow', 'reprint'] as const;
type Action = (typeof SESSION)[number] | (typeof TOKEN)[number];

const UNDO_SECONDS = 30;
const READ_ONLY_STATUSES = ['suspended', 'cancelled'];

/** One history line (PRD C-04: "Every action is logged (who, when)"). */
export function historyEntry(action: string, actor: Actor, note?: string | null) {
  return { action, by: actorLabel(actor), at: Timestamp.now(), ...(note ? { note } : {}) };
}

/** Same as onTokenWrite: activeNumbers = numbers still waiting (runs without triggers too). */
export async function syncDay(db: Firestore, doctorId: string, date: string): Promise<void> {
  const tokens = await db
    .collection('tokens')
    .where('doctorId', '==', doctorId)
    .where('date', '==', date)
    .where('status', 'in', WAITING_STATUSES)
    .get();
  const activeNumbers = tokens.docs.map((d) => d.data().number as number).sort((a, b) => a - b);
  await db
    .collection('doctors')
    .doc(doctorId)
    .collection('days')
    .doc(date)
    .set({ activeNumbers, waitingCount: activeNumbers.length, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
}

function minutesBetween(from: Timestamp | null | undefined, to: Date): number | null {
  if (!from) return null;
  return Math.max(0, Math.round((to.getTime() - from.toDate().getTime()) / 60000));
}

export const queueAction = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const d = input(request);
  const action = d.action as Action;
  if (![...SESSION, ...TOKEN].includes(action)) throw new HttpsError('invalid-argument', 'Unknown action.');
  const actor = await requireClinic(db, request);
  const clinic = (await db.collection('clinics').doc(actor.clinicId).get()).data();
  if (READ_ONLY_STATUSES.includes(String(clinic?.status)) && action !== 'reprint') {
    throw new HttpsError('failed-precondition', 'This clinic is suspended. The queue is read-only until the payment is recorded.', { code: 'suspended' });
  }
  const today = pktNow().date;
  const reason = optStr(d, 'reason', 80);
  const ts = FieldValue.serverTimestamp();

  let doctorId: string;
  let date = today;
  let called: { id: string; label: string; name: string } | null = null;

  if ((SESSION as readonly string[]).includes(action)) {
    doctorId = id(d, 'doctorId');
    const doctorRef = db.collection('doctors').doc(doctorId);
    const dayRef = doctorRef.collection('days').doc(today);
    const doctor = (await doctorRef.get()).data();
    if (!doctor || doctor.clinicId !== actor.clinicId) throw new HttpsError('not-found', 'Doctor not found.');

    if (action === 'start' || action === 'pause') {
      await dayRef.set(
        {
          clinicId: actor.clinicId,
          doctorId,
          date: today,
          sessionStatus: action === 'start' ? 'running' : 'paused',
          updatedAt: ts,
        },
        { merge: true },
      );
    } else if (action === 'end') {
      // C-02: remaining Booked → No-show; the patient being seen is completed.
      const open = await db.collection('tokens').where('doctorId', '==', doctorId).where('date', '==', today).where('status', 'in', ['booked', 'called']).get();
      const batch = db.batch();
      const now = new Date();
      for (const t of open.docs) {
        const done = t.data().status === 'called';
        batch.update(t.ref, {
          status: done ? 'completed' : 'noShow',
          ...(done ? { completedAt: now } : {}),
          history: FieldValue.arrayUnion(historyEntry(done ? 'Completed' : 'No-show (session ended)', actor)),
          updatedAt: ts,
        });
      }
      batch.set(dayRef, { clinicId: actor.clinicId, doctorId, date: today, sessionStatus: 'ended', undo: FieldValue.delete(), updatedAt: ts }, { merge: true });
      await batch.commit();
    } else if (action === 'next') {
      called = await db.runTransaction(async (tx) => {
        const day = (await tx.get(dayRef)).data();
        const session = day?.sessionStatus ?? 'notStarted';
        if (session === 'notStarted') throw new HttpsError('failed-precondition', 'Start the session first.', { code: 'not-started' });
        if (session === 'paused') throw new HttpsError('failed-precondition', 'The session is paused. Resume it first.', { code: 'paused' });
        if (session === 'ended') throw new HttpsError('failed-precondition', "Today's session has ended.", { code: 'ended' });
        const snap = await tx.get(
          db.collection('tokens').where('doctorId', '==', doctorId).where('date', '==', today).where('status', 'in', ['called', 'arrived', 'booked']),
        );
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const list: Array<NextCandidate & Record<string, any>> = snap.docs.map((s) => ({
          ...s.data(),
          id: s.id,
          number: Number(s.data().number),
          status: String(s.data().status),
          ref: s.ref,
          priorityAt: s.data().priorityAt?.toMillis?.() ?? null,
        }));
        const current = list.find((t) => t.status === 'called');
        // D-24: strict token number order (+ re-checked-in Skipped patients first).
        const candidate = pickNext(list.filter((t) => t.status !== 'called'));
        if (!current && !candidate) throw new HttpsError('failed-precondition', 'No patients waiting.', { code: 'empty' });
        if (needsArrivalConfirm(candidate, optStr(d, 'callNotArrived', 40))) {
          const label = `${candidate!.tokenPrefix ?? 'A'}-${candidate!.number}`;
          // Nothing is written; the web asks "Skip / Call anyway" and calls again.
          throw new HttpsError('failed-precondition', `${label} has not arrived.`, {
            code: 'not-arrived',
            tokenId: candidate!.id,
            label,
            name: String(candidate!.patientSnapshot?.name ?? ''),
          });
        }
        const now = new Date();
        if (current) {
          tx.update(current.ref, { status: 'completed', completedAt: now, history: FieldValue.arrayUnion(historyEntry('Completed', actor)), updatedAt: ts });
        }
        if (candidate) {
          tx.update(candidate.ref, {
            status: 'called',
            calledAt: now,
            waitMinutes: minutesBetween(candidate.arrivedAt ?? candidate.createdAt, now),
            history: FieldValue.arrayUnion(historyEntry('Called (Next)', actor)),
            updatedAt: ts,
          });
        }
        tx.set(
          dayRef,
          {
            currentToken: candidate?.number ?? day?.currentToken ?? 0,
            // C-03 "Undo last Next" for 30 seconds.
            undo: {
              at: now,
              completedId: current?.ref.id ?? null,
              calledId: candidate?.ref.id ?? null,
              calledPrevStatus: candidate?.status ?? null,
              prevCurrent: day?.currentToken ?? 0,
            },
            updatedAt: ts,
          },
          { merge: true },
        );
        return candidate
          ? { id: candidate.ref.id, label: `${candidate.tokenPrefix ?? 'A'}-${candidate.number}`, name: String(candidate.patientSnapshot?.name ?? '') }
          : null;
      });
    } else {
      // undo
      await db.runTransaction(async (tx) => {
        const day = (await tx.get(dayRef)).data();
        // D-38: read the called token first (reads before writes) for the one-time repeat.
        const calledTok = day?.undo?.calledId ? (await tx.get(db.collection('tokens').doc(day.undo.calledId))).data() : undefined;
        const u = day?.undo;
        const at: Date | null = u?.at?.toDate ? u.at.toDate() : null;
        if (!u || !at || Date.now() - at.getTime() > UNDO_SECONDS * 1000) {
          throw new HttpsError('failed-precondition', 'Undo is no longer available.', { code: 'undo-expired' });
        }
        if (u.completedId) {
          tx.update(db.collection('tokens').doc(u.completedId), {
            status: 'called',
            completedAt: null,
            history: FieldValue.arrayUnion(historyEntry('Undo last Next', actor)),
            updatedAt: ts,
          });
        }
        if (u.calledId) {
          tx.update(db.collection('tokens').doc(u.calledId), {
            status: u.calledPrevStatus ?? 'arrived',
            calledAt: null,
            waitMinutes: null,
            // D-38: no push on undo; one more "Your turn now" when really called.
            ...(calledTok && turnRepeatOnUndo(calledTok) ? { 'notified.yourTurn': FieldValue.delete(), turnRepeatUsed: true } : {}),
            history: FieldValue.arrayUnion(historyEntry('Undo last Next', actor)),
            updatedAt: ts,
          });
        }
        tx.update(dayRef, { currentToken: u.prevCurrent ?? 0, undo: FieldValue.delete(), updatedAt: ts });
      });
    }
  } else {
    // ---- one token ----
    const tokenRef = db.collection('tokens').doc(id(d, 'tokenId'));
    const result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(tokenRef);
      const t = snap.data();
      if (!t || t.clinicId !== actor.clinicId) throw new HttpsError('not-found', 'Token not found.');
      const status = String(t.status);
      if (status === 'completed' && action !== 'reprint') {
        throw new HttpsError('failed-precondition', 'A completed token cannot be changed.', { code: 'completed' }); // BW-4
      }
      const allowed: Record<string, string[]> = {
        arrive: ['booked', 'skipped'], // D-24: a Skipped patient may check in later
        callNow: ['booked', 'arrived', 'onHold', 'skipped'],
        skip: ['booked', 'arrived', 'called'],
        hold: ['booked', 'arrived', 'called'],
        backToQueue: ['onHold', 'skipped'],
        cancel: ['booked', 'arrived', 'onHold'],
        noShow: ['booked', 'arrived', 'onHold', 'skipped'],
        reprint: ['arrived', 'called', 'completed', 'onHold'],
      };
      if (!allowed[action].includes(status)) {
        throw new HttpsError('failed-precondition', `This token is ${status}; that action is not possible now.`, { code: 'bad-status' });
      }
      const now = new Date();
      const dayRef = db.collection('doctors').doc(t.doctorId).collection('days').doc(t.date);
      const hist = (label: string, note?: string | null) => FieldValue.arrayUnion(historyEntry(label, actor, note));
      switch (action) {
        case 'arrive':
          // D-24: a Skipped patient who checks in is called right after the current patient.
          tx.update(tokenRef, {
            status: 'arrived',
            arrivedAt: now,
            ...(status === 'skipped' ? { priorityAt: now } : {}),
            history: hist(status === 'skipped' ? 'Arrived after skip · called next' : 'Arrived'),
            updatedAt: ts,
          });
          break;
        case 'callNow': {
          // BW-3: one Called token per doctor; the current one is completed.
          const current = await tx.get(
            db.collection('tokens').where('doctorId', '==', t.doctorId).where('date', '==', t.date).where('status', '==', 'called'),
          );
          for (const c of current.docs) {
            if (c.id !== tokenRef.id) tx.update(c.ref, { status: 'completed', completedAt: now, history: hist('Completed'), updatedAt: ts });
          }
          tx.update(tokenRef, {
            status: 'called',
            calledAt: now,
            arrivedAt: t.arrivedAt ?? now,
            waitMinutes: minutesBetween(t.arrivedAt ?? t.createdAt, now),
            history: hist(status === 'skipped' ? 'Recalled' : 'Called (out of order)'),
            updatedAt: ts,
          });
          tx.set(dayRef, { currentToken: t.number, undo: FieldValue.delete(), updatedAt: ts }, { merge: true });
          break;
        }
        case 'skip':
          tx.update(tokenRef, {
            status: 'skipped',
            priorityAt: FieldValue.delete(),
            // D-35: one more "Your turn now" when recalled (max once per token).
            ...(turnRepeatOnSkip(t) ? { 'notified.yourTurn': FieldValue.delete(), turnRepeatUsed: true } : {}),
            history: hist('Skipped'),
            updatedAt: ts,
          });
          break;
        case 'hold':
          tx.update(tokenRef, { status: 'onHold', priorityAt: FieldValue.delete(), history: hist('On hold', reason), updatedAt: ts });
          break;
        case 'backToQueue':
          // D-24: back from Skipped = checked in again → called right after the current patient.
          tx.update(tokenRef, {
            status: 'arrived',
            arrivedAt: t.arrivedAt ?? now,
            ...(status === 'skipped' ? { priorityAt: now } : {}),
            history: hist(status === 'skipped' ? 'Back to queue · called next' : 'Back to queue'),
            updatedAt: ts,
          });
          break;
        case 'cancel':
          tx.update(tokenRef, {
            status: 'cancelled',
            cancelledAt: now,
            cancelledBy: 'clinic',
            cancelReason: reason,
            history: hist('Cancelled', reason),
            updatedAt: ts,
          });
          break;
        case 'noShow':
          tx.update(tokenRef, { status: 'noShow', history: hist('Marked No-show'), updatedAt: ts });
          break;
        case 'reprint':
          tx.update(tokenRef, { history: hist('Reprinted'), updatedAt: ts });
          break;
      }
      return { doctorId: String(t.doctorId), date: String(t.date) };
    });
    doctorId = result.doctorId;
    date = result.date;
  }

  // Keep the queue numbers right and notify patients (works without triggers).
  await syncDay(db, doctorId, date);
  await evaluateQueue(db, getMessaging(), doctorId, date).catch((e) => logger.warn('notify after queueAction', e));
  // D-23: the patient is told when the clinic cancels (separate from the 4 queue alerts).
  if (action === 'cancel') {
    await notifyClinicCancel(db, getMessaging(), [id(d, 'tokenId')]).catch((e) => logger.warn('cancel notice', e));
  }
  // D-34: one push when the patient is skipped (separate from the 4 queue alerts).
  if (action === 'skip') {
    await notifySkipped(db, getMessaging(), id(d, 'tokenId')).catch((e) => logger.warn('skip notice', e));
  }
  return { ok: true, called };
});
