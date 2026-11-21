#!/usr/bin/env node
/**
 * One-time migration for doctor search + same-doctor linking (PRD D-31..D-33,
 * DATABASE §8b "Migration"):
 *   - free-text `speciality` → fixed key; unknown → `other` + `specialityFlagged: true`
 *   - backfill `city` (from the clinic), `nameKey`, `hasPmdc`, `doctorGroupId`
 *   - list clinics without a location (no write; the Super Admin fills them in)
 *   - run the suggestion builder once over all doctors
 *
 *   node migrate-doctor-search.js [--project dev] [--dry-run]
 *
 * Needs `npm run build` in functions/ first. Safe to run again. No prod option.
 */
const { admin, parseArgs, init, functionsLib } = require('./lib/target');

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const where = init(opts.project);
  const dry = Boolean(opts['dry-run']);
  const db = admin.firestore();
  const { isSpecialityKey, legacySpeciality, doctorNameKey } = functionsLib('doctors/linking.js');

  const clinics = new Map();
  for (const c of (await db.collection('clinics').get()).docs) clinics.set(c.id, c.data());

  const noLocation = [...clinics.entries()].filter(([, c]) => !c.location);
  console.log(`[${where}] clinics without a location (${noLocation.length}):`);
  for (const [id, c] of noLocation) console.log(`  ${id}  ${c.name} · ${c.area}, ${c.city}`);

  const doctors = (await db.collection('doctors').get()).docs;
  let changed = 0;
  const flagged = [];
  for (const d of doctors) {
    const x = d.data();
    const patch = {};
    if (!isSpecialityKey(x.speciality)) {
      const key = legacySpeciality(x.speciality);
      patch.speciality = key ?? 'other';
      if (!key) {
        patch.specialityFlagged = true;
        flagged.push(`${d.id}  ${x.name} · "${x.speciality}" (${clinics.get(x.clinicId)?.name ?? x.clinicId})`);
      }
    }
    const city = clinics.get(x.clinicId)?.city ?? '';
    if (x.city !== city) patch.city = city;
    const nameKey = doctorNameKey(String(x.name ?? ''));
    if (x.nameKey !== nameKey) patch.nameKey = nameKey;
    if (x.hasPmdc === undefined) patch.hasPmdc = false;
    if (x.doctorGroupId === undefined) patch.doctorGroupId = null;
    if (!Object.keys(patch).length) continue;
    changed++;
    console.log(`  ${dry ? 'would update' : 'update'} ${d.id} ${x.name}: ${JSON.stringify(patch)}`);
    if (!dry) await d.ref.update({ ...patch, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
  }
  console.log(`[${where}] ${changed} doctor(s) ${dry ? 'would be ' : ''}updated.`);
  console.log(`Unknown specialities set to "other" + flagged for the clinic (${flagged.length}):`);
  for (const f of flagged) console.log(`  ${f}`);

  if (dry) {
    console.log('Dry run: suggestions not built.');
    process.exit(0);
  }
  const { buildSuggestions } = functionsLib('doctors/suggest.js');
  let pairs = 0;
  const now = () => admin.firestore.FieldValue.serverTimestamp();
  for (const d of doctors) pairs += await buildSuggestions(db, d.id, now);
  console.log(`[${where}] ${pairs} same-doctor suggestion(s) written.`);
  process.exit(0);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
