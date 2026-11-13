import { FieldValue, Firestore, Transaction } from 'firebase-admin/firestore';
import { CallableRequest, HttpsError } from 'firebase-functions/v2/https';

/**
 * PRD-CLINIC-WEB §4 (D-18): roles are Firebase Auth custom claims, set only
 * by Cloud Functions / admin scripts. Never read a role from Firestore.
 *   clinic login: { role: 'clinic', clinicId }
 *   super admin:  { role: 'superAdmin' }
 */
export interface Actor {
  uid: string;
  role: 'clinic' | 'superAdmin';
  clinicId: string | null;
  /** As shown in logs: "Al-Shifa Clinic" or "Sarbuland". */
  name: string;
}

export function claimsOf(request: CallableRequest): { uid: string; role?: string; clinicId?: string } {
  const auth = request.auth;
  if (!auth) throw new HttpsError('unauthenticated', 'Please log in again.');
  return { uid: auth.uid, role: auth.token.role as string | undefined, clinicId: auth.token.clinicId as string | undefined };
}

/** The clinic login of `clinicId` (its own clinic only). */
export async function requireClinic(db: Firestore, request: CallableRequest, clinicId?: string): Promise<Actor & { clinicId: string }> {
  const c = claimsOf(request);
  if (c.role !== 'clinic' || !c.clinicId) throw new HttpsError('permission-denied', "This account doesn't have clinic access.");
  if (clinicId !== undefined && clinicId !== c.clinicId) throw new HttpsError('permission-denied', 'This is not your clinic.');
  const clinic = await db.collection('clinics').doc(c.clinicId).get();
  return { uid: c.uid, role: 'clinic', clinicId: c.clinicId, name: String(clinic.data()?.name ?? 'Clinic') };
}

export async function requireSuperAdmin(db: Firestore, request: CallableRequest): Promise<Actor> {
  const c = claimsOf(request);
  if (c.role !== 'superAdmin') throw new HttpsError('permission-denied', 'Super admin only.');
  const user = await db.collection('adminUsers').doc(c.uid).get();
  return { uid: c.uid, role: 'superAdmin', clinicId: null, name: String(user.data()?.name ?? request.auth?.token.name ?? 'Super Admin') };
}

/** "Al-Shifa Clinic (clinic login)" / "Sarbuland (Super Admin)" for token history. */
export function actorLabel(a: Actor): string {
  return `${a.name} (${a.role === 'clinic' ? 'clinic login' : 'Super Admin'})`;
}

/** A-07 / BW-10: every change writes one activity log row (backend only). */
export function logActivity(
  db: Firestore,
  actor: Actor,
  clinicId: string | null,
  action: string,
  target: string,
  tx?: Transaction,
): void | Promise<unknown> {
  const ref = db.collection('activityLogs').doc();
  const data = {
    clinicId,
    actor: { uid: actor.uid, name: actor.name, role: actor.role },
    action,
    target,
    at: FieldValue.serverTimestamp(),
  };
  if (tx) {
    tx.set(ref, data);
    return;
  }
  return ref.set(data);
}

/** Small input readers for callables (all inputs are validated). */
export function str(d: Record<string, unknown>, k: string, max = 128): string {
  const v = d[k];
  if (typeof v !== 'string' || v.trim().length === 0 || v.length > max) throw new HttpsError('invalid-argument', `${k} is required.`);
  return v.trim();
}

export function optStr(d: Record<string, unknown>, k: string, max = 200): string | null {
  const v = d[k];
  if (v === undefined || v === null || v === '') return null;
  if (typeof v !== 'string' || v.length > max) throw new HttpsError('invalid-argument', `${k} is invalid.`);
  return v.trim();
}

export function int(d: Record<string, unknown>, k: string, min: number, max: number): number {
  const v = d[k];
  if (typeof v !== 'number' || !Number.isInteger(v) || v < min || v > max) throw new HttpsError('invalid-argument', `${k} must be ${min}–${max}.`);
  return v;
}

export function id(d: Record<string, unknown>, k: string): string {
  const v = str(d, k);
  if (v.includes('/')) throw new HttpsError('invalid-argument', `${k} is invalid.`);
  return v;
}

export function input(request: CallableRequest): Record<string, unknown> {
  return (request.data ?? {}) as Record<string, unknown>;
}

/** yyyy-MM of a yyyy-MM-dd date. */
export const monthOf = (date: string) => date.slice(0, 7);
