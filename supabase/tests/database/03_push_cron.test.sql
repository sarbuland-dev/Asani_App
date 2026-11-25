-- Phase 3 tests (D-52): follow-up reminders, the push outbox claim/finish API, clean-up and the cron schedules.
-- Rolled back at the end (pg_net requests queued here are rolled back too, so no real push is sent).
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
set local asani.test_now = '2026-11-24 04:00:00+00';   -- 09:00 PKT, Tue 24 Nov

select plan(27);

-- ================================================================== decide_reminder (reminders.test.ts)
select is(private.decide_reminder('pending', '2026-11-25', 0, '2026-11-24', '2026-11-25'), 'tomorrow', 'day before: one reminder');
select is(private.decide_reminder('pending', '2026-11-25', 1, '2026-11-24', '2026-11-25'), null, 'day before: only once');
select is(private.decide_reminder('pending', '2026-11-24', 1, '2026-11-24', '2026-11-25'), 'today', 'due day: until 2 sent');
select is(private.decide_reminder('pending', '2026-11-24', 2, '2026-11-24', '2026-11-25'), null, 'due day: not a third time');
select is(private.decide_reminder('pending', '2026-11-20', 0, '2026-11-24', '2026-11-25'), 'missed', 'past due → missed');
select is(private.decide_reminder('booked', '2026-11-24', 0, '2026-11-24', '2026-11-25'), null, 'booked is left alone');
select is(private.decide_reminder('pending', '2026-12-01', 0, '2026-11-24', '2026-11-25'), null, 'far future waits');

-- ================================================================== test data
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000000f1', 'f1@asani.test', 'authenticated', 'authenticated');
insert into public.users (id, email, phone, name, queue_alerts_enabled) values
  ('00000000-0000-0000-0000-0000000000f1', 'f1@asani.test', '+923000000021', 'Fatima Test', false);
insert into public.clinics (id, name, city) values ('p_c1', 'Push Clinic', 'Lahore');
insert into public.doctors (id, clinic_id, name, token_prefix) values ('p_d1', 'p_c1', 'Dr. Push', 'A');
insert into public.patients (id, phone, owner_uid, name, birth_year, gender, relation, created_by) values
  ('p_mom', '+923000000021', '00000000-0000-0000-0000-0000000000f1', 'Shazia Begum', 1960, 'female', 'mother', 'app');
insert into public.follow_ups (id, clinic_id, doctor_id, patient_id, owner_uid, due_date, reminders_sent) values
  ('p_f_tomorrow', 'p_c1', 'p_d1', 'p_mom', '00000000-0000-0000-0000-0000000000f1', '2026-11-25', 0),
  ('p_f_today',    'p_c1', 'p_d1', 'p_mom', '00000000-0000-0000-0000-0000000000f1', '2026-11-24', 1),
  ('p_f_old',      'p_c1', 'p_d1', 'p_mom', '00000000-0000-0000-0000-0000000000f1', '2026-11-20', 0),
  ('p_f_later',    'p_c1', 'p_d1', 'p_mom', '00000000-0000-0000-0000-0000000000f1', '2026-12-10', 0);
insert into public.devices (user_id, device_id, fcm_token, platform) values
  ('00000000-0000-0000-0000-0000000000f1', 'phone-1', 'tok-good', 'android'),
  ('00000000-0000-0000-0000-0000000000f1', 'phone-2', 'tok-dead', 'android');

-- ================================================================== run the 09:00 job
select is(private.follow_up_reminders(), 3, 'three follow-ups acted on (tomorrow, today, missed)');
select is((select status from follow_ups where id = 'p_f_old'), 'missed', 'past due marked missed');
select is((select reminders_sent from follow_ups where id = 'p_f_tomorrow'), 1, 'tomorrow reminder counted');
select is((select reminders_sent from follow_ups where id = 'p_f_today'), 2, 'today reminder counted');
select results_eq($$ select title, body from notifications where user_id = '00000000-0000-0000-0000-0000000000f1' order by title $$,
                  $$ values ('Follow-up visit today'::text, 'Shazia Begum · Dr. Push. Tap to book your token.'::text),
                            ('Follow-up visit tomorrow'::text, 'Shazia Begum · Dr. Push, Push Clinic. Tap to book.'::text) $$,
                  'reminder copy (DESIGN §8)');
select is((select count(*)::integer from push_outbox where user_id = '00000000-0000-0000-0000-0000000000f1'), 2,
          'follow-up pushes ignore the queue alerts switch');
select is((select data ->> 'route' from push_outbox where data ->> 'followUpId' = 'p_f_tomorrow'),
          '/book/p_c1/p_d1?patient=p_mom&date=2026-11-25', 'tap opens booking pre-filled');
select is(private.follow_up_reminders(), 0, 'running again sends nothing');

-- ================================================================== outbox API (as send-push would call it)
create temp table claimed on commit drop as select * from claim_push_batch(50);
select is((select count(*)::integer from claimed where user_id = '00000000-0000-0000-0000-0000000000f1'), 2,
          'send-push claims the 2 waiting pushes');
select is((select jsonb_array_length(devices) from claimed limit 1), 2, 'each claimed push carries the account''s devices');
select is((select count(*)::integer from claim_push_batch(50) where user_id = '00000000-0000-0000-0000-0000000000f1'), 0,
          'a claimed row is not handed out twice');

select lives_ok($$ select finish_push((select min(id) from claimed), null, array['tok-dead']) $$, 'first push done, dead token reported');
select lives_ok($$ select finish_push((select max(id) from claimed), 'fcm 503', '{}') $$, 'second push failed');
select is((select array_agg(fcm_token) from devices where user_id = '00000000-0000-0000-0000-0000000000f1'), array['tok-good'],
          'the dead device token is deleted');
select ok((select sent_at is not null from push_outbox where id = (select min(id) from claimed)), 'done row has sent_at');
select ok((select sent_at is null and claimed_at is null and last_error = 'fcm 503' from push_outbox where id = (select max(id) from claimed)),
          'failed row is released for a retry');

-- only the service role (send-push) may use the outbox API; the apps never can
select ok(has_function_privilege('service_role', 'public.claim_push_batch(integer)', 'execute'), 'service role may claim');
select ok(not has_function_privilege('authenticated', 'public.claim_push_batch(integer)', 'execute'), 'signed-in users may not claim');
select ok(not has_function_privilege('anon', 'public.finish_push(bigint, text, text[])', 'execute'), 'anonymous may not finish');

-- ================================================================== schedules
select is((select array_agg(jobname || ' ' || schedule order by jobname) from cron.job where jobname like 'asani-%'),
          array['asani-auto-close-tokens 0 22 * * *', 'asani-billing-jobs 0 1 * * *', 'asani-cleanup 0 23 * * *',
                'asani-follow-up-reminders 0 4 * * *', 'asani-retry-push * * * * *'],
          'cron jobs at 03:00, 04:00, 06:00 (billing, phase 6) and 09:00 PKT plus the retry');

select * from finish();
rollback;
