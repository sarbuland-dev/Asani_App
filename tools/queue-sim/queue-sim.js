#!/usr/bin/env node
/**
 * queue-sim (D-52): acts as a clinic's receptionist on the Supabase dev database (asani-dev).
 * Every command calls the SAME Postgres functions as the clinic web (queue_action, clinic_create_walk_in), signed in
 * as that doctor's clinic (app_metadata role clinic), so all rules, history lines and patient notifications are real.
 *
 *   node queue-sim.js status  --doctor d_ayesha [--date 2026-11-26]
 *   node queue-sim.js start   --doctor d_ayesha
 *   node queue-sim.js next    --doctor d_ayesha [--anyway]     D-24: --anyway calls a Booked (not arrived) patient
 *   node queue-sim.js undo    --doctor d_ayesha                within 30 s of Next
 *   node queue-sim.js arrive  --doctor d_ayesha --number 3      also: skip, hold, back, cancel, noshow, callnow
 *   node queue-sim.js walkin  --doctor d_ayesha --name "Ali Raza" --phone 03001234567 [--age 40] [--gender male]
 *   node queue-sim.js pause | end  --doctor d_ayesha
 *   node queue-sim.js auto    --doctor d_ayesha --every 30      start, then Next (anyway) every 30 s
 *
 * Database URL: env SUPABASE_DB_URL or supabase/.db-url.local (git-ignored). There is no prod option (AGENTS.md §7):
 * it refuses any project other than asani-dev. The old Firestore version is queue-sim-firebase.js.
 */
const fs = require('node:fs');
const path = require('node:path');
const { Client } = require('pg');

const DEV_REF = 'lgnbxxcmogbbzmuqyrgu'; // asani-dev
const TOKEN_ACTIONS = { arrive: 'arrive', skip: 'skip', hold: 'hold', back: 'backToQueue', cancel: 'cancel', noshow: 'noShow', callnow: 'callNow' };

function parseArgs(argv) {
  const [command, ...rest] = argv;
  const opts = {};
  for (let i = 0; i < rest.length; i++) {
    if (rest[i].startsWith('--')) opts[rest[i].slice(2)] = rest[i + 1] && !rest[i + 1].startsWith('--') ? rest[++i] : true;
  }
  return { command, opts };
}

const todayPkt = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Karachi' }).format(new Date());

function dbUrl() {
  const root = path.resolve(__dirname, '..', '..');
  const url = (process.env.SUPABASE_DB_URL ?? fs.readFileSync(path.join(root, 'supabase', '.db-url.local'), 'utf8')).trim();
  if (!url.includes(DEV_REF)) {
    console.error('This database is not asani-dev. queue-sim only runs on the dev project (AGENTS.md §7).');
    process.exit(1);
  }
  return url;
}

/** Runs [fn] signed in as the clinic of [doctorId] (one transaction, committed). */
async function asClinic(db, doctorId, fn) {
  const d = (await db.query('select clinic_id from public.doctors where id = $1', [doctorId])).rows[0];
  if (!d) throw new Error(`No doctor ${doctorId}`);
  const login = (await db.query('select id from public.clinic_accounts where clinic_id = $1 limit 1', [d.clinic_id])).rows[0];
  const claims = {
    sub: login?.id ?? '00000000-0000-0000-0000-00000000005e',
    role: 'authenticated',
    app_metadata: { role: 'clinic', clinic_id: d.clinic_id },
  };
  await db.query('begin');
  try {
    await db.query(`select set_config('role', 'authenticated', true), set_config('request.jwt.claims', $1, true)`, [JSON.stringify(claims)]);
    const out = await fn();
    await db.query('commit');
    return out;
  } catch (e) {
    await db.query('rollback');
    throw e;
  }
}

const fail = (e) => `${e.message}${e.hint ? ` · ${e.hint}` : ''}`;

async function status(db, doctorId, date) {
  const day = (await db.query('select * from public.queue_days where doctor_id = $1 and date = $2', [doctorId, date])).rows[0] ?? {};
  const tokens = (await db.query(
    `select token_prefix || '-' || number as label, status, source, patient_snapshot ->> 'name' as name
       from public.tokens where doctor_id = $1 and date = $2 order by number`, [doctorId, date])).rows;
  console.log(`${doctorId} · ${date} · session ${day.session_status ?? 'notStarted'} · now serving ${day.current_token || '-'} · waiting ${JSON.stringify(day.active_numbers ?? [])}`);
  if (tokens.length === 0) console.log('  (no tokens)');
  for (const t of tokens) console.log(`  ${t.label.padEnd(6)} ${t.status.padEnd(9)} ${t.source.padEnd(8)} ${t.name ?? ''}`);
}

async function queueAction(db, doctorId, action, extra = {}) {
  const r = await asClinic(db, doctorId, () =>
    db.query('select public.queue_action($1, $2, $3, $4, $5) as r', [action, extra.doctor ?? doctorId, extra.token ?? null, extra.reason ?? null, extra.anyway ?? null]));
  return r.rows[0].r;
}

async function next(db, doctorId, anyway) {
  try {
    const r = await queueAction(db, doctorId, 'next');
    return r.called ? `Now serving ${r.called.label} (${r.called.name}).` : 'Nobody is waiting.';
  } catch (e) {
    if (e.message !== 'not-arrived') throw e;
    const d = JSON.parse(e.detail ?? '{}');
    if (!anyway) return `${d.label} (${d.name}) has not arrived. Run "next --anyway" to call them, or "skip --number ${String(d.label).split('-')[1]}".`;
    const r = await queueAction(db, doctorId, 'next', { anyway: d.tokenId });
    return `Called anyway: now serving ${r.called.label} (${r.called.name}).`;
  }
}

async function main() {
  const { command, opts } = parseArgs(process.argv.slice(2));
  const known = ['status', 'start', 'pause', 'end', 'next', 'undo', 'walkin', 'auto', ...Object.keys(TOKEN_ACTIONS)];
  if (!known.includes(command) || !opts.doctor || opts.doctor === true) {
    console.log(`Usage: node queue-sim.js <${known.join('|')}> --doctor <doctorId> [--number N] [--anyway] [--date yyyy-MM-dd]`);
    process.exit(command ? 1 : 0);
  }
  const db = new Client({ connectionString: dbUrl(), ssl: { rejectUnauthorized: false } });
  await db.connect();
  const date = opts.date && opts.date !== true ? opts.date : todayPkt();
  try {
    if (command === 'status') return await status(db, opts.doctor, date);
    if (['start', 'pause', 'end', 'undo'].includes(command)) {
      await queueAction(db, opts.doctor, command);
      console.log(`${command}: done.`);
    } else if (command === 'next') {
      console.log(await next(db, opts.doctor, opts.anyway === true));
    } else if (TOKEN_ACTIONS[command]) {
      const t = (await db.query('select id from public.tokens where doctor_id = $1 and date = $2 and number = $3', [opts.doctor, date, Number(opts.number)])).rows[0];
      if (!t) throw new Error(`No token ${opts.number} for ${opts.doctor} on ${date}`);
      await queueAction(db, opts.doctor, TOKEN_ACTIONS[command], { token: t.id, reason: opts.reason === true ? null : opts.reason });
      console.log(`${command} ${opts.number}: done.`);
    } else if (command === 'walkin') {
      const r = await asClinic(db, opts.doctor, () => db.query('select public.clinic_create_walk_in($1, null, null, $2) as r', [
        opts.doctor,
        JSON.stringify({ phone: String(opts.phone ?? ''), name: String(opts.name ?? ''), gender: String(opts.gender ?? 'male'), age: opts.age ? Number(opts.age) : null }),
      ]));
      console.log(`Walk-in ${r.rows[0].r.label} created (Arrived).`);
    } else if (command === 'auto') {
      const every = Math.max(5, Number(opts.every) || 30);
      console.log(`Auto mode: Next every ${every}s (calls not-arrived patients too). Ctrl+C to stop.`);
      await queueAction(db, opts.doctor, 'start').catch(() => {});
      for (;;) {
        console.log(new Date().toLocaleTimeString(), await next(db, opts.doctor, true).catch(fail));
        await new Promise((res) => setTimeout(res, every * 1000));
      }
    }
    await status(db, opts.doctor, date);
  } catch (e) {
    console.error(fail(e));
    process.exitCode = 1;
  } finally {
    await db.end();
  }
}

main();
