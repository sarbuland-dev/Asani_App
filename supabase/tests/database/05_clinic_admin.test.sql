-- Phase 6 tests (D-52): clinic queue day, walk-ins + phone lookup (no auto-linking), patient edits, follow-ups,
-- doctors + suggestions, manager PIN, settings, Super Admin (status, links, billing), Link to app account,
-- delete account, service-only functions. Rolled back at the end. Clock: 12:00 PKT Tue 2026-11-24.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
set local asani.test_now = '2026-11-24 07:00:00+00';

select plan(76);

-- ================================================================== data
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000006c1', 'clinic1@asani.test', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000006c2', 'clinic2@asani.test', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000006ad', 'admin@asani.test',   'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000006a1', 'patient@asani.test', 'authenticated', 'authenticated');
insert into public.admin_users (id, email, name) values ('00000000-0000-0000-0000-0000000006ad', 'admin@asani.test', 'Sarbuland');
insert into public.clinics (id, name, city, status, lat, lng) values
  ('k_c1', 'Kay Clinic', 'Lahore', 'active', 31.5, 74.3),
  ('k_c2', 'Second Clinic', 'Lahore', 'active', 31.4, 74.2);
insert into public.clinic_billing (clinic_id, plan, monthly_fee, billing_day) values ('k_c1', 'basic', 3000, 1), ('k_c2', 'basic', 3000, 1);
insert into public.clinic_accounts (id, email, clinic_id, name, status) values
  ('00000000-0000-0000-0000-0000000006c1', 'clinic1@asani.test', 'k_c1', 'Manager', 'invited'),
  ('00000000-0000-0000-0000-0000000006c2', 'clinic2@asani.test', 'k_c2', 'Manager', 'active');
insert into public.doctors (id, clinic_id, name, name_key, speciality, city, token_prefix, schedule) values
  ('k_d1', 'k_c1', 'Dr. Kay', 'kay', 'heart', 'Lahore', 'A',
   '{"mon": {"start": "08:00", "end": "23:00"}, "tue": {"start": "08:00", "end": "23:00"}, "wed": {"start": "08:00", "end": "23:00"}}'),
  ('k_d2', 'k_c2', 'Dr. Two', 'two', 'skin', 'Lahore', 'A', '{}');
insert into public.users (id, email, phone, name) values ('00000000-0000-0000-0000-0000000006a1', 'patient@asani.test', '+923001230001', 'Pari Test');
insert into public.patients (id, phone, owner_uid, name, birth_year, gender, relation, created_by) values
  ('k_p_self', '+923001230001', '00000000-0000-0000-0000-0000000006a1', 'Pari Test', 1990, 'female', 'self', 'app');
update public.users set self_patient_id = 'k_p_self' where id = '00000000-0000-0000-0000-0000000006a1';

-- ================================================================== a patient cannot use clinic functions
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000006a1", "role": "authenticated", "app_metadata": {}}';
select throws_ok($$ select queue_action('start', 'k_d1') $$, 'P0001', 'permission-denied', 'patients cannot run the queue');
-- the patient books #1 from the app
select is((book_token('k_c1', 'k_d1', 'k_p_self', '2026-11-24')) ->> 'number', '1', 'app booking → #1');

-- ================================================================== clinic 1
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000006c1", "role": "authenticated", "app_metadata": {"role": "clinic", "clinic_id": "k_c1"}}';

-- walk-in, new profile with the app account's phone: NOT attached to the account (D-52)
select is((clinic_create_walk_in('k_d1', null, null, '{"phone": "0300 1230001", "name": "Walk Inn", "gender": "male", "relation": "self", "age": 40}')) ->> 'number',
          '2', 'walk-in → #2 (shared numbering)');
select is((select owner_uid::text from patients where name = 'Walk Inn'), null, 'new walk-in profile is not linked by phone (no auto-linking)');
select is((select status from tokens where doctor_id = 'k_d1' and number = 2), 'arrived', 'walk-in token is Arrived');
select throws_ok($$ select clinic_create_walk_in('k_d1', null, null, '{"phone": "12345", "name": "X Y", "gender": "male"}') $$,
                 'P0001', 'invalid-argument', 'bad phone refused');

-- phone lookup (D-22, S-3)
select is(jsonb_array_length((clinic_lookup_phone('3001230001')) -> 'profiles'), 2, 'lookup by full phone finds the app profile and the walk-in');
select is(((clinic_lookup_phone('3001230001')) -> 'profiles' -> 0 ->> 'appAccount'), 'true', 'app account profile listed first, marked appAccount');
select is(((clinic_lookup_phone('3001230001')) -> 'profiles' -> 0 ->> 'atThisClinic'), 'true', 'booked here → atThisClinic');

-- an existing profile from another clinic needs its full phone
select throws_ok($$ select clinic_create_walk_in('k_d1', 'k_p_self', null, null) $$, 'P0001', 'duplicate-token', 'app patient already has a token today');

-- the queue
select throws_ok($$ select queue_action('next', 'k_d1') $$, 'P0001', 'not-started', 'Next before Start');
select lives_ok($$ select queue_action('start', 'k_d1') $$, 'Start');
select throws_ok($$ select queue_action('next', 'k_d1') $$, 'P0001', 'not-arrived', 'D-24: lowest number #1 is Booked → ask first');
select is((queue_action('next', 'k_d1', null, null, (select id from tokens where doctor_id = 'k_d1' and number = 1))) -> 'called' ->> 'label',
          'A-1', 'Call anyway → A-1 called');
-- (read as the owner: the clinic login cannot see these, RLS)
reset role;
select is((select count(*)::integer from notifications where user_id = '00000000-0000-0000-0000-0000000006a1' and title = 'Your turn now'), 1,
          'patient got Your turn now');
set local role authenticated;
select is((queue_action('undo', 'k_d1')) ->> 'ok', 'true', 'Undo last Next within 30 s');
select is((select status || '/' || turn_repeat_used || '/' || (notified ? 'yourTurn') from tokens where doctor_id = 'k_d1' and number = 1),
          'booked/true/false', 'D-38: back to Booked, one more Your turn kept for later');
select throws_ok($$ select queue_action('undo', 'k_d1') $$, 'P0001', 'undo-expired', 'undo only once');

select is((queue_action('next', 'k_d1', null, null, (select id from tokens where doctor_id = 'k_d1' and number = 1))) -> 'called' ->> 'label',
          'A-1', 'A-1 called again');
-- (read as the owner: the clinic login cannot see these, RLS)
reset role;
select is((select count(*)::integer from notifications where user_id = '00000000-0000-0000-0000-0000000006a1' and title = 'Your turn now'), 2,
          'D-38: exactly one more Your turn now');
set local role authenticated;
select lives_ok($$ select queue_action('skip', null, (select id from tokens where doctor_id = 'k_d1' and number = 1)) $$, 'skip A-1');
-- (read as the owner: the clinic login cannot see these, RLS)
reset role;
select is((select count(*)::integer from notifications where user_id = '00000000-0000-0000-0000-0000000006a1' and type = 'skip'), 1,
          'D-34: missed-turn notice');
set local role authenticated;
select is((select turn_repeat_used and not (notified ? 'yourTurn') from tokens where doctor_id = 'k_d1' and number = 1), false,
          'D-35: the repeat was already used, so Your turn stays marked');
select lives_ok($$ select queue_action('arrive', null, (select id from tokens where doctor_id = 'k_d1' and number = 1)) $$, 'A-1 checks in again');
select ok((select priority_at is not null from tokens where doctor_id = 'k_d1' and number = 1), 'D-24: priority after a skip');
select is((queue_action('next', 'k_d1')) -> 'called' ->> 'label', 'A-1', 'Next calls the re-checked-in patient first');
select is((queue_action('next', 'k_d1')) -> 'called' ->> 'label', 'A-2', 'then the walk-in A-2');
select throws_ok($$ select queue_action('cancel', null, (select id from tokens where doctor_id = 'k_d1' and number = 1), 'x') $$,
                 'P0001', 'completed', 'BW-4: completed tokens cannot change');
select throws_ok($$ select queue_action('arrive', null, (select id from tokens where doctor_id = 'k_d2' limit 1)) $$,
                 'P0001', 'not-found', 'other clinic''s token not found');

-- patient edits (D-40), follow-ups
select throws_ok($$ select clinic_update_patient('k_p_self', 'New Name', 'female', 30) $$, 'P0001', 'managed-by-app', 'D-40: app profile is read-only');
select lives_ok($$ select clinic_update_patient((select id from patients where name = 'Walk Inn'), 'Walk Inn Fixed', 'male', 41) $$, 'walk-in name fixed');
select lives_ok($$ select set_follow_up((select id from tokens where doctor_id = 'k_d1' and number = 1), '2026-12-01', 'Review') $$, 'follow-up set');
select lives_ok($$ select set_follow_up((select id from tokens where doctor_id = 'k_d1' and number = 1), '2026-12-05', null) $$, 'set again');
select results_eq($$ select count(*)::integer, max(due_date), max(owner_uid::text) from follow_ups where patient_id = 'k_p_self' $$,
                  $$ values (1, '2026-12-05'::text, '00000000-0000-0000-0000-0000000006a1'::text) $$, 'one pending follow-up, updated, owned');
select throws_ok($$ select set_follow_up((select id from tokens where doctor_id = 'k_d1' and number = 1), '2026-11-24') $$,
                 'P0001', 'invalid-argument', 'follow-up must be after today');

-- doctors, suggestions, PIN
select throws_ok($$ select save_doctor(null, 'Dr. New', 'cardiology', null, null, 10, 40, 7, '{}') $$, 'P0001', 'invalid-argument', 'D-31: fixed speciality list only');
select throws_ok($$ select save_doctor(null, 'Dr. New', 'skin', null, null, 10, 40, 7, '{"mon": {"start": "18:00", "end": "09:00"}}') $$,
                 'P0001', 'invalid-argument', 'end must be after start');
select is((save_doctor(null, 'Dr. Two', 'skin', '12345-p', null, 10, 40, 7, '{"mon": {"start": "09:00", "end": "13:00"}}')) ->> 'tokenPrefix',
          'B', 'new doctor gets the next letter B (no PIN set yet)');
-- (read as the owner: the clinic login cannot see these, RLS)
reset role;
select is((select strength || '/' || status from doctor_link_suggestions where 'k_d2' = any (doctor_ids)), 'weak/open',
          'D-32: same name + speciality at another clinic in the city → weak suggestion');
select is((select pmdc_number from doctor_private where doctor_id = (select id from doctors where clinic_id = 'k_c1' and name = 'Dr. Two')),
          '12345-P', 'PMDC stored normalised, admin-only table');
set local role authenticated;
select is((clinic_set_pin('1234')) ->> 'ok', 'true', 'manager PIN set');
reset role;   -- the PIN table is backend-only; the test reads / ages it as the owner
update clinic_pins set unlocked_until = '2026-11-24 06:59:00+00' where clinic_id = 'k_c1';   -- before the pinned clock
set local role authenticated;
select throws_ok($$ select save_doctor(null, 'Dr. Three', 'eye', null, null, 10, 40, 7, '{}') $$, 'P0001', 'pin-required', 'D-41: adding a doctor needs the PIN');
select is((clinic_verify_pin('0000')) ->> 'code', 'pin-wrong', 'wrong PIN');
reset role;
select is((select failed from clinic_pins where clinic_id = 'k_c1'), 1, 'the wrong try is saved');
set local role authenticated;
select is((clinic_verify_pin('1234')) ->> 'ok', 'true', 'right PIN unlocks');
select is((save_doctor(null, 'Dr. Three', 'eye', null, null, 10, 40, 7, '{}')) ->> 'tokenPrefix', 'C', 'then the doctor is added');
select is((clinic_set_pin('5555', '9999')) ->> 'code', 'pin-wrong', 'changing the PIN needs the current one');
select lives_ok($$ select set_doctor_leave('k_d1', '2026-11-25') $$, 'leave added (no PIN)');
select throws_ok($$ select update_clinic_settings('Addr', 'Area', '042', 'a5', 51.5, -0.1) $$, 'P0001', 'invalid-argument', 'location must be in Pakistan');
select lives_ok($$ select update_clinic_settings('Addr', 'Area', '042', 'a5', 31.5, 74.3) $$, 'settings saved');
select is((select status from clinic_accounts where id = '00000000-0000-0000-0000-0000000006c1'), 'invited', 'still invited before login');
select lives_ok($$ select clinic_login_touch() $$, 'login touch');
select is((select status from clinic_accounts where id = '00000000-0000-0000-0000-0000000006c1'), 'active', 'invite accepted on first login');

-- ================================================================== Link to app account (D-52, S-2): walk-in → same person
select is((link_walk_in_to_account((select id from patients where name = 'Walk Inn Fixed'), '3001230001', 'k_p_self')) ->> 'visitsMoved',
          '1', 'walk-in visits moved to the chosen family member');
select is((select status from patients where name = 'Walk Inn Fixed'), 'merged', 'walk-in profile marked merged');
select is((select count(*)::integer from tokens where patient_id = 'k_p_self'), 2, 'the app profile now has both visits');
select throws_ok($$ select link_walk_in_to_account('k_p_self', '3001230001') $$, 'P0001', 'already-linked', 'an app profile cannot be linked again');

-- ================================================================== Super Admin
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000006ad", "role": "authenticated", "app_metadata": {"role": "superAdmin"}}';
select lives_ok($$ select admin_link_doctors((select id from doctor_link_suggestions where 'k_d2' = any (doctor_ids))) $$, 'link the pair');
select is((select count(distinct doctor_group_id)::integer from doctors where id = 'k_d2' or (clinic_id = 'k_c1' and name = 'Dr. Two')), 1,
          'both records share one group');
select lives_ok($$ select admin_unlink_doctor('k_d2') $$, 'unlink');
select is((select status from doctor_link_suggestions where 'k_d2' = any (doctor_ids)), 'unlinked', 'D-33: unlinked pair is remembered');
select lives_ok($$ select admin_set_clinic_status('k_c1', 'suspended', 'test') $$, 'suspend clinic 1');

-- billing job: invoice on billing day, then overdue → suspended, then payment → active
select ok(jsonb_array_length((admin_run_billing_jobs()) -> 'log') >= 1, 'billing job runs');
select is((select status from invoices where id = 'inv_k_c2_2026-11'), 'unpaid', 'monthly invoice created');
reset role;   -- test setup: make the invoice 23 days late
update invoices set due_date = '2026-11-01' where id = 'inv_k_c2_2026-11';
set local role authenticated;
select lives_ok($$ select admin_run_billing_jobs() $$, 'billing job again (23 days late)');
select is((select status from clinics where id = 'k_c2'), 'suspended', 'unpaid 15+ days → suspended');
select lives_ok($$ select record_payment('inv_k_c2_2026-11', 'bank', 3000, 'TX1') $$, 'payment recorded');
select is((select status from clinics where id = 'k_c2'), 'active', 'paid → active');
select throws_ok($$ select record_payment('inv_k_c2_2026-11', 'bank', 3000) $$, 'P0001', 'invoice-closed', 'a payment is recorded once');

-- the suspended clinic's queue is read-only
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000006c1", "role": "authenticated", "app_metadata": {"role": "clinic", "clinic_id": "k_c1"}}';
select throws_ok($$ select queue_action('pause', 'k_d1') $$, 'P0001', 'suspended', 'suspended clinic: queue is read-only');

-- service-only functions
reset role;
select ok(not has_function_privilege('authenticated', 'public.svc_create_clinic(jsonb, uuid)', 'execute'), 'apps cannot create clinics directly');
select ok(has_function_privilege('service_role', 'public.svc_create_clinic(jsonb, uuid)', 'execute'), 'the Edge Function (service role) can');

-- ================================================================== delete my account (F-10)
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000006a1", "role": "authenticated", "app_metadata": {}}';
select lives_ok($$ select delete_my_account() $$, 'patient deletes the account');
reset role;
select is((select count(*)::integer from auth.users where id = '00000000-0000-0000-0000-0000000006a1'), 0, 'login removed');
select results_eq($$ select name, status, phone from patients where id = 'k_p_self' $$,
                  $$ values ('Deleted user'::text, 'deleted'::text, null::text) $$, 'app profile anonymised');
select is((select count(*)::integer from tokens where patient_id = 'k_p_self' and patient_snapshot ->> 'name' = 'Deleted user'), 2,
          'visit records kept without the name');

select * from finish();
rollback;
