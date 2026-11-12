#!/usr/bin/env node
/**
 * Creates a test follow-up from a visit (PRD F-09: staff create them in Phase 2;
 * in Phase 1 this script does it for testing). DATABASE.md §8.
 *
 *   node create-followup.js --token <tokenId> --days 7 [--note "Review visit"] [--project dev]
 *   node create-followup.js --token <tokenId> --date 2026-11-20 --project dev
 */
const { admin, parseArgs, init } = require('./lib/target');

function addDays(date, days) {
  const [y, m, d] = date.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (!opts.token || opts.token === true || (!opts.days && !opts.date)) {
    console.log('Usage: node create-followup.js --token <tokenId> (--days N | --date yyyy-MM-dd) [--note "..."] [--project dev]');
    process.exit(1);
  }
  const where = init(opts.project);
  const db = admin.firestore();

  const token = await db.collection('tokens').doc(opts.token).get();
  if (!token.exists) throw new Error(`Token ${opts.token} not found.`);
  const t = token.data();
  const patient = await db.collection('patients').doc(t.patientId).get();
  const dueDate = opts.date && opts.date !== true ? opts.date : addDays(t.date, Number(opts.days));
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dueDate)) throw new Error('Bad date.');

  const now = admin.firestore.FieldValue.serverTimestamp();
  const ref = await db.collection('followUps').add({
    clinicId: t.clinicId,
    doctorId: t.doctorId,
    patientId: t.patientId,
    ownerUid: patient.data()?.ownerUid ?? null,
    sourceTokenId: token.id,
    dueDate,
    note: opts.note && opts.note !== true ? String(opts.note).slice(0, 80) : 'Review visit',
    status: 'pending',
    bookedTokenId: null,
    remindersSent: 0,
    createdAt: now,
    updatedAt: now,
  });
  console.log(`[${where}] Follow-up ${ref.id}: ${t.patientSnapshot?.name ?? t.patientId} with ${t.doctorId} on ${dueDate}.`);
  process.exit(0);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
