import type { Firestore } from 'firebase-admin/firestore';
import type { Messaging } from 'firebase-admin/messaging';

import { StepKey, messageFor, nextStep, patientsAhead } from './steps';
import { saveToInbox } from '../lib/inbox';

/**
 * ARCHITECTURE.md §3.3: after any queue change, send each token the one step
 * that now applies (PRD F-06). Safe to run any number of times: the
 * `token.notified` map is set in a transaction BEFORE sending, so a step is
 * never sent twice, even if two runs overlap.
 *
 * Takes `db` and `messaging` as parameters (type-only imports, plain Date
 * timestamps) so tools/queue-sim can call it with its own Admin SDK.
 */
export interface SentLog {
  tokenId: string;
  step: StepKey;
  devices: number;
  skipped?: 'alerts-off' | 'no-devices';
}

export async function evaluateQueue(db: Firestore, messaging: Messaging, doctorId: string, date: string): Promise<SentLog[]> {
  const doctorRef = db.collection('doctors').doc(doctorId);
  const [daySnap, doctorSnap, tokensSnap] = await Promise.all([
    doctorRef.collection('days').doc(date).get(),
    doctorRef.get(),
    db
      .collection('tokens')
      .where('doctorId', '==', doctorId)
      .where('date', '==', date)
      .where('status', 'in', ['booked', 'arrived', 'called'])
      .get(),
  ]);
  const activeNumbers: number[] = daySnap.data()?.activeNumbers ?? [];
  const doctorName: string = doctorSnap.data()?.name ?? 'the doctor';

  // D-39: someone is with the doctor → the first waiting patient gets "You're next" even at 0 ahead.
  const withDoctor = tokensSnap.docs.some((d) => d.data().status === 'called');

  const log: SentLog[] = [];
  for (const doc of tokensSnap.docs) {
    const t = doc.data();
    if (!nextStep(t.status, patientsAhead(activeNumbers, t.number), t.notified ?? {}, withDoctor)) continue;

    // Claim the step in a transaction; only the run that claims it sends.
    const claimed = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      const ft = fresh.data();
      if (!ft) return null;
      const decision = nextStep(ft.status, patientsAhead(activeNumbers, ft.number), ft.notified ?? {}, withDoctor);
      if (!decision) return null;
      const now = new Date();
      const notified = { ...(ft.notified ?? {}) };
      for (const k of decision.mark) notified[k] = now;
      tx.update(doc.ref, { notified, updatedAt: now });
      return { step: decision.send, token: ft };
    });
    if (!claimed) continue;

    const { title, body } = messageFor(claimed.step, `${claimed.token.tokenPrefix ?? 'A'}-${claimed.token.number}`, doctorName);
    // Walk-ins have no booker; the profile's app account gets the alerts (D-22).
    const uid = claimed.token.bookedByUserId ?? claimed.token.patientOwnerUid;
    log.push(await sendToOwner(db, messaging, doc.id, claimed.step, uid, title, body));
  }
  return log;
}

/** N-5: to the account owner's devices, unless they turned queue alerts off (D-18). */
async function sendToOwner(
  db: Firestore,
  messaging: Messaging,
  tokenId: string,
  step: StepKey,
  uid: string | null | undefined,
  title: string,
  body: string,
): Promise<SentLog> {
  if (!uid) return { tokenId, step, devices: 0, skipped: 'no-devices' };
  // D-43: saved to the in-app list even if alerts are off or no phone gets it.
  await saveToInbox(db, uid, { type: 'queue', title, body, route: `/token/${tokenId}`, tokenId });
  const userRef = db.collection('users').doc(uid);
  const [user, devices] = await Promise.all([userRef.get(), userRef.collection('devices').get()]);
  if (user.data()?.queueAlertsEnabled === false) return { tokenId, step, devices: 0, skipped: 'alerts-off' };

  const targets = devices.docs.filter((d) => typeof d.data().fcmToken === 'string');
  if (targets.length === 0) return { tokenId, step, devices: 0, skipped: 'no-devices' };

  const res = await messaging.sendEachForMulticast({
    tokens: targets.map((d) => d.data().fcmToken as string),
    notification: { title, body },
    data: { type: 'queue', tokenId, step, route: `/token/${tokenId}` },
    android: { priority: 'high', notification: { channelId: 'queue_alerts', tag: `${tokenId}` } },
    apns: { payload: { aps: { sound: 'default' } } },
  });

  // Remove tokens FCM no longer knows (cleanupStaleDevices does this weekly too).
  await Promise.all(
    res.responses.map((r, i) => {
      const code = r.error?.code;
      if (code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token') {
        return targets[i].ref.delete();
      }
      return null;
    }),
  );
  return { tokenId, step, devices: res.successCount };
}
