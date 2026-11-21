import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { id, input, logActivity, requireSuperAdmin } from '../lib/access';
import { callableOptions } from '../lib/options';
import { unlinkPlan } from '../doctors/linking';

/**
 * A-09 "Possible same doctor" (PRD D-32, D-33). Super Admin only.
 * Link gives both records one doctorGroupId; Not the same and Unlink are
 * remembered, so that pair is never suggested again.
 */

type Db = FirebaseFirestore.Firestore;

async function label(db: Db, doctorIds: string[]): Promise<string> {
  const parts: string[] = [];
  for (const x of doctorIds) {
    const d = (await db.collection('doctors').doc(x).get()).data();
    const c = d ? (await db.collection('clinics').doc(String(d.clinicId)).get()).data() : undefined;
    parts.push(`${d?.name ?? x} (${c?.name ?? d?.clinicId ?? '?'})`);
  }
  return parts.join(' + ');
}

export const adminLinkDoctors = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const actor = await requireSuperAdmin(db, request);
  const pairId = id(input(request), 'pairId');
  const ref = db.collection('doctorLinkSuggestions').doc(pairId);

  const done = await db.runTransaction(async (tx) => {
    const s = (await tx.get(ref)).data();
    if (!s) throw new HttpsError('not-found', 'Suggestion not found.');
    if (s.status !== 'open') return false; // decided once
    const [aId, bId] = s.doctorIds as string[];
    const aRef = db.collection('doctors').doc(aId), bRef = db.collection('doctors').doc(bId);
    const [a, b] = [(await tx.get(aRef)).data(), (await tx.get(bRef)).data()];
    if (!a || !b) throw new HttpsError('not-found', 'Doctor not found.');
    // Join an existing group if either record already has one.
    const group = (a.doctorGroupId ?? b.doctorGroupId ?? `g_${pairId}`) as string;
    const otherGroup = a.doctorGroupId && b.doctorGroupId && a.doctorGroupId !== b.doctorGroupId ? (b.doctorGroupId as string) : null;
    if (otherGroup) {
      // Both already linked elsewhere: merge b's group into a's.
      const members = await tx.get(db.collection('doctors').where('doctorGroupId', '==', otherGroup));
      for (const m of members.docs) tx.update(m.ref, { doctorGroupId: group, updatedAt: FieldValue.serverTimestamp() });
    }
    tx.update(aRef, { doctorGroupId: group, updatedAt: FieldValue.serverTimestamp() });
    tx.update(bRef, { doctorGroupId: group, updatedAt: FieldValue.serverTimestamp() });
    tx.update(ref, { status: 'linked', decidedAt: FieldValue.serverTimestamp(), decidedBy: { uid: actor.uid, name: actor.name } });
    return true;
  });
  if (done) {
    const s = (await ref.get()).data();
    await logActivity(db, actor, null, 'linked doctors', await label(db, s?.doctorIds ?? []));
  }
  return { ok: true };
});

export const adminMarkNotSame = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const actor = await requireSuperAdmin(db, request);
  const pairId = id(input(request), 'pairId');
  const ref = db.collection('doctorLinkSuggestions').doc(pairId);
  const done = await db.runTransaction(async (tx) => {
    const s = (await tx.get(ref)).data();
    if (!s) throw new HttpsError('not-found', 'Suggestion not found.');
    if (s.status !== 'open') return false;
    tx.update(ref, { status: 'notSame', decidedAt: FieldValue.serverTimestamp(), decidedBy: { uid: actor.uid, name: actor.name } });
    return true;
  });
  if (done) {
    const s = (await ref.get()).data();
    await logActivity(db, actor, null, 'marked doctors not the same', await label(db, s?.doctorIds ?? []));
  }
  return { ok: true };
});

export const adminUnlinkDoctor = onCall(callableOptions, async (request) => {
  const db = getFirestore();
  const actor = await requireSuperAdmin(db, request);
  const doctorId = id(input(request), 'doctorId');
  const docRef = db.collection('doctors').doc(doctorId);

  const done = await db.runTransaction(async (tx) => {
    const d = (await tx.get(docRef)).data();
    if (!d) throw new HttpsError('not-found', 'Doctor not found.');
    const group = d.doctorGroupId as string | null | undefined;
    if (!group) return false;
    const members = await tx.get(db.collection('doctors').where('doctorGroupId', '==', group));
    const pairs = await tx.get(db.collection('doctorLinkSuggestions').where('doctorIds', 'array-contains', doctorId));
    for (const x of unlinkPlan(doctorId, members.docs.map((m) => m.id))) {
      tx.update(db.collection('doctors').doc(x), { doctorGroupId: null, updatedAt: FieldValue.serverTimestamp() });
    }
    // D-33: Unlink counts as Not the same: never suggested again.
    for (const p of pairs.docs) {
      if (p.data().status === 'linked') {
        tx.update(p.ref, { status: 'unlinked', decidedAt: FieldValue.serverTimestamp(), decidedBy: { uid: actor.uid, name: actor.name } });
      }
    }
    return true;
  });
  if (done) await logActivity(db, actor, null, 'unlinked doctor', await label(db, [doctorId]));
  return { ok: true };
});
