import { randomBytes } from 'node:crypto';

import { FieldValue, Firestore, getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { logger } from 'firebase-functions/v2';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { Actor, id, input, int, logActivity, optStr, requireSuperAdmin, str } from '../lib/access';
import { pktNow } from '../lib/dates';
import { REGION, callableOptions } from '../lib/options';

const PLANS = ['pilot', 'basic', 'premium'];
const METHODS = ['bank', 'jazzCash', 'easypaisa', 'cash'];
const CLINIC_STATUSES = ['pilot', 'active', 'grace', 'suspended', 'cancelled'];
const PRINT_FORMATS = ['thermal80', 'a5', 'none'];
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

/** Defaults for settings/billing (A-08). */
export const DEFAULT_SETTINGS = {
  prices: { pilot: 0, basic: 3000, premium: 5000 },
  pilotDays: 30,
  billingDay: 1,
  dueDays: 7,
  graceDays: 7,
  suspendDays: 15,
  paymentInstructions: 'Bank / JazzCash / Easypaisa details will be shared by Asani. Send the transaction ID after paying.',
};

async function billingSettings(db: Firestore) {
  const s = (await db.collection('settings').doc('billing').get()).data();
  return { ...DEFAULT_SETTINGS, ...(s ?? {}) };
}

/** Words of name + area and their prefixes (same as tools/admin-scripts/seed-dev.js). */
function searchKeywords(...parts: string[]): string[] {
  const out = new Set<string>();
  for (const word of parts.join(' ').toLowerCase().split(/[^a-z0-9]+/)) {
    for (let i = 2; i <= word.length; i++) out.add(word.slice(0, i));
  }
  return [...out].sort();
}

const addDays = (d: Date, n: number) => new Date(d.getTime() + n * 86_400_000);

// ======================================================================
// A-04 New clinic wizard: clinic + billing + the clinic's single login.
// Doctors are not added here; the clinic adds them itself (D-19).
// The client then calls sendPasswordResetEmail(email): Firebase sends the
// "Set your Asani password" email (template set in the console).
// ======================================================================
export const adminCreateClinic = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const d = input(request);
  const actor = await requireSuperAdmin(db, request);
  const email = str(d, 'email', 120).toLowerCase();
  if (!EMAIL.test(email)) throw new HttpsError('invalid-argument', 'Enter a valid clinic email.');
  const name = str(d, 'name', 80);
  const area = str(d, 'area', 60);
  const city = str(d, 'city', 40);
  const printFormat = str(d, 'printFormat', 12);
  if (!PRINT_FORMATS.includes(printFormat)) throw new HttpsError('invalid-argument', 'Unknown print format.');
  const planAfterPilot = str(d, 'planAfterPilot', 10);
  if (!['basic', 'premium'].includes(planAfterPilot)) throw new HttpsError('invalid-argument', 'Unknown plan.');
  const pilotDays = int(d, 'pilotDays', 0, 365);

  const auth = getAuth();
  try {
    await auth.getUserByEmail(email);
    throw new HttpsError('already-exists', 'An account with this email already exists.', { code: 'email-taken' });
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    if ((e as { code?: string }).code !== 'auth/user-not-found') throw e;
  }

  const clinicRef = db.collection('clinics').doc();
  const ts = FieldValue.serverTimestamp();
  const now = new Date();
  // Random password nobody knows; the manager sets their own from the email.
  const user = await auth.createUser({ email, password: randomBytes(24).toString('base64url'), displayName: name, emailVerified: false });
  await auth.setCustomUserClaims(user.uid, { role: 'clinic', clinicId: clinicRef.id });

  const batch = db.batch();
  batch.set(clinicRef, {
    name,
    nameLower: name.toLowerCase(),
    area,
    city,
    address: str(d, 'address', 120),
    phone: str(d, 'phone', 20),
    location: null,
    searchKeywords: searchKeywords(name, area),
    status: 'pilot',
    doctorCount: 0,
    nextDoctorLetter: 0,
    timezone: 'Asia/Karachi',
    printFormat,
    createdAt: ts,
    updatedAt: ts,
  });
  batch.set(clinicRef.collection('private').doc('billing'), {
    plan: 'pilot',
    planAfterPilot,
    monthlyFee: int(d, 'monthlyFee', 0, 1_000_000),
    billingDay: int(d, 'billingDay', 1, 28),
    pilotEndsAt: addDays(now, pilotDays),
    paidUntil: null,
    ownerName: str(d, 'ownerName', 60),
    ownerPhone: str(d, 'ownerPhone', 20),
    email,
    createdAt: ts,
  });
  batch.set(db.collection('clinicAccounts').doc(user.uid), {
    email,
    clinicId: clinicRef.id,
    name: str(d, 'ownerName', 60),
    status: 'invited',
    invitedAt: ts,
    lastLoginAt: null,
    createdAt: ts,
  });
  await batch.commit();
  await logActivity(db, actor, clinicRef.id, 'created clinic', name);
  await logActivity(db, actor, clinicRef.id, 'invited clinic login', email);
  return { clinicId: clinicRef.id, email };
});

async function loginOf(db: Firestore, clinicId: string) {
  const snap = await db.collection('clinicAccounts').where('clinicId', '==', clinicId).limit(1).get();
  if (snap.empty) throw new HttpsError('not-found', 'This clinic has no login yet.');
  return snap.docs[0];
}

/** Logs the resend; the client sends the email (sendPasswordResetEmail). */
export const adminResendClinicInvite = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const actor = await requireSuperAdmin(db, request);
  const clinicId = id(input(request), 'clinicId');
  const login = await loginOf(db, clinicId);
  await login.ref.update({ invitedAt: FieldValue.serverTimestamp() });
  await logActivity(db, actor, clinicId, 'resent clinic login invite', String(login.data().email));
  return { email: login.data().email };
});

/** §5.4: disabling signs the clinic out everywhere within minutes. */
export const adminSetClinicLogin = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const d = input(request);
  const actor = await requireSuperAdmin(db, request);
  const clinicId = id(d, 'clinicId');
  const disabled = d.status === 'disabled';
  const login = await loginOf(db, clinicId);
  await getAuth().updateUser(login.id, { disabled });
  if (disabled) await getAuth().revokeRefreshTokens(login.id);
  const wasInvited = login.data().status === 'invited';
  await login.ref.update({ status: disabled ? 'disabled' : wasInvited ? 'invited' : 'active' });
  await logActivity(db, actor, clinicId, disabled ? 'disabled clinic login' : 'enabled clinic login', String(login.data().email));
  return { ok: true };
});

export const adminSetClinicStatus = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const d = input(request);
  const actor = await requireSuperAdmin(db, request);
  const clinicId = id(d, 'clinicId');
  const status = str(d, 'status', 12);
  if (!CLINIC_STATUSES.includes(status)) throw new HttpsError('invalid-argument', 'Unknown status.');
  const ref = db.collection('clinics').doc(clinicId);
  const clinic = (await ref.get()).data();
  if (!clinic) throw new HttpsError('not-found', 'Clinic not found.');
  await ref.update({ status, updatedAt: FieldValue.serverTimestamp() });
  const reason = optStr(d, 'reason', 80);
  const verb = status === 'suspended' ? 'suspended clinic' : status === 'cancelled' ? 'cancelled clinic' : 'reactivated clinic';
  await logActivity(db, actor, clinicId, verb, reason ? `${clinic.name} · ${reason}` : String(clinic.name));
  return { ok: true };
});

export const adminChangePlan = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const d = input(request);
  const actor = await requireSuperAdmin(db, request);
  const clinicId = id(d, 'clinicId');
  const plan = str(d, 'plan', 10);
  if (!PLANS.includes(plan)) throw new HttpsError('invalid-argument', 'Unknown plan.');
  const monthlyFee = int(d, 'monthlyFee', 0, 1_000_000);
  await db.collection('clinics').doc(clinicId).collection('private').doc('billing').set({ plan, monthlyFee }, { merge: true });
  await logActivity(db, actor, clinicId, 'changed plan', `${plan} · Rs ${monthlyFee}`);
  return { ok: true };
});

export const adminExtendPilot = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const d = input(request);
  const actor = await requireSuperAdmin(db, request);
  const clinicId = id(d, 'clinicId');
  const days = int(d, 'days', 1, 90);
  const billingRef = db.collection('clinics').doc(clinicId).collection('private').doc('billing');
  const b = (await billingRef.get()).data();
  const cur: Date = b?.pilotEndsAt?.toDate?.() ?? new Date();
  const base = cur > new Date() ? cur : new Date();
  await billingRef.set({ plan: 'pilot', pilotEndsAt: addDays(base, days) }, { merge: true });
  await db.collection('clinics').doc(clinicId).update({ status: 'pilot', updatedAt: FieldValue.serverTimestamp() });
  await logActivity(db, actor, clinicId, `extended pilot by ${days} days`, clinicId);
  return { ok: true };
});

// ======================================================================
// A-05 / A-06 payments, invoices, defaulters.
// ======================================================================
/** Only an open invoice (unpaid / overdue) can be paid or waived, once. */
export function canRecordPayment(status: string): boolean {
  return status === 'unpaid' || status === 'overdue';
}

/** Payment date from the client (ms since epoch); anything odd → now. Not in the future. */
export function paymentDate(v: unknown, now: Date): Date {
  if (typeof v !== 'number' || !Number.isFinite(v)) return now;
  const d = new Date(v);
  return d.getTime() > now.getTime() || d.getFullYear() < 2020 ? now : d;
}

async function invoiceRef(db: Firestore, invoiceId: string) {
  const ref = db.collection('invoices').doc(invoiceId);
  const inv = (await ref.get()).data();
  if (!inv) throw new HttpsError('not-found', 'Invoice not found.');
  return { ref, inv };
}

export const recordPayment = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const d = input(request);
  const actor = await requireSuperAdmin(db, request);
  const { ref, inv } = await invoiceRef(db, id(d, 'invoiceId'));
  const method = str(d, 'method', 12);
  if (!METHODS.includes(method)) throw new HttpsError('invalid-argument', 'Unknown method.');
  const amount = int(d, 'amount', 1, 10_000_000);
  const paidOn = paymentDate(d.date, new Date());
  const ts = FieldValue.serverTimestamp();
  // Claim the invoice in a transaction: a second click (or a second admin tab)
  // must not record the payment again and extend paidUntil twice.
  await db.runTransaction(async (tx) => {
    const status = String((await tx.get(ref)).data()?.status ?? '');
    if (!canRecordPayment(status)) {
      throw new HttpsError('failed-precondition', `This invoice is already ${status}.`, { code: 'invoice-closed' });
    }
    tx.update(ref, {
      status: 'paid',
      payment: { amount, method, reference: optStr(d, 'reference', 60), date: paidOn, recordedBy: actor.name },
      updatedAt: ts,
    });
  });

  // A-05: paid until +1 month, clinic Active (unless another invoice is still overdue).
  const clinicRef = db.collection('clinics').doc(inv.clinicId);
  const billingRef = clinicRef.collection('private').doc('billing');
  const b = (await billingRef.get()).data() ?? {};
  const from: Date = b.paidUntil?.toDate?.() && b.paidUntil.toDate() > new Date() ? b.paidUntil.toDate() : new Date();
  const until = new Date(from);
  until.setMonth(until.getMonth() + 1);
  await billingRef.set({ paidUntil: until, ...(b.plan === 'pilot' ? { plan: b.planAfterPilot ?? 'basic' } : {}) }, { merge: true });
  const stillOverdue = await db.collection('invoices').where('clinicId', '==', inv.clinicId).where('status', '==', 'overdue').limit(1).get();
  if (stillOverdue.empty) await clinicRef.update({ status: 'active', updatedAt: ts });
  await logActivity(db, actor, inv.clinicId, 'recorded payment', `${inv.month} · Rs ${amount} · ${method}`);
  return { ok: true };
});

export const waiveInvoice = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const d = input(request);
  const actor = await requireSuperAdmin(db, request);
  const { ref, inv } = await invoiceRef(db, id(d, 'invoiceId'));
  const reason = str(d, 'reason', 80);
  await db.runTransaction(async (tx) => {
    const status = String((await tx.get(ref)).data()?.status ?? '');
    if (!canRecordPayment(status)) {
      throw new HttpsError('failed-precondition', `This invoice is already ${status}.`, { code: 'invoice-closed' });
    }
    tx.update(ref, { status: 'waived', waiveReason: reason, updatedAt: FieldValue.serverTimestamp() });
  });
  await logActivity(db, actor, inv.clinicId, 'waived invoice', `${inv.month} · ${reason}`);
  return { ok: true };
});

export const giveExtension = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const d = input(request);
  const actor = await requireSuperAdmin(db, request);
  const { ref, inv } = await invoiceRef(db, id(d, 'invoiceId'));
  if (typeof d.dueDate !== 'number') throw new HttpsError('invalid-argument', 'dueDate is required.');
  const due = new Date(d.dueDate);
  await ref.update({ status: 'unpaid', dueDate: due, updatedAt: FieldValue.serverTimestamp() });
  const clinicRef = db.collection('clinics').doc(inv.clinicId);
  const c = (await clinicRef.get()).data();
  if (c?.status === 'grace' || c?.status === 'suspended') await clinicRef.update({ status: 'active' });
  await logActivity(db, actor, inv.clinicId, 'gave payment extension', `${inv.month} · due ${due.toISOString().slice(0, 10)}`);
  return { ok: true };
});

export const saveAdminSettings = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const d = input(request);
  const actor = await requireSuperAdmin(db, request);
  const prices = (d.prices ?? {}) as Record<string, unknown>;
  const settings = {
    prices: { pilot: int(prices, 'pilot', 0, 1_000_000), basic: int(prices, 'basic', 0, 1_000_000), premium: int(prices, 'premium', 0, 1_000_000) },
    pilotDays: int(d, 'pilotDays', 0, 365),
    billingDay: int(d, 'billingDay', 1, 28),
    dueDays: int(d, 'dueDays', 0, 60),
    graceDays: int(d, 'graceDays', 0, 60),
    suspendDays: int(d, 'suspendDays', 1, 90),
    paymentInstructions: str(d, 'paymentInstructions', 1000),
  };
  if (settings.suspendDays <= settings.graceDays) throw new HttpsError('invalid-argument', 'Suspension must come after the reminder.');
  await db.collection('settings').doc('billing').set({ ...settings, updatedAt: FieldValue.serverTimestamp() });
  await logActivity(db, actor, null, 'updated admin settings', 'Plans & billing');
  return { ok: true };
});

/**
 * Daily billing job (A-05, A-06). Idempotent: invoice IDs are per clinic and
 * month, and status changes only move forward.
 */
export async function runBillingJobs(db: Firestore, now = new Date()) {
  const s = await billingSettings(db);
  const today = pktNow(now).date;
  const month = today.slice(0, 7);
  const dayOfMonth = Number(today.slice(8, 10));
  const system: Actor = { uid: 'system', role: 'superAdmin', clinicId: null, name: 'System' };
  const log: string[] = [];

  const clinics = await db.collection('clinics').get();
  for (const c of clinics.docs) {
    const clinic = c.data();
    if (clinic.status === 'cancelled') continue;
    const billingRef = c.ref.collection('private').doc('billing');
    const b = (await billingRef.get()).data();
    if (!b) continue;

    // Pilot over → plan after pilot.
    const pilotEnds: Date | null = b.pilotEndsAt?.toDate?.() ?? null;
    let plan = String(b.plan ?? 'pilot');
    if (plan === 'pilot' && pilotEnds && pilotEnds <= now) {
      plan = String(b.planAfterPilot ?? 'basic');
      await billingRef.set({ plan }, { merge: true });
      if (clinic.status === 'pilot') await c.ref.update({ status: 'active' });
      log.push(`${c.id}: pilot ended → ${plan}`);
    }

    // Billing day: one invoice per month (not during pilot).
    if (plan !== 'pilot' && dayOfMonth >= Number(b.billingDay ?? 1)) {
      const invRef = db.collection('invoices').doc(`inv_${c.id}_${month}`);
      if (!(await invRef.get()).exists) {
        await invRef.set({
          clinicId: c.id,
          month,
          amount: Number(b.monthlyFee ?? s.prices[plan as 'basic'] ?? 0),
          dueDate: addDays(now, s.dueDays),
          status: 'unpaid',
          payment: null,
          createdAt: FieldValue.serverTimestamp(),
        });
        log.push(`${c.id}: invoice ${month}`);
      }
    }
  }

  // Overdue → Grace; +graceDays reminder; +suspendDays Suspended.
  const open = await db.collection('invoices').where('status', 'in', ['unpaid', 'overdue']).get();
  for (const inv of open.docs) {
    const v = inv.data();
    const due: Date = v.dueDate?.toDate?.() ?? now;
    if (due > now) continue;
    const late = Math.floor((now.getTime() - due.getTime()) / 86_400_000);
    const clinicRef = db.collection('clinics').doc(v.clinicId);
    const clinic = (await clinicRef.get()).data();
    if (!clinic) continue;
    if (v.status === 'unpaid') await inv.ref.update({ status: 'overdue' });
    if (late >= s.suspendDays && clinic.status !== 'suspended' && clinic.status !== 'cancelled') {
      await clinicRef.update({ status: 'suspended' });
      await logActivity(db, system, v.clinicId, 'suspended clinic', `${clinic.name} · unpaid ${late} days`);
      log.push(`${v.clinicId}: suspended`);
    } else if (clinic.status === 'active' || clinic.status === 'pilot') {
      await clinicRef.update({ status: 'grace' });
      await logActivity(db, system, v.clinicId, 'moved to grace', `${clinic.name} · invoice overdue`);
      log.push(`${v.clinicId}: grace`);
    }
    if (late >= s.graceDays && !v.reminderSentAt) {
      // Reminder email: needs a mail service (Blaze); recorded here for now.
      await inv.ref.update({ reminderSentAt: FieldValue.serverTimestamp() });
      log.push(`${v.clinicId}: reminder due`);
    }
  }
  return log;
}

/** Daily 06:00 PKT (needs Blaze + deploy). */
export const billingJobs = onSchedule({ schedule: '0 6 * * *', timeZone: 'Asia/Karachi', region: REGION }, async () => {
  const log = await runBillingJobs(getFirestore());
  logger.info('billing jobs', { log });
});

/** Run the billing job now (dev / emulator, where schedules do not fire). */
export const adminRunBillingJobs = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  await requireSuperAdmin(db, request);
  return { log: await runBillingJobs(db) };
});
