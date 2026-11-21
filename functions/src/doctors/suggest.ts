import { FieldValue, Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';

import { LinkStatus, Strength, pairIdOf, suggestionChange } from './linking';

/** doctors/{id}/private/admin: the PMDC number, Super Admin read only (D-33). */
export const pmdcRef = (db: Firestore, doctorId: string) => db.collection('doctors').doc(doctorId).collection('private').doc('admin');

/**
 * Suggestion builder (D-32, D-33): after a doctor is saved, find possible
 * matches at OTHER clinics in the SAME city and create / upgrade
 * doctorLinkSuggestions. Never links and never throws (a save must not fail
 * because of this). Returns how many pairs were written.
 */
export async function buildSuggestions(
  db: Firestore,
  doctorId: string,
  // Admin scripts pass their own (a second firebase-admin copy can't serialise this one's sentinel).
  serverTime: () => unknown = () => FieldValue.serverTimestamp(),
): Promise<number> {
  try {
    const doctor = (await db.collection('doctors').doc(doctorId).get()).data();
    if (!doctor || doctor.active === false || !doctor.city) return 0;
    const pmdc = (await pmdcRef(db, doctorId).get()).data()?.pmdcNumber as string | undefined;

    const candidates = new Map<string, Strength>(); // other doctorId → strength
    if (pmdc) {
      // Collection group "private" also holds clinics/{id}/private/billing, which has no pmdcNumber.
      const same = await db.collectionGroup('private').where('pmdcNumber', '==', pmdc).get();
      for (const d of same.docs) {
        const otherId = d.ref.parent.parent?.id;
        if (otherId && otherId !== doctorId && d.ref.parent.parent?.parent.id === 'doctors') candidates.set(otherId, 'strong');
      }
    }
    if (doctor.nameKey) {
      const same = await db.collection('doctors').where('nameKey', '==', doctor.nameKey).where('speciality', '==', doctor.speciality).get();
      for (const d of same.docs) {
        if (d.id !== doctorId && !candidates.has(d.id)) candidates.set(d.id, 'weak');
      }
    }

    let written = 0;
    for (const [otherId, strength] of candidates) {
      const other = (await db.collection('doctors').doc(otherId).get()).data();
      if (!other || other.clinicId === doctor.clinicId || other.city !== doctor.city) continue;
      const pairId = pairIdOf(doctorId, otherId);
      const ref = db.collection('doctorLinkSuggestions').doc(pairId);
      const cur = (await ref.get()).data() as { status: LinkStatus; strength: Strength } | undefined;
      const change = suggestionChange(cur ?? null, strength === 'strong');
      if (!change) continue;
      const ids = [doctorId, otherId].sort();
      const clinicOf = (x: string) => (x === doctorId ? doctor.clinicId : other.clinicId) as string;
      if (change === 'create') {
        await ref.set({
          doctorIds: ids,
          clinicIds: ids.map(clinicOf),
          strength,
          status: 'open',
          createdAt: serverTime(),
          decidedAt: null,
          decidedBy: null,
        });
      } else {
        await ref.update({ strength: 'strong' });
      }
      written++;
    }
    return written;
  } catch (e) {
    logger.error('buildSuggestions failed', { doctorId, error: String(e) });
    return 0;
  }
}
