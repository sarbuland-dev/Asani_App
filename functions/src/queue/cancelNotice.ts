import type { Firestore } from 'firebase-admin/firestore';
import type { Messaging } from 'firebase-admin/messaging';
import { saveToInbox } from '../lib/inbox';

/**
 * PRD D-23: when the CLINIC cancels a token (one token, or a leave-day bulk
 * cancel), the patient's account gets one push with the reason. Tapping it
 * opens booking for the same clinic and doctor. No push for No-show.
 *
 * Separate from the 4 queue notifications (F-06): it never touches
 * `token.notified`. Idempotent: `cancelNotifiedAt` is claimed in a transaction
 * BEFORE sending. Like notify.ts it takes db/messaging as parameters and
 * writes plain values only.
 */

export interface CancelNoticeLog {
  tokenId: string;
  devices: number;
  skipped?: 'not-clinic-cancel' | 'already-sent' | 'no-account' | 'no-devices';
}

/** DESIGN copy for the cancel push. */
export function cancelMessage(label: string, clinicName: string, reason: string | null | undefined): { title: string; body: string } {
  const r = (reason ?? '').trim().replace(/[.\s]+$/, '');
  return {
    title: `Token ${label} cancelled by ${clinicName}`,
    body: r ? `${r}. Tap to book another day.` : 'Tap to book another day.',
  };
}

/** Booking route for "Book another day" (same clinic, doctor and patient). */
export function rebookRoute(t: { clinicId: string; doctorId: string; patientId: string }): string {
  return `/book/${t.clinicId}/${t.doctorId}?patient=${t.patientId}`;
}

export async function notifyClinicCancel(db: Firestore, messaging: Messaging, tokenIds: string[]): Promise<CancelNoticeLog[]> {
  const log: CancelNoticeLog[] = [];
  const clinicNames = new Map<string, string>();

  for (const tokenId of tokenIds) {
    const ref = db.collection('tokens').doc(tokenId);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const claimed = await db.runTransaction(async (tx): Promise<{ t: Record<string, any> } | NonNullable<CancelNoticeLog['skipped']>> => {
      const t = (await tx.get(ref)).data();
      if (!t || t.status !== 'cancelled' || t.cancelledBy !== 'clinic') return 'not-clinic-cancel';
      if (t.cancelNotifiedAt) return 'already-sent';
      tx.update(ref, { cancelNotifiedAt: new Date() });
      return { t };
    });
    if (typeof claimed === 'string') {
      log.push({ tokenId, devices: 0, skipped: claimed });
      continue;
    }
    const t = claimed.t;
    // Walk-ins have no booker; the profile's app account is told (D-22).
    const uid: string | null = t.bookedByUserId ?? t.patientOwnerUid ?? null;
    if (!uid) {
      log.push({ tokenId, devices: 0, skipped: 'no-account' });
      continue;
    }
    if (!clinicNames.has(t.clinicId)) {
      clinicNames.set(t.clinicId, String((await db.collection('clinics').doc(t.clinicId).get()).data()?.name ?? 'the clinic'));
    }
    const { title, body } = cancelMessage(`${t.tokenPrefix ?? 'A'}-${t.number}`, clinicNames.get(t.clinicId)!, t.cancelReason);
    // D-43: in the in-app list even when no phone gets the push.
    await saveToInbox(db, uid, { type: 'cancel', title, body, route: rebookRoute({ clinicId: t.clinicId, doctorId: t.doctorId, patientId: t.patientId }), tokenId });
    const devices = await db.collection('users').doc(uid).collection('devices').get();
    const targets = devices.docs.filter((d) => typeof d.data().fcmToken === 'string');
    if (targets.length === 0) {
      log.push({ tokenId, devices: 0, skipped: 'no-devices' });
      continue;
    }
    const res = await messaging.sendEachForMulticast({
      tokens: targets.map((d) => d.data().fcmToken as string),
      notification: { title, body },
      data: { type: 'cancel', tokenId, route: rebookRoute({ clinicId: t.clinicId, doctorId: t.doctorId, patientId: t.patientId }) },
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
    log.push({ tokenId, devices: res.successCount });
  }
  return log;
}
