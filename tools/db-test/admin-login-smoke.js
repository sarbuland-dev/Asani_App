#!/usr/bin/env node
// Phase 6 check of the admin-clinic-login Edge Function (D-52) against asani-dev, WITHOUT sending a real email:
//  - a patient login is refused (403), a bad email is refused (400),
//  - "create" with an @asani.test address: Supabase refuses to email it, and the function must undo the clinic it
//    already created (no clinic without a login),
//  - "resend" for a clinic without a login → not-found.
// Temporary password logins and rows are deleted afterwards. Usage: node tools/db-test/admin-login-smoke.js
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { Client } = require('pg');
const { createClient } = require('@supabase/supabase-js');

const root = path.resolve(__dirname, '..', '..');
const dbUrl = process.env.SUPABASE_DB_URL ?? fs.readFileSync(path.join(root, 'supabase', '.db-url.local'), 'utf8').trim();
const URL = 'https://lgnbxxcmogbbzmuqyrgu.supabase.co';
const KEY = 'sb_publishable_Hgin4aABXeUBXqu02QODMg_81Loge4G';
const ADMIN = { id: '00000000-0000-0000-0000-0000000007ad', email: 'smoke-admin@asani.test', meta: { provider: 'email', providers: ['email'], role: 'superAdmin' } };
const PATIENT = { id: '00000000-0000-0000-0000-0000000007a1', email: 'smoke-patient@asani.test', meta: { provider: 'email', providers: ['email'] } };
const PASSWORD = crypto.randomBytes(18).toString('base64url');
const CLINIC_NAME = 'Smoke Rollback Clinic';

let failures = 0;
const check = (ok, label, extra = '') => {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${extra ? ` (${extra})` : ''}`);
  if (!ok) failures++;
};

async function cleanup(pg) {
  await pg.query(`delete from public.clinics where name = $1`, [CLINIC_NAME]);
  await pg.query(`delete from public.admin_users where id = $1`, [ADMIN.id]);
  await pg.query(`delete from auth.users where id in ($1, $2) or email = 'rollback-smoke@asani.test'`, [ADMIN.id, PATIENT.id]);
}

async function createLogin(pg, u) {
  await pg.query(
    `insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data,
       raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)
     values ('00000000-0000-0000-0000-000000000000', $1, 'authenticated', 'authenticated', $2,
       extensions.crypt($3, extensions.gen_salt('bf')), now(), $4::jsonb, '{}', now(), now(), '', '', '', '')`,
    [u.id, u.email, PASSWORD, JSON.stringify(u.meta)],
  );
  await pg.query(
    `insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
     values (gen_random_uuid(), $1::text::uuid, $1::text, jsonb_build_object('sub', $1::text, 'email', $2::text), 'email', now(), now(), now())`,
    [u.id, u.email],
  );
}

async function call(u, body) {
  const c = createClient(URL, KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await c.auth.signInWithPassword({ email: u.email, password: PASSWORD });
  if (error) throw new Error(`sign-in ${u.email}: ${error.message}`);
  const res = await fetch(`${URL}/functions/v1/admin-clinic-login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: KEY, Authorization: `Bearer ${data.session.access_token}` },
    body: JSON.stringify(body),
  });
  return { status: res.status, body: await res.json().catch(() => ({})) };
}

(async () => {
  const pg = new Client({ connectionString: dbUrl, ssl: { rejectUnauthorized: false } });
  await pg.connect();
  try {
    await cleanup(pg);
    await createLogin(pg, ADMIN);
    await createLogin(pg, PATIENT);
    await pg.query(`insert into public.admin_users (id, email, name) values ($1, $2, 'Smoke Admin')`, [ADMIN.id, ADMIN.email]);

    let r = await call(PATIENT, { action: 'resend', clinicId: 'x' });
    check(r.status === 403 && r.body.error === 'permission-denied', 'a patient is refused', `${r.status} ${r.body.error}`);

    r = await call(ADMIN, { action: 'create', clinic: { email: 'not-an-email' } });
    check(r.status === 400 && r.body.error === 'invalid-argument', 'a bad email is refused', `${r.status} ${r.body.error}`);

    r = await call(ADMIN, { action: 'create', clinic: { email: 'x@asani.test', name: 'No Location' } });
    check(r.status === 400 && r.body.error === 'invalid-argument', 'missing fields are refused before anything is made', `${r.status} ${r.body.message}`);

    const clinic = {
      email: 'rollback-smoke@asani.test', name: CLINIC_NAME, area: 'Test', city: 'Lahore', address: 'Test road', phone: '042-0',
      lat: 31.5, lng: 74.3, printFormat: 'thermal80', planAfterPilot: 'basic', pilotDays: 30, monthlyFee: 3000, billingDay: 1,
      ownerName: 'Smoke Owner', ownerPhone: '03000000000',
    };
    r = await call(ADMIN, { action: 'create', clinic });
    const left = (await pg.query(`select count(*)::int n from public.clinics where name = $1`, [CLINIC_NAME])).rows[0].n;
    if (r.status === 200) {
      check(true, 'create worked (the invite email was accepted)', JSON.stringify(r.body));
    } else {
      check(left === 0, 'invite refused → the half-made clinic was removed (no clinic without a login)', `${r.status} ${r.body.message}`);
    }

    r = await call(ADMIN, { action: 'resend', clinicId: 'c_alshifa' });
    check(r.status === 400 && r.body.error === 'not-found', 'resend for a clinic without a login → not-found', `${r.status} ${r.body.error}`);
  } catch (e) {
    console.error('ERROR', e.message);
    failures++;
  } finally {
    await cleanup(pg).catch((e) => console.error('cleanup failed', e.message));
    await pg.end();
    console.log(failures ? `\n${failures} check(s) failed` : '\nPASS');
    process.exit(failures ? 1 : 0);
  }
})();
