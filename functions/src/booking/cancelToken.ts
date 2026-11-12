import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions/v2';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { callableOptions } from '../lib/options';
import { badInput } from '../lib/errors';
import { CANCELLABLE_STATUSES, withoutNumber } from './rules';
import { evaluateQueue } from '../queue/notify';

/**
 * PRD F-05: the patient cancels their own token while it is booked or arrived.
 * The number leaves `day.activeNumbers` in the same transaction (see bookToken).
 * Cancelling twice is safe: a cancelled token is reported as already done.
 */
export const cancelToken = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Please log in again.');
  const tokenId = (request.data ?? {}).tokenId;
  if (typeof tokenId !== 'string' || tokenId.length === 0 || tokenId.length > 128 || tokenId.includes('/')) {
    throw badInput('tokenId is required.');
  }

  const db = getFirestore();
  const tokenRef = db.collection('tokens').doc(tokenId);

  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(tokenRef);
    const token = snap.data();
    if (!token || token.bookedByUserId !== uid) throw new HttpsError('not-found', 'Token not found.');
    if (token.status === 'cancelled') return { ok: true, doctorId: null as string | null, date: '' };
    if (!CANCELLABLE_STATUSES.includes(token.status)) {
      throw new HttpsError('failed-precondition', 'This token can no longer be cancelled.', { code: 'cannot-cancel' });
    }

    const dayRef = db.collection('doctors').doc(token.doctorId).collection('days').doc(token.date);
    const daySnap = await tx.get(dayRef);
    const ts = FieldValue.serverTimestamp();

    tx.update(tokenRef, { status: 'cancelled', cancelledAt: ts, cancelledBy: 'patient', updatedAt: ts });
    if (daySnap.exists) {
      const activeNumbers = withoutNumber(daySnap.data()!.activeNumbers, token.number);
      tx.update(dayRef, { activeNumbers, waitingCount: activeNumbers.length, updatedAt: ts });
    }
    return { ok: true, doctorId: token.doctorId as string, date: token.date as string };
  });

  // Patients behind may now get their next step (ARCHITECTURE.md §3.4).
  if (result.doctorId) {
    await evaluateQueue(db, getMessaging(), result.doctorId, result.date).catch((e) => logger.warn('notify after cancel', e));
  }
  return { ok: true };
});
