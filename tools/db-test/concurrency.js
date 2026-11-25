#!/usr/bin/env node
// PRD F-04 acceptance: "two users booking the same doctor at the same moment never get the same number".
// 10 database connections each book 2 tokens on one doctor at the same time (20 bookings), then we check
// the numbers are exactly 1..20 and the queue day agrees.
//
// Unlike the pgTAP files this must COMMIT (other connections only see committed rows), so it creates its own
// rows with the prefix cc_ (and @cc.asani.test accounts) and deletes ONLY those rows afterwards.
// Usage: node tools/db-test/concurrency.js
const fs = require('node:fs');
const path = require('node:path');
const { Client } = require('pg');

const root = path.resolve(__dirname, '..', '..');
const url = process.env.SUPABASE_DB_URL ?? fs.readFileSync(path.join(root, 'supabase', '.db-url.local'), 'utf8').trim();
const connect = async () => {
  const c = new Client({ connectionString: url, ssl: { rejectUnauthorized: false } });
  await c.connect();
  return c;
};

const USERS = 10;
const uid = (i) => `00000000-0000-0000-0000-0000000cc${String(i).padStart(3, '0')}`;
const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Karachi' }).format(new Date());

async function cleanup(c) {
  await c.query(`delete from public.tokens where clinic_id = 'cc_clinic'`);
  await c.query(`delete from public.queue_days where clinic_id = 'cc_clinic'`);
  await c.query(`delete from public.patients where id like 'cc\\_%'`);
  await c.query(`delete from public.doctors where id = 'cc_doctor'`);
  await c.query(`delete from public.clinics where id = 'cc_clinic'`);
  await c.query(`delete from public.users where email like '%@cc.asani.test'`);
  await c.query(`delete from auth.users where email like '%@cc.asani.test'`);
}

(async () => {
  const admin = await connect();
  let ok = false;
  try {
    await cleanup(admin);
    await admin.query(`insert into public.clinics (id, name, city, status) values ('cc_clinic', 'Concurrency Clinic', 'Lahore', 'active')`);
    const allDay = JSON.stringify(Object.fromEntries(['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'].map((d) => [d, { start: '00:00', end: '23:59' }])));
    await admin.query(
      `insert into public.doctors (id, clinic_id, name, token_prefix, max_tokens_per_day, schedule) values ('cc_doctor', 'cc_clinic', 'Dr. Race', 'A', 100, $1)`,
      [allDay],
    );
    for (let i = 0; i < USERS; i++) {
      const phone = `+9230000${String(90000 + i)}`;
      await admin.query(`insert into auth.users (id, email, aud, role) values ($1, $2, 'authenticated', 'authenticated')`, [uid(i), `u${i}@cc.asani.test`]);
      await admin.query(`insert into public.users (id, email, phone, name) values ($1, $2, $3, $4)`, [uid(i), `u${i}@cc.asani.test`, phone, `Racer ${i}`]);
      for (const rel of ['self', 'son']) {
        await admin.query(
          `insert into public.patients (id, phone, owner_uid, name, birth_year, gender, relation, created_by) values ($1, $2, $3, $4, 1990, 'male', $5, 'app')`,
          [`cc_${i}_${rel}`, phone, uid(i), `Racer ${i} ${rel}`, rel],
        );
      }
    }

    // Open all connections first, then fire every booking together.
    const clients = await Promise.all(Array.from({ length: USERS }, connect));
    const started = Date.now();
    const results = await Promise.all(
      clients.map(async (c, i) => {
        const out = [];
        for (const rel of ['self', 'son']) {
          await c.query('begin');
          await c.query(`select set_config('role', 'authenticated', true), set_config('request.jwt.claims', $1, true)`, [
            JSON.stringify({ sub: uid(i), role: 'authenticated', app_metadata: {} }),
          ]);
          const r = await c.query(`select public.book_token('cc_clinic', 'cc_doctor', $1, $2) as res`, [`cc_${i}_${rel}`, today]);
          await c.query('commit');
          out.push(Number(r.rows[0].res.number));
        }
        return out;
      }),
    );
    const ms = Date.now() - started;
    await Promise.all(clients.map((c) => c.end()));

    const numbers = results.flat().sort((a, b) => a - b);
    const expected = Array.from({ length: USERS * 2 }, (_, k) => k + 1);
    const day = (await admin.query(`select last_token_number, active_numbers from public.queue_days where doctor_id = 'cc_doctor' and date = $1`, [today])).rows[0];
    const dupes = numbers.length - new Set(numbers).size;

    ok = JSON.stringify(numbers) === JSON.stringify(expected) && day.last_token_number === USERS * 2 && day.active_numbers.length === USERS * 2;
    console.log(`${USERS * 2} bookings on ${USERS} connections in ${ms} ms`);
    console.log(`numbers: ${numbers.join(', ')}`);
    console.log(`duplicates: ${dupes} · last_token_number: ${day.last_token_number} · active: ${day.active_numbers.length}`);
    console.log(ok ? 'PASS: every booking got its own number' : 'FAIL');
  } catch (e) {
    console.error('ERROR', e.message);
  } finally {
    await cleanup(admin).catch((e) => console.error('cleanup failed', e.message));
    await admin.end();
    process.exit(ok ? 0 : 1);
  }
})();
