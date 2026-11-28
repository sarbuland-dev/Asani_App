-- D-68 tests: a suspended clinic is read-only but can still cancel; single-token actions only on the token's day;
-- the Super Admin's live feeds are published. Rolled back at the end. Clock: 12:00 PKT Tue 2026-11-24.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
set local asani.test_now = '2026-11-24 07:00:00+00';

select plan(20);

-- ================================================================== data
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000007c1', 'clinic7@asani.test', 'authenticated', 'authenticated');
insert into public.clinics (id, name, city, status, lat, lng) values ('s_c1', 'Seven Clinic', 'Lahore', 'active', 31.5, 74.3);
insert into public.clinic_billing (clinic_id, plan, monthly_fee, billing_day) values ('s_c1', 'basic', 3000, 1);
insert into public.clinic_accounts (id, email, clinic_id, name, status) values
  ('00000000-0000-0000-0000-0000000007c1', 'clinic7@asani.test', 's_c1', 'Manager', 'active');
insert into public.doctors (id, clinic_id, name, name_key, speciality, city, token_prefix, schedule) values
  ('s_d1', 's_c1', 'Dr. Seven', 'seven', 'heart', 'Lahore', 'A',
   '{"tue": {"start": "08:00", "end": "23:00"}, "wed": {"start": "08:00", "end": "23:00"}}');

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000007c1", "role": "authenticated", "app_metadata": {"role": "clinic", "clinic_id": "s_c1"}}';

-- two walk-ins today
select lives_ok($$ select clinic_create_walk_in('s_d1', null, null, '{"phone": "03001230071", "relation": "self", "name": "One Test", "age": 30, "gender": "male"}') $$, 'walk-in one');
select lives_ok($$ select clinic_create_walk_in('s_d1', null, null, '{"phone": "03001230072", "relation": "self", "name": "Two Test", "age": 31, "gender": "female"}') $$, 'walk-in two');

-- ================================================================== I3: only on the token's own day
set local asani.test_now = '2026-11-23 07:00:00+00';   -- "today" is the day before the tokens
select throws_ok($$ select queue_action('skip', null, (select id from tokens where doctor_id = 's_d1' and number = 1)) $$,
                 'P0001', 'not-today', 'a future token cannot be skipped');
select throws_ok($$ select queue_action('callNow', null, (select id from tokens where doctor_id = 's_d1' and number = 1)) $$,
                 'P0001', 'not-today', 'a future token cannot be called');
select throws_ok($$ select queue_action('noShow', null, (select id from tokens where doctor_id = 's_d1' and number = 1)) $$,
                 'P0001', 'not-today', 'a future token cannot be a no-show');
set local asani.test_now = '2026-11-24 07:00:00+00';
select lives_ok($$ select queue_action('callNow', null, (select id from tokens where doctor_id = 's_d1' and number = 1)) $$,
                'the same token works on its day');

-- ================================================================== I1: suspended = read-only, cancel allowed
reset role;
update public.clinics set status = 'suspended' where id = 's_c1';
set local role authenticated;
select throws_ok($$ select queue_action('callNow', null, (select id from tokens where doctor_id = 's_d1' and number = 1)) $$,
                 'P0001', 'suspended', 'no calling');
select throws_ok($$ select clinic_create_walk_in('s_d1', null, null, '{"phone": "03001230073", "relation": "self", "name": "No Entry", "age": 20, "gender": "male"}') $$,
                 'P0001', 'suspended', 'no walk-ins');
select throws_ok($$ select set_follow_up((select id from tokens where doctor_id = 's_d1' and number = 1), '2026-12-01') $$,
                 'P0001', 'suspended', 'no follow-ups');
select throws_ok($$ select set_doctor_leave('s_d1', '2026-11-25') $$, 'P0001', 'suspended', 'no leave changes');
select throws_ok($$ select set_doctor_active('s_d1', false) $$, 'P0001', 'suspended', 'no deactivating doctors');
select throws_ok($$ select save_doctor(null, 'Dr. New', 'skin', null, null, 10, 40, 7, '{}'::jsonb) $$,
                 'P0001', 'suspended', 'no new doctors');
select throws_ok($$ select clinic_update_patient((select patient_id from tokens where doctor_id = 's_d1' and number = 1), 'New Name', 'male') $$,
                 'P0001', 'suspended', 'no patient edits');
select throws_ok($$ select update_clinic_settings('Street 1', 'Area', '042-1234567', 'a5', 31.5, 74.3) $$,
                 'P0001', 'suspended', 'no settings changes');
select throws_ok($$ select link_walk_in_to_account('nobody', '03001230001') $$, 'P0001', 'suspended', 'no linking');
select lives_ok($$ select queue_action('cancel', null, (select id from tokens where doctor_id = 's_d1' and number = 2), 'Clinic closed') $$,
                'one token can still be cancelled');
select lives_ok($$ select cancel_doctor_tokens('s_d1', '2026-11-24', 'Clinic closed') $$, 'bulk cancel still works');
select is((select count(*)::integer from tokens where doctor_id = 's_d1' and status = 'cancelled'), 2, 'both are cancelled');

-- ================================================================== I2: live feeds
reset role;
select ok(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'clinic_stats'),
          'monthly token counts are published');
select ok(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'doctor_private'),
          'PMDC numbers are published');

select * from finish();
rollback;
