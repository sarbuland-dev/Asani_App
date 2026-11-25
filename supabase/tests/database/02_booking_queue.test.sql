-- Phase 2 tests (D-52): booking rules, book/cancel, queue notification steps, skip/cancel notices, alerts switch,
-- auto-close. Ports functions/src/booking/rules.test.ts, queue/steps.test.ts, cancelNotice/skipNotice/autoClose tests.
-- Rolled back at the end. Time is pinned with asani.test_now (12:00 PKT on Tue 2026-11-24).
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
set local asani.test_now = '2026-11-24 07:00:00+00';   -- 12:00 PKT

select plan(59);

-- ================================================================== pure rules
select is(private.pkt_today(), '2026-11-24', 'PKT date from the pinned clock');
select is(private.pkt_minutes(), 720, 'PKT minutes (12:00)');
select is(private.weekday_key('2026-11-24'), 'tue', 'weekday key');

-- next_step (steps.test.ts)
select is((private.next_step('booked', 3, '{}')).send, 'ahead3', 'N-2: 3 ahead → ahead3');
select is((private.next_step('booked', 2, '{"ahead3": 1}')).mark, array['ahead2'], 'N-2: 2 ahead marks ahead2 only');
select is((private.next_step('arrived', 1, '{"ahead3": 1, "ahead2": 1}')).send, 'ahead1', 'arrived 1 ahead → ahead1');
select is((private.next_step('called', 0, '{"ahead3": 1, "ahead2": 1, "ahead1": 1}')).send, 'yourTurn', 'called → yourTurn');
select is((private.next_step('booked', 2, '{"ahead3": 1, "ahead2": 1}')).send, null, 'never the same step twice');
select is((private.next_step('booked', 1, '{}')).mark, array['ahead3', 'ahead2', 'ahead1'], 'N-3: a jump marks the skipped steps');
select is((private.next_step('called', 0, '{"ahead3": 1}')).mark, array['ahead2', 'ahead1', 'yourTurn'], 'N-3: jump to called');
select is((private.next_step('booked', 4, '{}')).send, null, 'nothing at 4+ ahead');
select is((private.next_step('booked', 0, '{}')).send, null, 'nothing at 0 ahead when nobody is with the doctor');
select is((private.next_step('onHold', 2, '{}')).send, null, 'nothing while on hold');
select is((private.next_step('cancelled', 1, '{}')).send, null, 'nothing for a cancelled token');
select is((private.next_step('booked', 0, '{}', true)).send, 'ahead1', 'D-39: 0 ahead + someone with the doctor → You''re next');
select is((private.next_step('booked', 0, '{"ahead1": 1}', true)).send, null, 'D-39: only once');
select is((private.step_message('ahead1', 'A-11', 'Dr. Ayesha Malik')).body, 'Token A-11 · Please be at the reception.', 'copy: ahead1');
select is((private.step_message('yourTurn', 'A-11', 'Dr. Ayesha Malik')).body, 'Token A-11 · Please go to Dr. Ayesha Malik.', 'copy: your turn');

-- ================================================================== test data
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000000a1', 'a1@asani.test', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000b1', 'b1@asani.test', 'authenticated', 'authenticated');
insert into public.users (id, email, phone, name) values
  ('00000000-0000-0000-0000-0000000000a1', 'a1@asani.test', '+923000000011', 'Ali Test'),
  ('00000000-0000-0000-0000-0000000000b1', 'b1@asani.test', '+923000000012', 'Bina Test');

insert into public.clinics (id, name, city, status) values
  ('q_c1', 'Queue Clinic', 'Lahore', 'active'),
  ('q_c2', 'Closed Clinic', 'Lahore', 'suspended');
insert into public.doctors (id, clinic_id, name, token_prefix, max_tokens_per_day, schedule, on_leave_dates) values
  ('q_d1', 'q_c1', 'Dr. Queue', 'A', 40,
   '{"mon": {"start": "08:00", "end": "23:00"}, "tue": {"start": "08:00", "end": "23:00"}, "wed": {"start": "08:00", "end": "23:00"}}', '{2026-11-25}'),
  ('q_d2', 'q_c1', 'Dr. Small', 'B', 1, '{"tue": {"start": "08:00", "end": "11:00"}, "wed": {"start": "08:00", "end": "23:00"}}', '{}'),
  ('q_d3', 'q_c2', 'Dr. Away', 'A', 40, '{"tue": {"start": "08:00", "end": "23:00"}}', '{}');

insert into public.patients (id, phone, owner_uid, name, birth_year, gender, relation, created_by) values
  ('q_a_self', '+923000000011', '00000000-0000-0000-0000-0000000000a1', 'Ali Test',   1990, 'male',   'self',   'app'),
  ('q_a_mom',  '+923000000011', '00000000-0000-0000-0000-0000000000a1', 'Ali Mother', 1960, 'female', 'mother', 'app'),
  ('q_a_son',  '+923000000011', '00000000-0000-0000-0000-0000000000a1', 'Ali Son',    2018, 'male',   'son',    'app'),
  ('q_a_wife', '+923000000011', '00000000-0000-0000-0000-0000000000a1', 'Ali Wife',   1992, 'female', 'spouse', 'app'),
  ('q_b_self', '+923000000012', '00000000-0000-0000-0000-0000000000b1', 'Bina Test',  1985, 'female', 'self',   'app');

insert into public.follow_ups (id, clinic_id, doctor_id, patient_id, owner_uid, due_date)
values ('q_f1', 'q_c1', 'q_d1', 'q_a_mom', '00000000-0000-0000-0000-0000000000a1', '2026-11-26');

-- ================================================================== booking as patient A
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000a1", "role": "authenticated", "app_metadata": {}}';

select is((book_token('q_c1', 'q_d1', 'q_a_self', '2026-11-24')) ->> 'number', '1', 'first booking gets number 1');
select is((book_token('q_c1', 'q_d1', 'q_a_mom', '2026-11-24')) ->> 'number', '2', 'second booking gets number 2');
select is((select source from tokens where patient_id = 'q_a_mom'), 'followUp', 'D-20: booking with a pending follow-up → source followUp');
select is((select status from follow_ups where id = 'q_f1'), 'booked', 'D-20: the follow-up is marked booked');
select is((select clinic_ids from patients where id = 'q_a_self'), array['q_c1'], 'BW-6: clinic added to the patient');

select throws_ok($$ select book_token('q_c1', 'q_d1', 'q_a_self', '2026-11-24') $$, 'P0001', 'duplicate-token', 'BR-5: one active token per profile');
select throws_ok($$ select book_token('q_c2', 'q_d3', 'q_a_son', '2026-11-24') $$, 'P0001', 'clinic-unavailable', 'BR-1: suspended clinic');
select throws_ok($$ select book_token('q_c1', 'q_d1', 'q_a_son', '2026-11-25') $$, 'P0001', 'doctor-unavailable', 'BR-2: doctor on leave');
select throws_ok($$ select book_token('q_c1', 'q_d1', 'q_a_son', '2026-11-27') $$, 'P0001', 'doctor-unavailable', 'BR-2: no schedule that day');
select throws_ok($$ select book_token('q_c1', 'q_d1', 'q_a_son', '2026-12-05') $$, 'P0001', 'doctor-unavailable', 'outside the booking window');
select throws_ok($$ select book_token('q_c1', 'q_d1', 'q_a_son', '2026-11-23') $$, 'P0001', 'doctor-unavailable', 'a past date');
select throws_ok($$ select book_token('q_c1', 'q_d2', 'q_a_son', '2026-11-24') $$, 'P0001', 'session-ended', 'BR-3: today after the session end');
select is((book_token('q_c1', 'q_d2', 'q_a_son', '2026-11-25')) ->> 'number', '1', 'tomorrow is still open');
select throws_ok($$ select book_token('q_c1', 'q_d2', 'q_a_wife', '2026-11-25') $$, 'P0001', 'tokens-full', 'BR-4: max tokens per day');
select throws_ok($$ select book_token('q_c1', 'q_d1', 'q_b_self', '2026-11-24') $$, 'P0001', 'permission-denied', 'cannot book for another family');

-- ================================================================== patient B books → numbers keep counting
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000b1", "role": "authenticated", "app_metadata": {}}';
select is((book_token('q_c1', 'q_d1', 'q_b_self', '2026-11-24')) ->> 'number', '3', 'another account gets the next number');

set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000a1", "role": "authenticated", "app_metadata": {}}';
select is((book_token('q_c1', 'q_d1', 'q_a_son', '2026-11-24')) ->> 'number', '4', 'number 4');

-- a clinic login cannot book through the patient function
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000a1", "role": "authenticated", "app_metadata": {"role": "clinic", "clinic_id": "q_c1"}}';
select throws_ok($$ select book_token('q_c1', 'q_d1', 'q_a_wife', '2026-11-24') $$, 'P0001', 'unauthenticated', 'clinic login cannot use book_token');

-- ================================================================== queue state + notifications on booking (N-4)
reset role;
select is((select active_numbers from queue_days where doctor_id = 'q_d1' and date = '2026-11-24'), array[1, 2, 3, 4], 'active numbers 1..4');
select is((select last_token_number from queue_days where doctor_id = 'q_d1' and date = '2026-11-24'), 4, 'last token number 4');
select is((select notified ? 'ahead1' from tokens where doctor_id = 'q_d1' and number = 2), true, '#2 (1 ahead) got You''re next at booking');
select is((select notified ? 'ahead2' and notified ? 'ahead3' from tokens where doctor_id = 'q_d1' and number = 3), true, '#3 got ahead2 and marked ahead3');
select is((select count(*)::integer from notifications where user_id = '00000000-0000-0000-0000-0000000000a1' and type = 'queue'), 2,
          'A has 2 queue entries (#2 ahead1, #4 ahead3)');
select is((select app from clinic_stats where clinic_id = 'q_c1' and month = '2026-11'), 5, 'monthly app bookings counted');

-- alerts switch (D-18): B turns queue alerts off → inbox yes, push no
update users set queue_alerts_enabled = false where id = '00000000-0000-0000-0000-0000000000b1';
select is((select count(*)::integer from push_outbox where user_id = '00000000-0000-0000-0000-0000000000b1'), 1,
          'B''s booking push was queued while alerts were on');

-- ================================================================== the clinic calls #1 (as the backend)
update queue_days set session_status = 'running', current_token = 1 where doctor_id = 'q_d1' and date = '2026-11-24';
update tokens set status = 'called', called_at = now() where doctor_id = 'q_d1' and date = '2026-11-24' and number = 1;

select is((select notified ? 'yourTurn' from tokens where doctor_id = 'q_d1' and number = 1), true, '#1 called → Your turn now');
select is((select notified ? 'ahead1' from tokens where doctor_id = 'q_d1' and number = 3), true, '#3 now 1 ahead → You''re next');
select is((select count(*)::integer from notifications where user_id = '00000000-0000-0000-0000-0000000000b1'), 2,
          'B (alerts off) still gets the inbox entry (D-45)');
select is((select count(*)::integer from push_outbox where user_id = '00000000-0000-0000-0000-0000000000b1'), 1,
          'B (alerts off) gets no new push');
select is((select count(*)::integer from push_outbox where user_id = '00000000-0000-0000-0000-0000000000a1'
            and data ->> 'step' = 'yourTurn'), 1, 'one Your turn push queued for A');

-- running the evaluation again sends nothing new
select is(private.evaluate_queue('q_d1', '2026-11-24'), 0, 'evaluate_queue is idempotent');

-- ================================================================== cancel
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000a1", "role": "authenticated", "app_metadata": {}}';
select throws_ok($$ select cancel_token((select id from tokens where doctor_id = 'q_d1' and number = 1)) $$,
                 'P0001', 'cannot-cancel', 'a called token cannot be cancelled');
select throws_ok($$ select cancel_token((select id from tokens where doctor_id = 'q_d1' and number = 3)) $$,
                 'P0001', 'not-found', 'cannot cancel another account''s token');
select lives_ok($$ select cancel_token((select id from tokens where doctor_id = 'q_d1' and number = 2)) $$, 'A cancels #2');
select lives_ok($$ select cancel_token((select id from tokens where doctor_id = 'q_d1' and number = 2)) $$, 'cancelling twice is safe');
reset role;
select is((select active_numbers from queue_days where doctor_id = 'q_d1' and date = '2026-11-24'), array[3, 4], 'cancelled number left the queue');

-- ================================================================== skip (D-34) and clinic cancel (D-23) notices
update tokens set status = 'skipped' where doctor_id = 'q_d1' and number = 4;
update tokens set status = 'arrived' where doctor_id = 'q_d1' and number = 4;
update tokens set status = 'skipped' where doctor_id = 'q_d1' and number = 4;
select is((select count(*)::integer from notifications where user_id = '00000000-0000-0000-0000-0000000000a1' and type = 'skip'), 1,
          'skip push sent once per token');

update tokens set status = 'cancelled', cancelled_by = 'clinic', cancel_reason = 'Doctor on leave.'
 where doctor_id = 'q_d1' and number = 3;
select results_eq($$ select title, body from notifications where user_id = '00000000-0000-0000-0000-0000000000b1' and type = 'cancel' $$,
                  $$ values ('Token A-3 cancelled by Queue Clinic'::text, 'Doctor on leave. Tap to book another day.'::text) $$,
                  'clinic cancel notice copy');

-- ================================================================== auto-close (D-21), the next day
set local asani.test_now = '2026-11-25 22:00:00+00';   -- 03:00 PKT on 26 Nov
select is(private.auto_close_tokens(), 2, 'two old open tokens closed (#1 called on the 24th, Dr. Small booked on the 25th)');
select is((select status from tokens where doctor_id = 'q_d1' and number = 1), 'completed', 'called → completed');
select is((select status || '/' || auto_closed from tokens where doctor_id = 'q_d2' and number = 1), 'noShow/true', 'booked → noShow, autoClosed');

select * from finish();
rollback;
