-- RLS tests (D-52), port of functions/test/rules/*.test.js.
-- Runs inside one transaction that is rolled back, so nothing stays in the database.
-- Run: node tools/db-test/run.js   (see docs/02-setup.md, Supabase section)
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(37);

-- ------------------------------------------------------------------ test data (as the database owner)
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-00000000000a', 'a@asani.test', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-00000000000b', 'b@asani.test', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-00000000000c', 'clinic@asani.test', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-00000000000d', 'admin@asani.test', 'authenticated', 'authenticated');

insert into public.users (id, email, phone, name) values
  ('00000000-0000-0000-0000-00000000000a', 'a@asani.test', '+923000000001', 'Patient A'),
  ('00000000-0000-0000-0000-00000000000b', 'b@asani.test', '+923000000002', 'Patient B');

insert into public.clinics (id, name, city, status) values
  ('t_c1', 'Test Clinic One', 'Lahore', 'active'),
  ('t_c2', 'Test Clinic Two', 'Lahore', 'active');
insert into public.clinic_billing (clinic_id) values ('t_c1'), ('t_c2');
insert into public.doctors (id, clinic_id, name, token_prefix) values
  ('t_d1', 't_c1', 'Dr. One', 'A'),
  ('t_d2', 't_c2', 'Dr. Two', 'A');
insert into public.doctor_private (doctor_id, clinic_id, pmdc_number) values ('t_d1', 't_c1', '12345-P');
insert into public.doctor_link_suggestions (id, doctor_ids, clinic_ids, strength)
  values ('t_d1_t_d2', '{t_d1,t_d2}', '{t_c1,t_c2}', 'weak');

insert into public.patients (id, phone, owner_uid, name, birth_year, gender, relation, created_by, clinic_ids) values
  ('t_pa', '+923000000001', '00000000-0000-0000-0000-00000000000a', 'Patient A', 1990, 'male',   'self', 'app',   '{t_c1}'),
  ('t_pb', '+923000000002', '00000000-0000-0000-0000-00000000000b', 'Patient B', 1985, 'female', 'self', 'app',   '{t_c2}'),
  ('t_pw', '+923000000009', null,                                   'Walk In',   1970, 'male',   'self', 'staff', '{t_c1}');

insert into public.queue_days (doctor_id, date, clinic_id) values ('t_d1', '2026-11-24', 't_c1'), ('t_d2', '2026-11-24', 't_c2');
insert into public.tokens (id, clinic_id, doctor_id, date, number, token_prefix, patient_id, patient_snapshot,
                           booked_by_user_id, patient_owner_uid, source) values
  ('t_ta', 't_c1', 't_d1', '2026-11-24', 1, 'A', 't_pa', '{}', '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000a', 'app'),
  ('t_tb', 't_c2', 't_d2', '2026-11-24', 1, 'A', 't_pb', '{}', '00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000b', 'app'),
  ('t_tw', 't_c1', 't_d1', '2026-11-24', 2, 'A', 't_pw', '{}', null,                                   '00000000-0000-0000-0000-00000000000a', 'walkIn');

insert into public.notifications (user_id, type, title, body) values
  ('00000000-0000-0000-0000-00000000000a', 'queue', 'For A', 'x'),
  ('00000000-0000-0000-0000-00000000000b', 'queue', 'For B', 'x');
insert into public.invoices (id, clinic_id, month, amount, due_date) values
  ('inv_t_c1_2026-11', 't_c1', '2026-11', 3000, '2026-11-08'),
  ('inv_t_c2_2026-11', 't_c2', '2026-11', 3000, '2026-11-08');
insert into public.clinic_pins (clinic_id, hash) values ('t_c1', 'x');

-- ------------------------------------------------------------------ anonymous visitor
set local role anon;
select throws_ok($$ select * from public.clinics $$, '42501', null, 'anon cannot read clinics');

-- ------------------------------------------------------------------ patient A
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-00000000000a", "role": "authenticated", "app_metadata": {}}';

select results_eq($$ select id::text from public.users $$, array['00000000-0000-0000-0000-00000000000a'], 'patient reads only own user row');
select results_eq($$ select id from public.patients where id like 't_%' order by id $$, array['t_pa'], 'patient sees only own profiles');
select results_eq($$ select id from public.tokens where id like 't_%' order by id $$, array['t_ta', 't_tw'],
                  'patient sees own booking and walk-ins on own profiles (D-22), not others');
select results_eq($$ select title from public.notifications $$, array['For A'], 'patient sees only own notifications');
select ok((select count(*) from public.clinics where id like 't_%') = 2, 'patient reads clinics');
select ok((select count(*) from public.doctors where id like 't_%') = 2, 'patient reads doctors');
select ok((select count(*) from public.queue_days where doctor_id like 't_%') = 2, 'patient reads queue days');
select is_empty($$ select * from public.clinic_billing where clinic_id like 't_%' $$, 'patient cannot see billing');
select is_empty($$ select * from public.doctor_private $$, 'patient cannot see PMDC (D-33)');
select is_empty($$ select * from public.doctor_link_suggestions $$, 'patient cannot see link suggestions');
select is_empty($$ select * from public.invoices where clinic_id like 't_%' $$, 'patient cannot see invoices');
select throws_ok($$ select * from public.clinic_pins $$, '42501', null, 'nobody reads clinic PINs');
select throws_ok($$ select * from public.push_outbox $$, '42501', null, 'nobody reads the push outbox');

-- direct writes that are allowed
select lives_ok($$ update public.users set city = 'Karachi', queue_alerts_enabled = false
                   where id = '00000000-0000-0000-0000-00000000000a' $$, 'patient updates own city and alerts');
select lives_ok($$ insert into public.patients (name, birth_year, gender, relation) values ('Mother A', 1960, 'female', 'mother') $$,
                'patient adds a family member');
select results_eq($$ select phone, created_by, status from public.patients where name = 'Mother A' $$,
                  $$ values ('+923000000001'::text, 'app'::text, 'active'::text) $$,
                  'new family member gets the account phone, created_by app, active');
select lives_ok($$ insert into public.devices (user_id, device_id, fcm_token, platform)
                   values ('00000000-0000-0000-0000-00000000000a', 'dev-1', 'tok', 'android') $$, 'patient saves own device');

-- direct writes that are refused
select throws_ok($$ update public.users set phone = '+923009999999' where id = '00000000-0000-0000-0000-00000000000a' $$,
                 '42501', null, 'patient cannot change phone directly (update_phone only)');
select throws_ok($$ insert into public.patients (name, birth_year, gender, relation) values ('Me Again', 1990, 'male', 'self') $$,
                 '23514', null, 'patient cannot add a second Self profile');
select throws_ok($$ update public.patients set status = 'deleted' where id = 't_pa' $$, '23514', null, 'Self profile cannot be removed');
select throws_ok($$ update public.patients set clinic_ids = '{t_c2}' where id = 't_pa' $$, '42501', null, 'patient cannot change clinic_ids');
select is_empty($$ update public.patients set name = 'Hacked' where id = 't_pb' returning id $$, 'patient cannot edit another family''s profile');
select throws_ok($$ insert into public.tokens (clinic_id, doctor_id, date, number, token_prefix, patient_id, patient_snapshot, source)
                    values ('t_c1', 't_d1', '2026-11-24', 9, 'A', 't_pa', '{}', 'app') $$, '42501', null, 'patient cannot write tokens');
select throws_ok($$ update public.queue_days set last_token_number = 99 $$, '42501', null, 'patient cannot write queue days');
select throws_ok($$ insert into public.devices (user_id, device_id, fcm_token, platform)
                    values ('00000000-0000-0000-0000-00000000000b', 'dev-x', 'tok', 'android') $$, '42501', null,
                 'patient cannot save a device for another account');

-- ------------------------------------------------------------------ clinic login of t_c1
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-00000000000c", "role": "authenticated", "app_metadata": {"role": "clinic", "clinic_id": "t_c1"}}';

select results_eq($$ select clinic_id from public.clinic_billing where clinic_id like 't_%' $$, array['t_c1'], 'clinic reads only own billing');
select results_eq($$ select id from public.tokens where id like 't_%' order by id $$, array['t_ta', 't_tw'], 'clinic reads only own clinic tokens');
select results_eq($$ select id from public.patients where id like 't_%' order by id $$, array['t_pa', 't_pw'],
                  'clinic reads only patients who visited it (BW-6)');
select results_eq($$ select id from public.invoices where clinic_id like 't_%' $$, array['inv_t_c1_2026-11'], 'clinic reads only own invoices');
select is_empty($$ select * from public.doctor_private $$, 'clinic cannot read PMDC back (D-33)');
select is_empty($$ select * from public.users $$, 'clinic cannot read patient accounts');
select throws_ok($$ insert into public.patients (name, birth_year, gender, relation) values ('X Y', 1990, 'male', 'mother') $$,
                 '23514', null, 'clinic cannot add app family profiles directly (no app profile)');

-- ------------------------------------------------------------------ Super Admin
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-00000000000d", "role": "authenticated", "app_metadata": {"role": "superAdmin"}}';

select results_eq($$ select pmdc_number from public.doctor_private where doctor_id = 't_d1' $$, array['12345-P'], 'Super Admin reads PMDC');
select ok((select count(*) from public.doctor_link_suggestions where id = 't_d1_t_d2') = 1, 'Super Admin reads link suggestions');
select ok((select count(*) from public.clinic_billing where clinic_id like 't_%') = 2, 'Super Admin reads every clinic''s billing');

-- ------------------------------------------------------------------ user_metadata is never trusted
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-00000000000b", "role": "authenticated", "app_metadata": {}, "user_metadata": {"role": "superAdmin"}}';
select is_empty($$ select * from public.doctor_private $$, 'a role in user_metadata gives no access');

select * from finish();
rollback;
