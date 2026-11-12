#!/usr/bin/env node
/**
 * queue-sim: acts as the clinic receptionist until the desktop app exists.
 * Implements the desktop contract in ARCHITECTURE.md §10 and nothing more.
 *
 *   node queue-sim.js status --doctor d_ayesha [--date 2026-11-12] [--project dev]
 *   node queue-sim.js start  --doctor d_ayesha        session → running
 *   node queue-sim.js next   --doctor d_ayesha        called → completed, next waiting → called
 *   node queue-sim.js arrive --doctor d_ayesha --number 3
 *   node queue-sim.js skip   --doctor d_ayesha --number 3
 *   node queue-sim.js hold   --doctor d_ayesha --number 3
 *   node queue-sim.js pause  --doctor d_ayesha
 *   node queue-sim.js end    --doctor d_ayesha        session → ended, remaining booked → noShow
 *   node queue-sim.js auto   --doctor d_ayesha --every 30   start, then "next" every 30 s
 *
 * Target: Firestore emulator by default; `--project dev` = asani-b2b17 with
 * serviceAccount.dev.json. There is deliberately NO prod option (AGENTS.md §7).
 *
 * Until Firestore triggers run (Blaze, D-17) this also keeps `day.activeNumbers`
 * and `waitingCount` correct, exactly as the `onTokenWrite` trigger will, and
 * sends the queue notifications with the same code (functions/lib/queue/notify.js,
 * run `npm run build` in functions/ first).
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const DEV_PROJECT_ID = 'asani-b2b17';
const WAITING = ['booked', 'arrived', 'onHold']; // counted as "ahead" (DATABASE.md §7)

/** Shared with the Cloud Functions so both send exactly the same steps. */
function loadNotify() {
  const lib = path.join(__dirname, '../../functions/lib/queue/notify.js');
  if (!fs.existsSync(lib)) {
    console.warn('(notifications skipped: run "npm run build" in functions/ first)');
    return null;
  }
  return require(lib);
}

// ---------------------------------------------------------------- args

function parseArgs(argv) {
  const [command, ...rest] = argv;
  const opts = {};
  for (let i = 0; i < rest.length; i++) {
    if (rest[i].startsWith('--')) opts[rest[i].slice(2)] = rest[i + 1] && !rest[i + 1].startsWith('--') ? rest[++i] : true;
  }
  return { command, opts };
}

function todayPkt() {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Karachi', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
}

function init(project) {
  if (!project || project === 'emulator') {
    process.env.FIRESTORE_EMULATOR_HOST ||= '127.0.0.1:8080';
    admin.initializeApp({ projectId: DEV_PROJECT_ID });
    return `emulator (${process.env.FIRESTORE_EMULATOR_HOST})`;
  }
  if (project !== 'dev') {
    console.error(`Unknown --project "${project}". Use no flag (emulator) or --project dev. There is no prod option.`);
    process.exit(1);
  }
  const candidates = [path.join(__dirname, 'serviceAccount.dev.json'), path.join(__dirname, '../admin-scripts/serviceAccount.dev.json')];
  const keyPath = candidates.find((p) => fs.existsSync(p));
  if (!keyPath) {
    console.error('Missing serviceAccount.dev.json (tools/queue-sim/ or tools/admin-scripts/). Never commit it.');
    process.exit(1);
  }
  const key = JSON.parse(fs.readFileSync(keyPath, 'utf8'));
  if (key.project_id !== DEV_PROJECT_ID) {
    console.error(`Key is for "${key.project_id}", expected "${DEV_PROJECT_ID}". Stopping.`);
    process.exit(1);
  }
  admin.initializeApp({ credential: admin.credential.cert(key), projectId: DEV_PROJECT_ID });
  return `dev project ${DEV_PROJECT_ID}`;
}

// ---------------------------------------------------------------- data

const db = () => admin.firestore();
const ts = () => admin.firestore.FieldValue.serverTimestamp();

function dayRef(doctorId, date) {
  return db().collection('doctors').doc(doctorId).collection('days').doc(date);
}

function tokensQuery(doctorId, date) {
  return db().collection('tokens').where('doctorId', '==', doctorId).where('date', '==', date);
}

/** activeNumbers = waiting tokens, sorted (what onTokenWrite maintains). */
function activeNumbersFrom(tokens) {
  return tokens.filter((t) => WAITING.includes(t.status)).map((t) => t.number).sort((a, b) => a - b);
}

/**
 * Runs `change(tokens, day)` in a transaction. `change` returns
 * { tokenUpdates: [[id, data]], dayUpdate: {...}, message }.
 */
async function apply(doctorId, date, change) {
  return db().runTransaction(async (tx) => {
    const daySnap = await tx.get(dayRef(doctorId, date));
    const snap = await tx.get(tokensQuery(doctorId, date));
    const tokens = snap.docs.map((d) => ({ id: d.id, ...d.data() })).sort((a, b) => a.number - b.number);
    const day = daySnap.exists ? daySnap.data() : null;
    const result = change(tokens, day);
    if (result.error) return result;

    const next = tokens.map((t) => {
      const u = (result.tokenUpdates || []).find(([id]) => id === t.id);
      return u ? { ...t, ...u[1] } : t;
    });
    for (const [id, data] of result.tokenUpdates || []) {
      tx.update(db().collection('tokens').doc(id), { ...data, updatedAt: ts() });
    }
    const activeNumbers = activeNumbersFrom(next);
    tx.set(
      dayRef(doctorId, date),
      {
        doctorId,
        date,
        ...(day ? {} : { clinicId: tokens[0]?.clinicId ?? '', currentToken: 0, lastTokenNumber: 0, bookedCount: 0, sessionStatus: 'notStarted' }),
        ...(result.dayUpdate || {}),
        activeNumbers,
        waitingCount: activeNumbers.length,
        updatedAt: ts(),
      },
      { merge: true },
    );
    return result;
  });
}

// ---------------------------------------------------------------- commands

const label = (t) => `${t.tokenPrefix || 'A'}-${t.number}`;
const byNumber = (tokens, n) => tokens.find((t) => t.number === Number(n));

const commands = {
  async status(doctorId, date) {
    const daySnap = await dayRef(doctorId, date).get();
    const snap = await tokensQuery(doctorId, date).get();
    const tokens = snap.docs.map((d) => d.data()).sort((a, b) => a.number - b.number);
    const day = daySnap.data() || {};
    console.log(`${doctorId} · ${date} · session ${day.sessionStatus || 'notStarted'} · now serving ${day.currentToken || '-'} · waiting ${JSON.stringify(day.activeNumbers || [])}`);
    if (tokens.length === 0) console.log('  (no tokens)');
    for (const t of tokens) console.log(`  ${label(t).padEnd(6)} ${t.status.padEnd(9)} ${t.patientSnapshot?.name ?? ''}`);
    return { message: '' };
  },

  start: (doctorId, date) =>
    apply(doctorId, date, () => ({ dayUpdate: { sessionStatus: 'running' }, message: 'Session started.' })),

  pause: (doctorId, date) =>
    apply(doctorId, date, () => ({ dayUpdate: { sessionStatus: 'paused' }, message: 'Session paused.' })),

  /** Previous called → completed; next waiting (booked/arrived/onHold) → called. */
  next: (doctorId, date) =>
    apply(doctorId, date, (tokens, day) => {
      const updates = [];
      const called = tokens.find((t) => t.status === 'called');
      if (called) updates.push([called.id, { status: 'completed', completedAt: ts() }]);
      const nextToken = tokens.find((t) => WAITING.includes(t.status) && t.status !== 'onHold') ||
        tokens.find((t) => t.status === 'onHold');
      if (!nextToken) {
        return { tokenUpdates: updates, message: called ? `${label(called)} completed. Nobody is waiting.` : 'Nobody is waiting.' };
      }
      const since = (nextToken.arrivedAt || nextToken.createdAt)?.toDate?.();
      updates.push([
        nextToken.id,
        { status: 'called', calledAt: ts(), waitMinutes: since ? Math.max(0, Math.round((Date.now() - since.getTime()) / 60000)) : null },
      ]);
      return {
        tokenUpdates: updates,
        dayUpdate: { currentToken: nextToken.number, ...(day?.sessionStatus === 'running' ? {} : { sessionStatus: 'running' }) },
        message: `Now serving ${label(nextToken)} (${nextToken.patientSnapshot?.name ?? ''}).`,
      };
    }),

  arrive: (doctorId, date, opts) =>
    apply(doctorId, date, (tokens) => {
      const t = byNumber(tokens, opts.number);
      if (!t || t.status !== 'booked') return { error: `Token ${opts.number} is not booked.` };
      return { tokenUpdates: [[t.id, { status: 'arrived', arrivedAt: ts() }]], message: `${label(t)} arrived.` };
    }),

  skip: (doctorId, date, opts) =>
    apply(doctorId, date, (tokens) => {
      const t = byNumber(tokens, opts.number);
      if (!t || !['booked', 'arrived'].includes(t.status)) return { error: `Token ${opts.number} cannot be skipped.` };
      return { tokenUpdates: [[t.id, { status: 'skipped' }]], message: `${label(t)} skipped.` };
    }),

  hold: (doctorId, date, opts) =>
    apply(doctorId, date, (tokens) => {
      const t = byNumber(tokens, opts.number);
      if (!t || t.status !== 'arrived') return { error: `Token ${opts.number} must be arrived to hold.` };
      return { tokenUpdates: [[t.id, { status: 'onHold' }]], message: `${label(t)} on hold.` };
    }),

  /** Session end: the called patient is completed, remaining booked → noShow (DATABASE.md §7). */
  end: (doctorId, date) =>
    apply(doctorId, date, (tokens) => {
      const updates = [];
      for (const t of tokens) {
        if (t.status === 'called') updates.push([t.id, { status: 'completed', completedAt: ts() }]);
        if (t.status === 'booked') updates.push([t.id, { status: 'noShow' }]);
      }
      return { tokenUpdates: updates, dayUpdate: { sessionStatus: 'ended' }, message: `Session ended (${updates.length} tokens closed).` };
    }),

  async auto(doctorId, date, opts) {
    const every = Math.max(5, Number(opts.every) || 30);
    console.log(`Auto mode: "next" every ${every}s. Ctrl+C to stop.`);
    await commands.start(doctorId, date);
    for (;;) {
      const r = await commands.next(doctorId, date);
      console.log(new Date().toLocaleTimeString(), r.message);
      await notify(doctorId, date);
      await new Promise((res) => setTimeout(res, every * 1000));
    }
  },
};

async function notify(doctorId, date) {
  const mod = loadNotify();
  if (!mod) return;
  const sent = await mod.evaluateQueue(admin.firestore(), admin.messaging(), doctorId, date);
  for (const s of sent) {
    const why = s.skipped === 'alerts-off' ? ' (owner turned alerts off)' : s.skipped === 'no-devices' ? ' (no registered phone)' : '';
    console.log(`  alert ${s.step} → token ${s.tokenId}: ${s.devices} device(s)${why}`);
  }
}

async function main() {
  const { command, opts } = parseArgs(process.argv.slice(2));
  if (!commands[command] || !opts.doctor || opts.doctor === true) {
    console.log('Usage: node queue-sim.js <status|start|next|arrive|skip|hold|pause|end|auto> --doctor <doctorId> [--number N] [--date yyyy-MM-dd] [--every 30] [--project dev]');
    process.exit(command ? 1 : 0);
  }
  const where = init(opts.project);
  const date = opts.date && opts.date !== true ? opts.date : todayPkt();
  if (command !== 'status') console.log(`[${where}] ${opts.doctor} · ${date}`);
  const result = await commands[command](opts.doctor, date, opts);
  if (result?.error) {
    console.error(result.error);
    process.exit(1);
  }
  if (result?.message) console.log(result.message);
  if (command !== 'status') await notify(opts.doctor, date);
  process.exit(0);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
