#!/usr/bin/env node
// Phase 5 client smoke test (D-52): does what the patient app does, from OUTSIDE the database, with the public
// (publishable) key and a real signed-in session: create_profile, family insert, book_token, cancel_token,
// Realtime on the queue day and own tokens, RLS (cannot see other accounts), notifications list.
//
// It creates a temporary password login (email codes need a mailbox) and its own sm_ clinic/doctor, then deletes
// ONLY those rows. Usage: node tools/db-test/client-smoke.js
const fs = require('node:fs');
const path = require('node:path');
const { Client } = require('pg');
const { createClient } = require('@supabase/supabase-js');

const root = path.resolve(__dirname, '..', '..');
const dbUrl = process.env.SUPABASE_DB_URL ?? fs.readFileSync(path.join(root, 'supabase', '.db-url.local'), 'utf8').trim();
const URL = 'https://lgnbxxcmogbbzmuqyrgu.supabase.co';
const KEY = 'sb_publishable_Hgin4aABXeUBXqu02QODMg_81Loge4G'; // public
const A = { id: '00000000-0000-0000-0000-0000000005a1', email: 'smoke-a@asani.test' };
const B = { id: '00000000-0000-0000-0000-0000000005b1', email: 'smoke-b@asani.test' };
const PASSWORD = require('node:crypto').randomBytes(18).toString('base64url'); // throwaway, never stored
const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Karachi' }).format(new Date());

let failures = 0;
const check = (ok, label, extra = '') => {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${extra ? ` (${extra})` : ''}`);
  if (!ok) failures++;
};
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

async function cleanup(pg) {
  await pg.query(`delete from public.tokens where clinic_id = 'sm_clinic'`);
  await pg.query(`delete from public.queue_days where clinic_id = 'sm_clinic'`);
  await pg.query(`delete from public.clinic_stats where clinic_id = 'sm_clinic'`);
  await pg.query(`delete from public.patients where owner_uid in ($1, $2) or id like 'sm\\_%'`, [A.id, B.id]);
  await pg.query(`delete from public.doctors where id = 'sm_doctor'`);
  await pg.query(`delete from public.clinics where id = 'sm_clinic'`);
  await pg.query(`delete from auth.users where id in ($1, $2)`, [A.id, B.id]);
}

async function createLogin(pg, u) {
  await pg.query(
    `insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
       raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, email_change,
       email_change_token_new, recovery_token)
     values ('00000000-0000-0000-0000-000000000000', $1, 'authenticated', 'authenticated', $2,
       extensions.crypt($3, extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}',
       now(), now(), '', '', '', '')`,
    [u.id, u.email, PASSWORD],
  );
  await pg.query(
    `insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
     values (gen_random_uuid(), $1::text::uuid, $1::text, jsonb_build_object('sub', $1::text, 'email', $2::text), 'email', now(), now(), now())`,
    [u.id, u.email],
  );
}

async function signIn(u) {
  const c = createClient(URL, KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  const { error } = await c.auth.signInWithPassword({ email: u.email, password: PASSWORD });
  if (error) throw new Error(`sign-in ${u.email}: ${error.message}`);
  return c;
}

(async () => {
  const pg = new Client({ connectionString: dbUrl, ssl: { rejectUnauthorized: false } });
  await pg.connect();
  const channels = [];
  try {
    await cleanup(pg);
    await pg.query(`insert into public.clinics (id, name, city, status, lat, lng) values ('sm_clinic', 'Smoke Clinic', 'Lahore', 'active', 31.5, 74.3)`);
    const allDay = JSON.stringify(Object.fromEntries(['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'].map((d) => [d, { start: '00:00', end: '23:59' }])));
    await pg.query(`insert into public.doctors (id, clinic_id, name, token_prefix, schedule, city) values ('sm_doctor', 'sm_clinic', 'Dr. Smoke', 'S', $1, 'Lahore')`, [allDay]);
    await createLogin(pg, A);
    await createLogin(pg, B);

    const a = await signIn(A);
    const b = await signIn(B);

    // ---- profile setup (phase 4 function, through the API)
    let r = await a.rpc('create_profile', { p_name: 'Smoke A', p_age: 30, p_gender: 'male', p_phone: '+923009990001' });
    check(!r.error && r.data.created === true, 'A: create_profile', r.error?.message);
    r = await b.rpc('create_profile', { p_name: 'Smoke B', p_age: 30, p_gender: 'female', p_phone: '03009990001' });
    check(r.error?.message === 'phone-taken', 'B: same phone → phone-taken', r.error?.message);
    r = await b.rpc('create_profile', { p_name: 'Smoke B', p_age: 30, p_gender: 'female', p_phone: '3009990002' });
    check(!r.error, 'B: create_profile with another number', r.error?.message);

    // ---- reads the app does
    r = await a.from('users').select('*');
    check(!r.error && r.data.length === 1 && r.data[0].phone_verified === false, 'A sees only own users row, phone not verified');
    r = await a.from('clinics').select('id').eq('id', 'sm_clinic');
    check(!r.error && r.data.length === 1, 'A reads clinics');

    // ---- family: direct insert like addPatient
    r = await a.from('patients').insert({ name: 'Smoke Mother', birth_year: 1960, gender: 'female', relation: 'mother' }).select().single();
    check(!r.error && r.data.phone === '+923009990001' && r.data.owner_uid === A.id, 'A adds a family member (owner + phone filled by the DB)', r.error?.message);
    const mother = r.data;
    r = await b.from('patients').select('id').eq('id', mother.id);
    check(!r.error && r.data.length === 0, 'B cannot see A\'s family');

    // ---- Realtime: queue day + own tokens. Like the app, token / profile streams use NO uuid filter
    // (Realtime filters on uuid columns never fire); RLS alone limits them to the user's own rows.
    const events = { day: 0, tokenA: 0, tokenB: 0 };
    const owners = { tokenA: new Set(), tokenB: new Set() };
    const subscribe = (client, name, opts, key) =>
      new Promise((resolve) => {
        const ch = client
          .channel(name)
          .on('postgres_changes', opts, (p) => {
            events[key]++;
            owners[key]?.add(p.new?.booked_by_user_id);
          })
          .subscribe((status) => status === 'SUBSCRIBED' && resolve());
        channels.push([client, ch]);
      });
    await subscribe(a, 'day', { event: '*', schema: 'public', table: 'queue_days', filter: 'doctor_id=eq.sm_doctor' }, 'day');
    await subscribe(a, 'tokA', { event: '*', schema: 'public', table: 'tokens' }, 'tokenA');
    await subscribe(b, 'tokB', { event: '*', schema: 'public', table: 'tokens' }, 'tokenB');

    // ---- booking
    const selfA = (await a.from('users').select('self_patient_id').single()).data.self_patient_id;
    r = await a.rpc('book_token', { p_clinic_id: 'sm_clinic', p_doctor_id: 'sm_doctor', p_patient_id: selfA, p_date: today });
    check(!r.error && r.data.number === 1, 'A books → number 1', r.error?.message);
    const t1 = r.data?.tokenId;
    r = await a.rpc('book_token', { p_clinic_id: 'sm_clinic', p_doctor_id: 'sm_doctor', p_patient_id: mother.id, p_date: today });
    check(!r.error && r.data.number === 2, 'A books for mother → number 2', r.error?.message);
    r = await a.rpc('book_token', { p_clinic_id: 'sm_clinic', p_doctor_id: 'sm_doctor', p_patient_id: selfA, p_date: today });
    check(r.error?.message === 'duplicate-token' && /"label"/.test(r.error?.details ?? ''), 'duplicate → duplicate-token with details', r.error?.message);
    const selfB = (await b.from('users').select('self_patient_id').single()).data.self_patient_id;
    r = await b.rpc('book_token', { p_clinic_id: 'sm_clinic', p_doctor_id: 'sm_doctor', p_patient_id: selfA, p_date: today });
    check(r.error?.message === 'permission-denied', 'B cannot book for A\'s profile', r.error?.message);
    r = await b.rpc('book_token', { p_clinic_id: 'sm_clinic', p_doctor_id: 'sm_doctor', p_patient_id: selfB, p_date: today });
    check(!r.error && r.data.number === 3, 'B books → number 3', r.error?.message);

    await wait(4000);
    check(events.day >= 1, 'Realtime: queue day changes reach the app', `${events.day} events`);
    check(events.tokenA >= 2 && [...owners.tokenA].every((o) => o === A.id), 'Realtime: A receives own token changes only', `${events.tokenA} events`);
    check(events.tokenB >= 1 && [...owners.tokenB].every((o) => o === B.id), 'Realtime + RLS: B receives only own token, not A\'s', `${events.tokenB} events`);

    r = await a.from('queue_days').select('active_numbers').eq('doctor_id', 'sm_doctor').eq('date', today).single();
    check(JSON.stringify(r.data?.active_numbers) === '[1,2,3]', 'queue day active numbers [1,2,3]', JSON.stringify(r.data?.active_numbers));
    r = await a.from('tokens').select('number').eq('doctor_id', 'sm_doctor').order('number');
    check(JSON.stringify(r.data?.map((t) => t.number)) === '[1,2]', 'A sees only own tokens (1, 2), not B\'s');

    // ---- notifications list: #2 (1 ahead) and B's #3 (2 ahead) got a queue entry at booking
    r = await a.from('notifications').select('title, route').eq('type', 'queue');
    check(!r.error && r.data.some((n) => n.title === "You're next"), 'A has "You\'re next" in the notifications list', JSON.stringify(r.data));
    r = await a.from('users').update({ notifications_seen_at: new Date().toISOString() }).eq('id', A.id).select('notifications_seen_at');
    check(!r.error && r.data?.[0]?.notifications_seen_at, 'markAllSeen writes notifications_seen_at');

    // ---- cancel
    r = await a.rpc('cancel_token', { p_token_id: t1 });
    check(!r.error, 'A cancels #1', r.error?.message);
    r = await b.rpc('cancel_token', { p_token_id: t1 });
    check(r.error?.message === 'not-found', 'B cannot cancel A\'s token', r.error?.message);
    r = await a.from('queue_days').select('active_numbers').eq('doctor_id', 'sm_doctor').eq('date', today).single();
    check(JSON.stringify(r.data?.active_numbers) === '[2,3]', 'cancelled number left the queue', JSON.stringify(r.data?.active_numbers));

    // ---- Realtime filters the app uses on text / boolean columns (clinic page, doctor lists)
    // (Filters on `id` and on uuid columns never fire, so the app does not use them.)
    const docEvents = { byClinic: 0, byActive: 0, byCity: 0 };
    for (const [key, table, filter] of [['byClinic', 'doctors', 'clinic_id=eq.sm_clinic'], ['byActive', 'doctors', 'active=eq.true'],
                                        ['byCity', 'clinics', 'city=eq.Lahore']]) {
      await new Promise((resolve) => {
        const ch = a
          .channel(`doc-${key}`)
          .on('postgres_changes', { event: '*', schema: 'public', table, filter }, () => docEvents[key]++)
          .subscribe((s) => s === 'SUBSCRIBED' && resolve());
        channels.push([a, ch]);
      });
    }
    await pg.query(`update public.doctors set sort_order = sort_order + 1 where id = 'sm_doctor'`);
    await pg.query(`update public.clinics set phone = '042-0000000' where id = 'sm_clinic'`);
    await wait(4000);
    check(docEvents.byClinic >= 1 && docEvents.byActive >= 1 && docEvents.byCity >= 1,
      'Realtime filters the app uses (clinic_id, active, city) fire', JSON.stringify(docEvents));

    // ---- device for pushes (PushService → devices)
    r = await a.from('devices').upsert({ user_id: A.id, device_id: 'smoke', fcm_token: 'x', platform: 'android', app_version: 'smoke' }, { onConflict: 'user_id,device_id' });
    check(!r.error, 'A saves a device token', r.error?.message);
    r = await b.from('devices').select('*').eq('user_id', A.id);
    check(!r.error && r.data.length === 0, 'B cannot see A\'s devices');
    await pg.query(`delete from public.push_outbox where user_id in ($1, $2)`, [A.id, B.id]); // never send to the fake token
  } catch (e) {
    console.error('ERROR', e.message);
    failures++;
  } finally {
    for (const [client, ch] of channels) await client.removeChannel(ch).catch(() => {});
    await cleanup(pg).catch((e) => console.error('cleanup failed', e.message));
    await pg.end();
    console.log(failures ? `\n${failures} check(s) failed` : '\nPASS: the app\'s Supabase calls work end to end');
    process.exit(failures ? 1 : 0);
  }
})();
