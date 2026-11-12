import { createHash } from 'node:crypto';

import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue, Firestore, DocumentReference, WriteBatch } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions/v2';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { callableOptions } from '../lib/options';
import { withoutNumber } from '../booking/rules';
import { evaluateQueue } from '../queue/notify';

/** Statuses the account's tokens are cancelled from (still waiting in a queue). */
const CANCEL_ON_DELETE = ['booked', 'arrived', 'onHold'];
export const DELETED_NAME = 'Deleted user';

/**
 * PRD F-10, docs/04 §8 (required by Google Play and the App Store):
 * 1. verify the caller  2. cancel their waiting tokens  3. delete users/{uid} + devices
 * 4. anonymise app-created profiles and the names in their tokens
 * 5. delete the Auth user  6. log an anonymised audit line.
 * Clinic visit records stay, without personal data. Safe to retry.
 */
export const deleteAccount = onCall(callableOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Please log in again.');
  const db = getFirestore();

  // 2. Cancel waiting tokens, freeing their places in the queue.
  const waiting = await db
    .collection('tokens')
    .where('bookedByUserId', '==', uid)
    .where('status', 'in', CANCEL_ON_DELETE)
    .get();
  const queues = new Set<string>();
  for (const doc of waiting.docs) {
    const moved = await cancelForDeletion(db, doc.ref);
    if (moved) queues.add(moved);
  }

  // 4. Profiles this account created in the app, and their visit records.
  const profiles = await db.collection('patients').where('ownerUid', '==', uid).get();
  const appProfiles = profiles.docs.filter((d) => d.data().createdBy === 'app');
  const tokenRefs = new Map<string, DocumentReference>();
  for (const q of [
    db.collection('tokens').where('bookedByUserId', '==', uid),
    db.collection('tokens').where('patientOwnerUid', '==', uid),
  ]) {
    for (const d of (await q.get()).docs) tokenRefs.set(d.id, d.ref);
  }
  const followUps = await db.collection('followUps').where('ownerUid', '==', uid).get();
  const devices = await db.collection('users').doc(uid).collection('devices').get();

  const now = FieldValue.serverTimestamp();
  const writes: Array<(b: WriteBatch) => void> = [
    ...appProfiles.map((d) => (b: WriteBatch) =>
      b.update(d.ref, {
        name: DELETED_NAME,
        nameLower: DELETED_NAME.toLowerCase(),
        patientPhone: null,
        phone: null,
        ownerUid: null,
        status: 'deleted',
        updatedAt: now,
      }),
    ),
    ...[...tokenRefs.values()].map((ref) => (b: WriteBatch) =>
      b.update(ref, { 'patientSnapshot.name': DELETED_NAME, 'patientSnapshot.phone': null, updatedAt: now }),
    ),
    // No reminders to an account that no longer exists.
    ...followUps.docs.map((d) => (b: WriteBatch) => b.update(d.ref, { ownerUid: null, updatedAt: now })),
    // 3. The account itself.
    ...devices.docs.map((d) => (b: WriteBatch) => b.delete(d.ref)),
    (b: WriteBatch) => b.delete(db.collection('users').doc(uid)),
  ];
  for (let i = 0; i < writes.length; i += 400) {
    const batch = db.batch();
    writes.slice(i, i + 400).forEach((w) => w(batch));
    await batch.commit();
  }

  // 5. Auth user (already gone on a retry).
  await getAuth()
    .deleteUser(uid)
    .catch((e) => {
      if (e?.code !== 'auth/user-not-found') throw e;
    });

  // Patients behind the cancelled tokens move up (notifications).
  for (const key of queues) {
    const [doctorId, date] = key.split('|');
    await evaluateQueue(db, getMessaging(), doctorId, date).catch((e) => logger.warn('notify after delete', e));
  }

  // 6. Anonymised audit line: no uid, no phone, no names.
  logger.info('account deleted', {
    uidHash: createHash('sha256').update(uid).digest('hex').slice(0, 16),
    profiles: appProfiles.length,
    tokens: tokenRefs.size,
    cancelled: waiting.size,
  });
  return { ok: true };
});

/** Cancels one waiting token and removes its number from the queue day. Returns "doctorId|date". */
async function cancelForDeletion(db: Firestore, ref: DocumentReference): Promise<string | null> {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const t = snap.data();
    if (!t || !CANCEL_ON_DELETE.includes(t.status)) return null;
    const dayRef = db.collection('doctors').doc(t.doctorId).collection('days').doc(t.date);
    const day = await tx.get(dayRef);
    const ts = FieldValue.serverTimestamp();
    tx.update(ref, { status: 'cancelled', cancelledAt: ts, cancelledBy: 'patient', updatedAt: ts });
    if (day.exists) {
      const activeNumbers = withoutNumber(day.data()!.activeNumbers, t.number);
      tx.update(dayRef, { activeNumbers, waitingCount: activeNumbers.length, updatedAt: ts });
    }
    return `${t.doctorId}|${t.date}`;
  });
}
