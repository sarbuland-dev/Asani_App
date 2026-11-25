-- Phase 4 tests (D-52): create_profile / update_phone, phone format, one phone = one app account.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
set local asani.test_now = '2026-11-24 07:00:00+00';

select plan(20);

-- ================================================================== phone format (same as PhoneUtils)
select is(private.normalize_pk_mobile('3001234567'), '+923001234567', '10 digits');
select is(private.normalize_pk_mobile('0300-1234567'), '+923001234567', 'leading 0 and a dash');
select is(private.normalize_pk_mobile('+92 300 1234567'), '+923001234567', '+92 with spaces');
select is(private.normalize_pk_mobile('923001234567'), '+923001234567', '92 prefix');
select is(private.normalize_pk_mobile('4001234567'), null, 'not a mobile (must start with 3)');
select is(private.normalize_pk_mobile('30012345'), null, 'too short');

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000000c1', 'c1@asani.test', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000c2', 'c2@asani.test', 'authenticated', 'authenticated');

-- ================================================================== first account
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000c1", "role": "authenticated", "email": "c1@asani.test", "app_metadata": {}}';

select throws_ok($$ select create_profile('Ali Khan', 30, 'male', '12345') $$, 'P0001', 'invalid-phone', 'bad phone → invalid-phone');
select throws_ok($$ select create_profile('A', 30, 'male', '3001110001') $$, 'P0001', 'invalid-argument', 'name too short');
select is((create_profile('  Ali   Khan ', 30, 'male', '0300 1110001')) ->> 'created', 'true', 'profile created');
select results_eq($$ select email, phone, phone_verified, name from users $$,
                  $$ values ('c1@asani.test'::text, '+923001110001'::text, false, 'Ali Khan'::text) $$,
                  'account row: email from the login, normalised phone, not verified, clean name');
select results_eq($$ select relation, phone, birth_year, created_by from patients $$,
                  $$ values ('self'::text, '+923001110001'::text, 1996, 'app'::text) $$, 'Self profile created (age 30 in 2026)');
select ok((select self_patient_id is not null from users), 'selfPatientId set');
select is((create_profile('Other Name', 40, 'female', '3001110009')) ->> 'created', 'false', 'calling again changes nothing');
select is((select name from users), 'Ali Khan', 'name unchanged by the second call');

-- ================================================================== second account, same phone
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000c2", "role": "authenticated", "email": "c2@asani.test", "app_metadata": {}}';
select throws_ok($$ select create_profile('Bina', 25, 'female', '+92 300 1110001') $$, 'P0001', 'phone-taken', 'one phone = one app account');
select is((create_profile('Bina', 25, 'female', '3001110002')) ->> 'created', 'true', 'another number works');
select throws_ok($$ select update_phone('3001110001') $$, 'P0001', 'phone-taken', 'cannot switch to a number in use');
select is((update_phone('03001110003')) ->> 'phone', '+923001110003', 'change to a free number');
select is((select phone from patients where relation = 'self'), '+923001110003', 'own profiles get the new phone');

-- a clinic login cannot create a patient account
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000c2", "role": "authenticated", "app_metadata": {"role": "clinic", "clinic_id": "x"}}';
select throws_ok($$ select update_phone('3001110004') $$, 'P0001', 'unauthenticated', 'staff logins cannot use patient functions');

select * from finish();
rollback;
