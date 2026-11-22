import type { Firestore } from 'firebase-admin/firestore';
import type { Messaging } from 'firebase-admin/messaging';
import { saveToInbox } from '../lib/inbox';

/**
 * PRD D-34: when the clinic SKIPS a token (patient not there when called),
 * the patient's account gets one push telling them to go to reception.
 * Tapping it opens the token screen.
 *
 * Separate from the 4 queue notifications (F-06): it never touches
 * `token.notified`. Sent at most once per token: `skipNotifiedAt` is claimed
 * in a transaction BEFORE sending (same pattern as cancelNotice.ts).
 */

export interface SkipNoticeLog {
  tokenId: string;
  devices: number;
  skipped?: 'not-skipped' | 'already-sent' | 'no-account' | 'no-devices';
}

/** DESIGN copy for the skip push. */
export function skipMessage(label: string): { title: string; body: string } {
  return { title: 'You missed your turn', body: `Token ${label} · Go to reception to be called next.` };
}

export async function notifySkipped(db: Firestore, messaging: Messaging, tokenId: string): Promise<SkipNoticeLog> {
  const ref = db.collection('tokens').doc(tokenId);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const claimed = await db.runTransaction(async (tx): Promise<{ t: Record<string, any> } | NonNullable<SkipNoticeLog['skipped']>> => {
    const t = (await tx.get(ref)).data();
    if (!t || t.status !== 'skipped') return 'not-skipped';
    if (t.skipNotifiedAt) return 'already-sent';
    tx.update(ref, { skipNotifiedAt: new Date() });
    return { t };
  });
  if (typeof claimed === 'string') return { tokenId, devices: 0, skipped: claimed };

  const t = claimed.t;
  // Walk-ins have no booker; the profile's app account is told (D-22).
  const uid: string | null = t.bookedByUserId ?? t.patientOwnerUid ?? null;
  if (!uid) return { tokenId, devices: 0, skipped: 'no-account' };
  const { title, body } = skipMessage(`${t.tokenPrefix ?? 'A'}-${t.number}`);
  await saveToInbox(db, uid, { type: 'skip', title, body, route: `/token/${tokenId}`, tokenId }); // D-43
  const devices = await db.collection('users').doc(uid).collection('devices').get();
  const targets = devices.docs.filter((d) => typeof d.data().fcmToken === 'string');
  if (targets.length === 0) return { tokenId, devices: 0, skipped: 'no-devices' };

  const res = await messaging.sendEachForMulticast({
    tokens: targets.map((d) => d.data().fcmToken as string),
    notification: { title, body },
    data: { type: 'skip', tokenId, route: `/token/${tokenId}` },
    android: { priority: 'high', notification: { channelId: 'queue_alerts', tag: tokenId } },
    apns: { payload: { aps: { sound: 'default' } } },
  });
  await Promise.all(
    res.responses.map((r, i) => {
      const code = r.error?.code;
      if (code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token') {
        return targets[i].ref.delete();
      }
      return null;
    }),
  );
  return { tokenId, devices: res.successCount };
}
