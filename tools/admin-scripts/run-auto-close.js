#!/usr/bin/env node
/**
 * Closes open tokens from before today once, by hand (PRD D-21; same code as
 * the `autoCloseTokens` scheduled function, which needs Blaze; PRD D-17).
 * Booked → No-show; Arrived / On hold / Called → Completed; `autoClosed: true`.
 *
 *   node run-auto-close.js [--project dev] [--dry-run]
 *
 * Needs `npm run build` in functions/ first. Safe to run again. No prod option.
 */
const { admin, parseArgs, init, functionsLib } = require('./lib/target');

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const where = init(opts.project);
  const db = admin.firestore();

  if (opts['dry-run']) {
    const { decideAutoClose } = functionsLib('queue/autoClose.js');
    const { pktNow } = functionsLib('lib/dates.js');
    const today = pktNow().date;
    const snap = await db.collection('tokens').where('status', 'in', ['booked', 'arrived', 'called', 'onHold']).get();
    let n = 0;
    for (const d of snap.docs) {
      const t = d.data();
      const to = decideAutoClose(t.status, t.date, today);
      if (!to) continue;
      n++;
      console.log(`  would close ${d.id} ${t.tokenPrefix ?? 'A'}-${t.number} (${t.date}) ${t.status} → ${to}`);
    }
    console.log(`[${where}] dry run: ${n} token(s) would be closed (today is ${today}).`);
    process.exit(0);
  }

  const { runAutoClose } = functionsLib('queue/autoClose.js');
  const log = await runAutoClose(db);
  console.log(`[${where}] ${log.length} token(s) closed.`);
  for (const l of log) console.log(`  ${l.tokenId} ${l.label} (${l.date}) ${l.from} → ${l.to}`);
  process.exit(0);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
