import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';

/**
 * Manager PIN (PRD D-41, Q-W11). Pure helpers, no Firestore.
 * The PIN is stored only as a salted scrypt hash in clinicPins/{clinicId}
 * (no rules match: clients can never read it) and checked on the server.
 */

export const PIN = /^\d{4}$/;
export const MAX_TRIES = 5;
export const LOCK_MS = 15 * 60 * 1000;
/** A correct PIN unlocks the protected pages/actions for 15 minutes. */
export const UNLOCK_MS = 15 * 60 * 1000;

export function hashPin(pin: string, salt = randomBytes(16).toString('hex')): { salt: string; hash: string } {
  return { salt, hash: scryptSync(pin, salt, 32).toString('hex') };
}

export function pinMatches(pin: string, salt: string, hash: string): boolean {
  const got = scryptSync(pin, salt, 32);
  const want = Buffer.from(hash, 'hex');
  return got.length === want.length && timingSafeEqual(got, want);
}

export interface PinState {
  failed: number;
  lockedUntil: number | null; // ms
}

/** After a check: 5 wrong tries in a row lock the PIN for 15 minutes; a right one resets. */
export function afterTry(state: PinState, correct: boolean, now: number): PinState {
  if (correct) return { failed: 0, lockedUntil: null };
  const failed = state.failed + 1;
  return failed >= MAX_TRIES ? { failed: 0, lockedUntil: now + LOCK_MS } : { failed, lockedUntil: state.lockedUntil };
}

export function isLocked(state: PinState, now: number): boolean {
  return state.lockedUntil !== null && state.lockedUntil > now;
}
