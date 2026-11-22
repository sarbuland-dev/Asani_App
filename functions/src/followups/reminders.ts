import type { Firestore } from 'firebase-admin/firestore';
import type { Messaging } from 'firebase-admin/messaging';

import { pktNow } from '../lib/dates';
import { saveToInbox } from '../lib/inbox';

/**
 * Follow-up reminders (PRD F-09, ARCHITECTURE.md §3.5), run daily at 09:00 PKT:
 * - due tomorrow, no reminder yet          → "Follow-up visit tomorrow"
 * - due today, fewer than 2 reminders sent → "Follow-up visit today"
 * - due date passed, still pending         → status `missed` (no notification)
 *
 * Like notify.ts it takes db/messaging as parameters and uses plain Dates, so
 * tools/admin-scripts/run-followup-reminders.js can run it until Blaze.
 */

export type ReminderAction = 'tomorrow' | 'today' | 'missed';

export interface FollowUpData {
  status: string;
  dueDate: string;
  remindersSent?: number;
}

/** Pure decision for one follow-up. */
export function decideReminder(f: FollowUpData, today: string, tomorrow: string): ReminderAction | null {
  if (f.status !== 'pending') return null;
  const sent = f.remindersSent ?? 0;
  if (f.dueDate < today) return 'missed';
  if (f.dueDate === today && sent < 2) return 'today';
  if (f.dueDate === tomorrow && sent === 0) return 'tomorrow';
  return null;
}

/** DESIGN.md §8 copy. */
export function reminderMessage(
  action: 'tomorrow' | 'today',
  patient: string,
  doctor: string,
  clinic: string,
): { title: string; body: string } {
  return action === 'tomorrow'
    ? { title: 'Follow-up visit tomorrow', body: `${patient} · ${doctor}, ${clinic}. Tap to book.` }
    : { title: 'Follow-up visit today', body: `${patient} · ${doctor}. Tap to book your token.` };
}

export function addDays(date: string, days: number): string {
  const [y, m, d] = date.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

export interface ReminderLog {
  followUpId: string;
  action: ReminderAction;
  devices: number;
}

export async function runFollowUpReminders(db: Firestore, messaging: Messaging, now: Date = new Date()): Promise<ReminderLog[]> {
  const today = pktNow(now).date;
  const tomorrow = addDays(today, 1);
  // Index: status + dueDate (DATABASE.md §9).
  const due = await db.collection('followUps').where('status', '==', 'pending').where('dueDate', '<=', tomorrow).get();

  const log: ReminderLog[] = [];
  for (const doc of due.docs) {
    if (!decideReminder(doc.data() as FollowUpData, today, tomorrow)) continue;

    // Claim in a transaction before sending, so a re-run never sends twice.
    const claimed = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      const f = fresh.data();
      if (!f) return null;
      const action = decideReminder(f as FollowUpData, today, tomorrow);
      if (!action) return null;
      if (action === 'missed') {
        tx.update(doc.ref, { status: 'missed', updatedAt: new Date() });
      } else {
        tx.update(doc.ref, { remindersSent: action === 'tomorrow' ? 1 : 2, updatedAt: new Date() });
      }
      return { action, f };
    });
    if (!claimed) continue;
    if (claimed.action === 'missed') {
      log.push({ followUpId: doc.id, action: 'missed', devices: 0 });
      continue;
    }

    const f = claimed.f;
    const [patient, doctor, clinic] = await Promise.all([
      db.collection('patients').doc(f.patientId).get(),
      db.collection('doctors').doc(f.doctorId).get(),
      db.collection('clinics').doc(f.clinicId).get(),
    ]);
    const { title, body } = reminderMessage(
      claimed.action,
      patient.data()?.name ?? 'Your family member',
      doctor.data()?.name ?? 'the doctor',
      clinic.data()?.name ?? 'the clinic',
    );
    log.push({ followUpId: doc.id, action: claimed.action, devices: await send(db, messaging, f, doc.id, title, body) });
  }
  return log;
}

async function send(
  db: Firestore,
  messaging: Messaging,
  f: Record<string, any>,
  followUpId: string,
  title: string,
  body: string,
): Promise<number> {
  if (!f.ownerUid) return 0;
  // Tapping opens booking pre-filled (PRD F-09).
  const route = `/book/${f.clinicId}/${f.doctorId}?patient=${f.patientId}&date=${f.dueDate}`;
  await saveToInbox(db, f.ownerUid, { type: 'followUp', title, body, route }); // D-45
  const devices = await db.collection('users').doc(f.ownerUid).collection('devices').get();
  const tokens = devices.docs.map((d) => d.data().fcmToken).filter((t): t is string => typeof t === 'string');
  if (tokens.length === 0) return 0;
  const res = await messaging.sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: { type: 'followUp', followUpId, route },
    android: { notification: { channelId: 'follow_ups' } },
  });
  return res.successCount;
}
