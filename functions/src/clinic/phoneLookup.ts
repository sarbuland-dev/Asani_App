import { Firestore, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { input, requireClinic, str } from '../lib/access';
import { callableOptions } from '../lib/options';

/**
 * PRD D-22: a clinic types a patient's FULL phone number at walk-in and sees
 * that number's family profiles from ANY clinic, so an Asani app user is linked
 * to their account instead of getting a duplicate profile.
 *
 * Privacy: only name, relation, age and gender are returned. Never the phone
 * owner's account, other clinics, visits or history. Rate limited per clinic.
 */

const PHONE = /^\+923\d{9}$/;
export const LOOKUP_LIMIT = 30; // lookups …
export const LOOKUP_WINDOW_MS = 10 * 60 * 1000; // … per 10 minutes per clinic

export interface RateWindow {
  windowStart: number; // ms
  count: number;
}

/** Pure: next window state, or null if the clinic is over the limit. */
export function nextRateWindow(cur: RateWindow | null, now: number, limit = LOOKUP_LIMIT, windowMs = LOOKUP_WINDOW_MS): RateWindow | null {
  if (!cur || now - cur.windowStart >= windowMs) return { windowStart: now, count: 1 };
  if (cur.count >= limit) return null;
  return { windowStart: cur.windowStart, count: cur.count + 1 };
}

/** Age from birth year in Pakistan's current year (null if unknown). */
export function ageOf(birthYear: unknown, year: number): number | null {
  return typeof birthYear === 'number' ? Math.max(0, year - birthYear) : null;
}

async function takeLookup(db: Firestore, clinicId: string): Promise<void> {
  // rateLimits/* has no rules match → clients can neither read nor write it.
  const ref = db.collection('rateLimits').doc(`phoneLookup_${clinicId}`);
  const ok = await db.runTransaction(async (tx) => {
    const d = (await tx.get(ref)).data();
    const cur = d ? { windowStart: Number(d.windowStart), count: Number(d.count) } : null;
    const next = nextRateWindow(cur, Date.now());
    if (!next) return false;
    tx.set(ref, { ...next, clinicId, updatedAt: new Date() });
    return true;
  });
  if (!ok) {
    throw new HttpsError('resource-exhausted', 'Too many phone lookups. Please try again in a few minutes.', { code: 'rate-limited' });
  }
}

export const clinicLookupPhone = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const actor = await requireClinic(db, request);
  const phone = str(input(request), 'phone', 20);
  if (!PHONE.test(phone)) throw new HttpsError('invalid-argument', 'Enter the full mobile number.');
  await takeLookup(db, actor.clinicId);

  const snap = await db.collection('patients').where('phone', '==', phone).where('status', '==', 'active').limit(20).get();
  const year = new Date().getFullYear();
  const profiles = snap.docs.map((d) => {
    const p = d.data();
    return {
      id: d.id,
      name: String(p.name ?? ''),
      relation: String(p.relation ?? 'other'),
      gender: String(p.gender ?? 'other'),
      age: ageOf(p.birthYear, year),
      // Lets the web show "visited here" vs "new to this clinic" without reading other clinics.
      atThisClinic: (Array.isArray(p.clinicIds) ? p.clinicIds : []).includes(actor.clinicId),
    };
  });
  return { profiles };
});
