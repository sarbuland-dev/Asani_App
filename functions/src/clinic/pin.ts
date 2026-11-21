import { FieldValue, Firestore, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { id, input, logActivity, optStr, requireClinic, requireSuperAdmin, str } from '../lib/access';
import { callableOptions } from '../lib/options';
import { PIN, UNLOCK_MS, afterTry, hashPin, isLocked, pinMatches } from './pinRules';

/**
 * Manager PIN (PRD D-41, Q-W11). Protects Billing, Export, Add / Deactivate
 * doctor and Change password; never queue work, leave or timings.
 * clinicPins/{clinicId}: {salt, hash, failed, lockedUntil, unlockedUntil} — no
 * rules match, so only functions read or write it. `clinicAccounts.pinSet`
 * tells the web whether a PIN exists.
 */

const pinRef = (db: Firestore, clinicId: string) => db.collection('clinicPins').doc(clinicId);

async function setPinFlag(db: Firestore, clinicId: string, pinSet: boolean) {
  const logins = await db.collection('clinicAccounts').where('clinicId', '==', clinicId).get();
  await Promise.all(logins.docs.map((d) => d.ref.set({ pinSet }, { merge: true })));
}

/**
 * Checks a PIN and records the try (5 wrong → locked 15 min). On success the
 * protected actions are unlocked for 15 minutes. Throws on wrong / locked.
 */
async function checkPin(db: Firestore, clinicId: string, pin: string): Promise<number> {
  const ref = pinRef(db, clinicId);
  const now = Date.now();
  const result = await db.runTransaction(async (tx) => {
    const p = (await tx.get(ref)).data();
    if (!p) return { ok: true as const, unlockedUntil: 0 };
    const state = { failed: Number(p.failed ?? 0), lockedUntil: (p.lockedUntil as number | null) ?? null };
    if (isLocked(state, now)) return { ok: false as const, locked: state.lockedUntil };
    const correct = PIN.test(pin) && pinMatches(pin, String(p.salt), String(p.hash));
    const next = afterTry(state, correct, now);
    const unlockedUntil = correct ? now + UNLOCK_MS : (p.unlockedUntil ?? 0);
    tx.update(ref, { failed: next.failed, lockedUntil: next.lockedUntil, unlockedUntil });
    if (correct) return { ok: true as const, unlockedUntil };
    return isLocked(next, now) ? { ok: false as const, locked: next.lockedUntil } : { ok: false as const, triesLeft: 5 - next.failed };
  });
  if (result.ok) return result.unlockedUntil;
  if ('locked' in result) {
    throw new HttpsError('resource-exhausted', 'Too many wrong PINs. Try again in 15 minutes.', { code: 'pin-locked', lockedUntil: result.locked });
  }
  throw new HttpsError('permission-denied', `Wrong PIN. ${result.triesLeft} tries left.`, { code: 'pin-wrong', triesLeft: result.triesLeft });
}

/**
 * Server gate for protected actions (Add / Deactivate doctor). Passes when no
 * PIN is set yet, or within 15 minutes of a correct PIN.
 */
export async function requirePinUnlocked(db: Firestore, clinicId: string): Promise<void> {
  const p = (await pinRef(db, clinicId).get()).data();
  if (!p) return;
  if (Number(p.unlockedUntil ?? 0) > Date.now()) return;
  throw new HttpsError('failed-precondition', 'Enter the manager PIN first.', { code: 'pin-required' });
}

/** Set or change the PIN. Changing needs the current PIN. */
export const clinicSetPin = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const d = input(request);
  const actor = await requireClinic(db, request);
  const pin = str(d, 'pin', 4);
  if (!PIN.test(pin)) throw new HttpsError('invalid-argument', 'The PIN must be 4 digits.');
  const ref = pinRef(db, actor.clinicId);
  const exists = (await ref.get()).exists;
  if (exists) await checkPin(db, actor.clinicId, optStr(d, 'currentPin', 4) ?? '');
  const { salt, hash } = hashPin(pin);
  await ref.set({ salt, hash, failed: 0, lockedUntil: null, unlockedUntil: Date.now() + UNLOCK_MS, updatedAt: FieldValue.serverTimestamp() });
  await setPinFlag(db, actor.clinicId, true);
  await logActivity(db, actor, actor.clinicId, exists ? 'changed manager PIN' : 'set manager PIN', actor.name);
  return { ok: true };
});

/** Unlock the protected pages for 15 minutes. */
export const clinicVerifyPin = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const actor = await requireClinic(db, request);
  const unlockedUntil = await checkPin(db, actor.clinicId, str(input(request), 'pin', 4));
  return { ok: true, unlockedUntil };
});

/** Super Admin: forgotten PIN. The clinic sets a new one. */
export const adminResetClinicPin = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const actor = await requireSuperAdmin(db, request);
  const clinicId = id(input(request), 'clinicId');
  await pinRef(db, clinicId).delete();
  await setPinFlag(db, clinicId, false);
  const clinic = (await db.collection('clinics').doc(clinicId).get()).data();
  await logActivity(db, actor, clinicId, 'reset manager PIN', String(clinic?.name ?? clinicId));
  return { ok: true };
});
