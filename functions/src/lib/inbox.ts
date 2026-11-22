import { Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';

/**
 * In-app notifications list (PRD D-45, DESIGN S-19).
 * Every push we send is also saved to users/{uid}/notifications, even when
 * the phone blocks pushes or queue alerts are off, so nothing is missed.
 * Kept 30 days: `expireAt` drives a Firestore TTL policy; the app also
 * filters by `createdAt`.
 */

export const INBOX_DAYS = 30;

export type InboxType = 'queue' | 'cancel' | 'skip' | 'followUp';

export interface InboxEntry {
  type: InboxType;
  title: string;
  body: string;
  /** Where a tap goes, same as the push: /token/{id} or a booking route. */
  route: string;
  tokenId: string | null;
  createdAt: Date;
  expireAt: Date;
}

export function inboxEntry(
  e: { type: InboxType; title: string; body: string; route: string; tokenId?: string | null },
  now = new Date(),
): InboxEntry {
  return {
    type: e.type,
    title: e.title,
    body: e.body,
    route: e.route,
    tokenId: e.tokenId ?? null,
    createdAt: now,
    expireAt: new Date(now.getTime() + INBOX_DAYS * 24 * 3600 * 1000),
  };
}

/** Never throws: a failed save must not stop the push. */
export async function saveToInbox(
  db: Firestore,
  uid: string | null | undefined,
  e: { type: InboxType; title: string; body: string; route: string; tokenId?: string | null },
): Promise<void> {
  if (!uid) return;
  try {
    await db.collection('users').doc(uid).collection('notifications').add(inboxEntry(e));
  } catch (err) {
    logger.error('saveToInbox failed', { uid, error: String(err) });
  }
}
