#!/usr/bin/env node
/**
 * One-time: fills `patients.clinicIds` from existing tokens, so clinics can
 * find patients who booked before the clinic web existed (PRD-CLINIC-WEB §11,
 * BW-6). New bookings and walk-ins set it themselves.
 *
 *   node backfill-clinic-ids.js [--project dev]
 *
 * Safe to run again (arrayUnion). No prod option.
 */
const { admin, parseArgs, init } = require('./lib/target');

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const where = init(opts.project);
  const db = admin.firestore();
  const byPatient = new Map();
  const tokens = await db.collection('tokens').select('patientId', 'clinicId').get();
  for (const t of tokens.docs) {
    const { patientId, clinicId } = t.data();
    if (!patientId || !clinicId) continue;
    if (!byPatient.has(patientId)) byPatient.set(patientId, new Set());
    byPatient.get(patientId).add(clinicId);
  }
  let n = 0;
  for (const [patientId, clinics] of byPatient) {
    const ref = db.collection('patients').doc(patientId);
    if (!(await ref.get()).exists) continue;
    await ref.update({ clinicIds: admin.firestore.FieldValue.arrayUnion(...clinics) });
    n++;
  }
  console.log(`${where}: clinicIds set on ${n} patients from ${tokens.size} tokens.`);
}

main().then(() => process.exit(0), (e) => {
  console.error(e.message ?? e);
  process.exit(1);
});
