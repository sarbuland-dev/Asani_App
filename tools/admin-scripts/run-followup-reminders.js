#!/usr/bin/env node
/**
 * Runs the daily follow-up reminders once, by hand (same code as the
 * `followUpReminders` scheduled function, which needs Blaze; PRD D-17).
 *
 *   node run-followup-reminders.js [--project dev]
 *
 * Needs `npm run build` in functions/ first. Safe to run again: each reminder
 * is recorded before it is sent.
 */
const { admin, parseArgs, init, functionsLib } = require('./lib/target');

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const where = init(opts.project);
  const { runFollowUpReminders } = functionsLib('followups/reminders.js');
  const log = await runFollowUpReminders(admin.firestore(), admin.messaging());
  console.log(`[${where}] ${log.length} follow-up(s) handled.`);
  for (const l of log) console.log(`  ${l.followUpId}: ${l.action}${l.action === 'missed' ? '' : ` → ${l.devices} device(s)`}`);
  process.exit(0);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
