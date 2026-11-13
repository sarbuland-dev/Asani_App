import type { Firestore } from 'firebase-admin/firestore';

import { ACTIVE_STATUSES } from '../booking/rules';
import { pktNow } from '../lib/dates';

/**
 * PRD D-21: every night at 03:00 PKT, tokens from BEFORE today that are still
 * open are closed, so they stop counting as active (5-token limit, My Tokens →
 * Active). Clinics may run past midnight, so today's tokens are never touched.
 *
 *   Booked                   → noShow
 *   Arrived, On hold, Called → completed
 *
 * Changed tokens get `autoClosed: true` (reports can tell them apart). Like
 * notify.ts it takes `db` as a parameter and writes plain values only (no
 * FieldValue), so tools/admin-scripts/run-auto-close.js can run it before Blaze.
 * Safe to run again: closed tokens are no longer active, so nothing repeats.
 */

export type AutoCloseResult = 'noShow' | 'completed';

/** Pure decision for one token. */
export function decideAutoClose(status: string, date: string, today: string): AutoCloseResult | null {
  if (date >= today) return null;
  if (status === 'booked') return 'noShow';
  if (status === 'arrived' || status === 'onHold' || status === 'called') return 'completed';
  return null;
}

export interface AutoCloseLog {
  tokenId: string;
  label: string;
  date: string;
  from: string;
  to: AutoCloseResult;
}

const BATCH_LIMIT = 400;

export async function runAutoClose(db: Firestore, now: Date = new Date()): Promise<AutoCloseLog[]> {
  const today = pktNow(now).date;
  // Only active tokens are read (small set); the date filter is done here, so
  // no extra composite index is needed.
  const snap = await db.collection('tokens').where('status', 'in', ACTIVE_STATUSES).get();

  const log: AutoCloseLog[] = [];
  const days = new Set<string>();
  let batch = db.batch();
  let pending = 0;

  for (const doc of snap.docs) {
    const t = doc.data();
    const to = decideAutoClose(String(t.status), String(t.date), today);
    if (!to) continue;
    const entry = { action: to === 'noShow' ? 'Auto-closed · No-show' : 'Auto-closed · Completed', by: 'System', at: now };
    batch.update(doc.ref, {
      status: to,
      autoClosed: true,
      ...(to === 'completed' ? { completedAt: t.completedAt ?? now } : {}),
      history: [...(Array.isArray(t.history) ? t.history : []), entry],
      updatedAt: now,
    });
    days.add(`${t.doctorId}|${t.date}`);
    log.push({ tokenId: doc.id, label: `${t.tokenPrefix ?? 'A'}-${t.number}`, date: String(t.date), from: String(t.status), to });
    if (++pending >= BATCH_LIMIT) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }

  // Past days have nobody waiting any more (ARCHITECTURE.md §10 contract).
  for (const key of days) {
    const [doctorId, date] = key.split('|');
    batch.set(
      db.collection('doctors').doc(doctorId).collection('days').doc(date),
      { activeNumbers: [], waitingCount: 0, updatedAt: now },
      { merge: true },
    );
    if (++pending >= BATCH_LIMIT) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (pending > 0) await batch.commit();
  return log;
}
