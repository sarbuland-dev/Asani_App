#!/usr/bin/env node
// DEV ONLY (asani-dev): creates a clinic-web login on Supabase without email (D-52, phase 7).
//   node tools/db-test/create-login.js --role superAdmin --email admin@asani.test --name "Sarbuland"
//   node tools/db-test/create-login.js --role clinic --clinic c_alshifa --email alshifa@asani.test --name "Manager"
// The role goes in app_metadata (server only). A random password is generated and APPENDED to
// tools/admin-scripts/dev-test-logins.local.txt (git-ignored); it is never printed. Real clinics get an invite
// email from the Super Admin's "New clinic" instead (admin-clinic-login).
// Running it again for the same email resets that login's password (new line in the file).
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { Client } = require('pg');

const root = path.resolve(__dirname, '..', '..');
const arg = (k) => {
  const i = process.argv.indexOf(`--${k}`);
  return i > 0 ? process.argv[i + 1] : undefined;
};
const role = arg('role');
const email = (arg('email') ?? '').trim().toLowerCase();
const name = arg('name') ?? '';
const clinicId = arg('clinic');
if (!['superAdmin', 'clinic'].includes(role) || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || (role === 'clinic' && !clinicId)) {
  console.error('Usage: --role superAdmin|clinic --email <email> --name <name> [--clinic <clinicId>]');
  process.exit(2);
}

(async () => {
  const url = process.env.SUPABASE_DB_URL ?? fs.readFileSync(path.join(root, 'supabase', '.db-url.local'), 'utf8').trim();
  const pg = new Client({ connectionString: url, ssl: { rejectUnauthorized: false } });
  await pg.connect();
  const password = crypto.randomBytes(12).toString('base64url');
  const meta = { provider: 'email', providers: ['email'], role, ...(role === 'clinic' ? { clinic_id: clinicId } : {}) };
  try {
    await pg.query('begin');
    if (role === 'clinic') {
      const c = await pg.query('select name from public.clinics where id = $1', [clinicId]);
      if (!c.rowCount) throw new Error(`No clinic ${clinicId}`);
    }
    let id = (await pg.query('select id from auth.users where email = $1', [email])).rows[0]?.id;
    if (id) {
      await pg.query(
        `update auth.users set encrypted_password = extensions.crypt($2, extensions.gen_salt('bf')), raw_app_meta_data = $3::jsonb,
           email_confirmed_at = coalesce(email_confirmed_at, now()), banned_until = null, updated_at = now() where id = $1`,
        [id, password, JSON.stringify(meta)],
      );
    } else {
      id = crypto.randomUUID();
      await pg.query(
        `insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data,
           raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)
         values ('00000000-0000-0000-0000-000000000000', $1, 'authenticated', 'authenticated', $2,
           extensions.crypt($3, extensions.gen_salt('bf')), now(), $4::jsonb, jsonb_build_object('name', $5::text), now(), now(), '', '', '', '')`,
        [id, email, password, JSON.stringify(meta), name],
      );
      await pg.query(
        `insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
         values (gen_random_uuid(), $1::text::uuid, $1::text, jsonb_build_object('sub', $1::text, 'email', $2::text), 'email', now(), now(), now())`,
        [id, email],
      );
    }
    if (role === 'superAdmin') {
      await pg.query(
        `insert into public.admin_users (id, email, name) values ($1, $2, $3) on conflict (id) do update set email = excluded.email, name = excluded.name`,
        [id, email, name],
      );
    } else {
      await pg.query(
        `insert into public.clinic_accounts (id, email, clinic_id, name, status, invited_at) values ($1, $2, $3, $4, 'active', now())
         on conflict (id) do update set email = excluded.email, clinic_id = excluded.clinic_id, name = excluded.name, status = 'active'`,
        [id, email, clinicId, name],
      );
    }
    await pg.query('commit');
    const file = path.join(root, 'tools', 'admin-scripts', 'dev-test-logins.local.txt');
    fs.appendFileSync(file, `\n[Supabase asani-dev, ${new Date().toISOString().slice(0, 10)}] ${role}${clinicId ? ` ${clinicId}` : ''}: ${email} / ${password}\n`);
    console.log(`OK: ${role} login ${email}${clinicId ? ` (${clinicId})` : ''}. Password saved in tools/admin-scripts/dev-test-logins.local.txt`);
  } catch (e) {
    await pg.query('rollback').catch(() => {});
    console.error('ERROR', e.message);
    process.exitCode = 1;
  } finally {
    await pg.end();
  }
})();
