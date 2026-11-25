-- Phase 2 (D-52): booking, cancelling, the live queue and its notifications, in Postgres.
-- Ports functions/src/booking/{bookToken,cancelToken,rules}.ts, queue/{steps,notify,triggers,skipNotice,cancelNotice,autoClose}.ts
-- and lib/{dates,inbox}.ts. Same rules and copy; see PRD F-04, F-06, D-21, D-23, D-34, D-39, D-45.
--
-- Errors: `raise exception` with the message = a stable code the apps map to text
-- (unauthenticated, invalid-argument, not-found, permission-denied, clinic-unavailable, doctor-unavailable,
-- session-ended, tokens-full, duplicate-token, too-many-active, cannot-cancel). Extra data goes in DETAIL as JSON.
--
-- Locking rule: anything that changes a token's status first locks its queue day row
-- (`select … for update` on queue_days). Two bookings on one doctor/day therefore run one after the other,
-- and the unique (doctor_id, date, number) index is a second guard against duplicate numbers.

-- ================================================================ time (Asia/Karachi, ARCHITECTURE §7)

-- Now in UTC. Tests (a direct database session, never the API) may pin it with: set asani.test_now = '…'.
create or replace function private.now_utc() returns timestamptz
language plpgsql stable as $$
declare v text := current_setting('asani.test_now', true);
begin
  if v is not null and v <> '' and session_user = 'postgres' then
    return v::timestamptz;
  end if;
  return now();
end $$;

create or replace function private.pkt_today() returns text
language sql stable as $$ select to_char(private.now_utc() at time zone 'Asia/Karachi', 'YYYY-MM-DD') $$;

create or replace function private.pkt_minutes() returns integer
language sql stable as $$
  select (extract(hour from private.now_utc() at time zone 'Asia/Karachi') * 60
        + extract(minute from private.now_utc() at time zone 'Asia/Karachi'))::integer $$;

create or replace function private.weekday_key(p_date text) returns text
language sql immutable as $$
  select (array['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'])[extract(isodow from p_date::date)::integer] $$;

create or replace function private.hhmm_minutes(p_hhmm text) returns integer
language sql immutable as $$ select split_part(p_hhmm, ':', 1)::integer * 60 + split_part(p_hhmm, ':', 2)::integer $$;

create or replace function private.token_label(p_prefix text, p_number integer) returns text
language sql immutable as $$ select coalesce(nullif(p_prefix, ''), 'A') || '-' || p_number $$;

-- ================================================================ booking rules (rules.ts)

-- BR-1..BR-4 for one doctor and date. Returns the error code, or null when booking is allowed.
create or replace function private.booking_block(
  p_clinic_status text, p_doctor public.doctors, p_date text,
  p_session_status text, p_booked_count integer, p_today text, p_now_minutes integer
) returns text
language plpgsql immutable as $$
declare
  v_offset integer := p_date::date - p_today::date;
  v_sched  jsonb   := p_doctor.schedule -> private.weekday_key(p_date);
begin
  if p_clinic_status not in ('pilot', 'active', 'grace') then return 'clinic-unavailable'; end if;
  -- Only today .. today + bookingWindowDays - 1 (PRD F-04 step 2).
  if v_offset < 0 or v_offset >= p_doctor.booking_window_days then return 'doctor-unavailable'; end if;
  if not p_doctor.active then return 'doctor-unavailable'; end if;
  if p_date = any (p_doctor.on_leave_dates) then return 'doctor-unavailable'; end if;
  if v_sched is null or jsonb_typeof(v_sched) <> 'object' then return 'doctor-unavailable'; end if;
  if coalesce(p_booked_count, 0) >= p_doctor.max_tokens_per_day then return 'tokens-full'; end if;
  if v_offset = 0 and (p_session_status = 'ended' or p_now_minutes >= private.hhmm_minutes(v_sched ->> 'end')) then
    return 'session-ended';
  end if;
  return null;
end $$;

-- ================================================================ queue steps (steps.ts)

-- The step to send now and every step to mark (the sent one plus skipped earlier ones, N-3), or null.
-- D-39: 0 ahead while someone is with the doctor → "You're next" (ahead1).
create or replace function private.next_step(
  p_status text, p_ahead integer, p_notified jsonb, p_someone_with_doctor boolean default false,
  out send text, out mark text[]
)
language plpgsql immutable as $$
declare
  v_keys text[] := array['ahead3', 'ahead2', 'ahead1', 'yourTurn'];
  v_current text;
  v_idx integer;
begin
  if p_status = 'called' then
    v_current := 'yourTurn';
  elsif p_status in ('booked', 'arrived') and p_ahead between 1 and 3 then
    v_current := 'ahead' || p_ahead;
  elsif p_status in ('booked', 'arrived') and p_ahead = 0 and p_someone_with_doctor then
    v_current := 'ahead1';
  end if;
  if v_current is null or coalesce(p_notified, '{}') ? v_current then
    send := null; mark := null;
    return;
  end if;
  v_idx := array_position(v_keys, v_current);
  send := v_current;
  select coalesce(array_agg(k order by i), '{}') into mark
  from unnest(v_keys[1:v_idx]) with ordinality as x(k, i)
  where not (coalesce(p_notified, '{}') ? k);
end $$;

-- DESIGN.md §8 copy (D-13 token labels).
create or replace function private.step_message(p_step text, p_label text, p_doctor text, out title text, out body text)
language sql immutable as $$
  select case p_step
           when 'ahead3' then '3 patients ahead of you'
           when 'ahead2' then '2 patients ahead of you'
           when 'ahead1' then 'You''re next'
           else 'Your turn now' end,
         case p_step
           when 'ahead3' then 'Token ' || p_label || ' · ' || p_doctor || '. Please start heading to the clinic.'
           when 'ahead2' then 'Token ' || p_label || ' · ' || p_doctor
           when 'ahead1' then 'Token ' || p_label || ' · Please be at the reception.'
           else 'Token ' || p_label || ' · Please go to ' || p_doctor || '.' end
$$;

-- ================================================================ inbox + push outbox (inbox.ts, D-45)

-- Saves the entry to the in-app list (always, D-45) and queues the push for send-push (phase 3).
-- Queue alerts respect the account switch (D-18); cancel / skip / follow-up notices do not.
create or replace function private.notify_user(
  p_uid uuid, p_type text, p_title text, p_body text, p_route text, p_token_id text,
  p_data jsonb, p_respect_alerts boolean
) returns void
language plpgsql security definer set search_path = '' as $$
declare v_alerts boolean;
begin
  if p_uid is null then return; end if;
  select u.queue_alerts_enabled into v_alerts from public.users u where u.id = p_uid;
  if not found then return; end if;                -- account deleted
  insert into public.notifications (user_id, type, title, body, route, token_id, created_at, expire_at)
  values (p_uid, p_type, p_title, p_body, p_route, p_token_id, private.now_utc(), private.now_utc() + interval '30 days');
  if p_respect_alerts and not v_alerts then return; end if;
  insert into public.push_outbox (user_id, title, body, data)
  values (p_uid, p_title, p_body, coalesce(p_data, '{}') || jsonb_build_object('type', p_type, 'route', p_route)
                                   || case when p_token_id is null then '{}'::jsonb else jsonb_build_object('tokenId', p_token_id) end);
end $$;

-- ================================================================ evaluate the queue (notify.ts)

-- After any queue change, give each token the one step that now applies. Idempotent: `notified` is set in the
-- same transaction as the inbox row and the outbox row, so a step is never queued twice.
create or replace function private.evaluate_queue(p_doctor_id text, p_date text) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_active  integer[];
  v_doctor  text;
  v_with    boolean;
  v_now     timestamptz := private.now_utc();
  v_sent    integer := 0;
  t         record;
  s         record;
  m         record;
begin
  select d.active_numbers into v_active from public.queue_days d where d.doctor_id = p_doctor_id and d.date = p_date;
  if not found then return 0; end if;
  select coalesce(doc.name, 'the doctor') into v_doctor from public.doctors doc where doc.id = p_doctor_id;
  select exists (select 1 from public.tokens x where x.doctor_id = p_doctor_id and x.date = p_date and x.status = 'called')
    into v_with;

  for t in
    select * from public.tokens x
    where x.doctor_id = p_doctor_id and x.date = p_date and x.status in ('booked', 'arrived', 'called')
    order by x.number
    for update
  loop
    select * into s from private.next_step(
      t.status, (select count(*)::integer from unnest(v_active) n where n < t.number), t.notified, v_with);
    if s.send is null then continue; end if;

    update public.tokens x
       set notified = x.notified || (select jsonb_object_agg(k, to_jsonb(v_now)) from unnest(s.mark) k)
     where x.id = t.id;

    select * into m from private.step_message(s.send, private.token_label(t.token_prefix, t.number), v_doctor);
    -- Walk-ins have no booker; the profile's app account gets the alerts (D-22).
    perform private.notify_user(coalesce(t.booked_by_user_id, t.patient_owner_uid), 'queue', m.title, m.body,
                                '/token/' || t.id, t.id, jsonb_build_object('step', s.send), true);
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end $$;

-- ================================================================ skip / clinic cancel notices (D-34, D-23)

create or replace function private.notify_skipped(p_token_id text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare t public.tokens;
begin
  -- Claim first: sent at most once per token.
  update public.tokens x set skip_notified_at = private.now_utc()
   where x.id = p_token_id and x.status = 'skipped' and x.skip_notified_at is null
  returning * into t;
  if not found then return false; end if;
  perform private.notify_user(coalesce(t.booked_by_user_id, t.patient_owner_uid), 'skip', 'You missed your turn',
                              'Token ' || private.token_label(t.token_prefix, t.number) || ' · Go to reception to be called next.',
                              '/token/' || t.id, t.id, '{}', false);
  return true;
end $$;

create or replace function private.notify_clinic_cancel(p_token_id text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  t        public.tokens;
  v_clinic text;
  v_reason text;
  v_route  text;
begin
  update public.tokens x set cancel_notified_at = private.now_utc()
   where x.id = p_token_id and x.status = 'cancelled' and x.cancelled_by = 'clinic' and x.cancel_notified_at is null
  returning * into t;
  if not found then return false; end if;
  select coalesce(c.name, 'the clinic') into v_clinic from public.clinics c where c.id = t.clinic_id;
  v_reason := regexp_replace(btrim(coalesce(t.cancel_reason, '')), '[.\s]+$', '');
  v_route := '/book/' || t.clinic_id || '/' || t.doctor_id || '?patient=' || t.patient_id;
  perform private.notify_user(coalesce(t.booked_by_user_id, t.patient_owner_uid), 'cancel',
                              'Token ' || private.token_label(t.token_prefix, t.number) || ' cancelled by ' || v_clinic,
                              case when v_reason = '' then 'Tap to book another day.'
                                   else v_reason || '. Tap to book another day.' end,
                              v_route, t.id, '{}', false);
  return true;
end $$;

-- ================================================================ triggers (triggers.ts)

-- Recompute day.active_numbers (booked / arrived / onHold, sorted). If the list changed, the queue day trigger
-- re-evaluates the queue; if not (e.g. a Skipped token is recalled), evaluate here.
create or replace function private.refresh_queue_day(p_doctor_id text, p_date text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_numbers integer[];
begin
  select coalesce(array_agg(x.number order by x.number), '{}') into v_numbers
  from public.tokens x
  where x.doctor_id = p_doctor_id and x.date = p_date and x.status in ('booked', 'arrived', 'onHold');

  update public.queue_days d
     set active_numbers = v_numbers, waiting_count = cardinality(v_numbers)
   where d.doctor_id = p_doctor_id and d.date = p_date and d.active_numbers is distinct from v_numbers;
  if not found then
    perform private.evaluate_queue(p_doctor_id, p_date);
  end if;
end $$;

create or replace function private.on_token_status() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and old.status is not distinct from new.status then
    return null;
  end if;
  perform private.refresh_queue_day(new.doctor_id, new.date);
  if tg_op = 'UPDATE' and new.status = 'skipped' then
    perform private.notify_skipped(new.id);
  elsif tg_op = 'UPDATE' and new.status = 'cancelled' and new.cancelled_by = 'clinic' then
    perform private.notify_clinic_cancel(new.id);
  end if;
  return null;
end $$;

create trigger on_token_status after insert or update of status on public.tokens
  for each row execute function private.on_token_status();

create or replace function private.on_queue_day_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform private.evaluate_queue(new.doctor_id, new.date);
  return null;
end $$;

create trigger on_queue_day_change after update on public.queue_days
  for each row
  when (old.active_numbers is distinct from new.active_numbers
        or old.current_token is distinct from new.current_token
        or old.session_status is distinct from new.session_status)
  execute function private.on_queue_day_change();

-- ================================================================ book_token (bookToken.ts, PRD F-04)

create or replace function public.book_token(p_clinic_id text, p_doctor_id text, p_patient_id text, p_date text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid       uuid := auth.uid();
  v_clinic    public.clinics;
  v_doctor    public.doctors;
  v_patient   public.patients;
  v_day       public.queue_days;
  v_block     text;
  v_dup       public.tokens;
  v_followup  text;
  v_number    integer;
  v_token_id  text := gen_random_uuid()::text;
  v_now       timestamptz := private.now_utc();
begin
  if v_uid is null or not private.is_patient() then
    raise exception 'unauthenticated' using hint = 'Please log in again.';
  end if;
  if p_clinic_id is null or p_doctor_id is null or p_patient_id is null or p_date is null
     or p_date !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'invalid-argument' using hint = 'clinic, doctor, patient and date (yyyy-MM-dd) are required.';
  end if;

  select * into v_clinic from public.clinics where id = p_clinic_id;
  select * into v_doctor from public.doctors where id = p_doctor_id;
  if v_clinic.id is null or v_doctor.id is null then
    raise exception 'not-found' using hint = 'Clinic or doctor not found.';
  end if;
  if v_doctor.clinic_id <> p_clinic_id then
    raise exception 'invalid-argument' using hint = 'This doctor is not at this clinic.';
  end if;

  select * into v_patient from public.patients where id = p_patient_id;
  if v_patient.id is null or v_patient.owner_uid is distinct from v_uid or v_patient.status <> 'active' then
    raise exception 'permission-denied' using hint = 'You can only book for your own family profiles.';
  end if;

  -- Lock the queue day (create it on the first booking).
  insert into public.queue_days (doctor_id, date, clinic_id) values (p_doctor_id, p_date, p_clinic_id)
  on conflict (doctor_id, date) do nothing;
  select * into v_day from public.queue_days where doctor_id = p_doctor_id and date = p_date for update;

  -- BR-1..BR-4
  v_block := private.booking_block(v_clinic.status, v_doctor, p_date, v_day.session_status, v_day.booked_count,
                                   private.pkt_today(), private.pkt_minutes());
  if v_block is not null then
    raise exception '%', v_block;
  end if;

  -- BR-5: one active token per profile per doctor per day.
  select * into v_dup from public.tokens
   where patient_id = p_patient_id and doctor_id = p_doctor_id and date = p_date
     and status in ('booked', 'arrived', 'called', 'onHold')
   limit 1;
  if v_dup.id is not null then
    raise exception 'duplicate-token'
      using detail = jsonb_build_object('name', v_patient.name,
                                        'label', private.token_label(v_dup.token_prefix, v_dup.number))::text;
  end if;

  -- BR-6: max 5 active tokens per account.
  if (select count(*) from public.tokens
       where booked_by_user_id = v_uid and status in ('booked', 'arrived', 'called', 'onHold')) >= 5 then
    raise exception 'too-many-active';
  end if;

  -- PRD F-09: booking with this doctor fulfils the patient's pending follow-up (D-20).
  select f.id into v_followup from public.follow_ups f
   where f.patient_id = p_patient_id and f.doctor_id = p_doctor_id and f.status = 'pending'
   order by f.due_date
   limit 1
   for update;

  -- BR-7: sequential per doctor per day.
  v_number := v_day.last_token_number + 1;
  update public.queue_days
     set last_token_number = v_number, booked_count = booked_count + 1
   where doctor_id = p_doctor_id and date = p_date;

  insert into public.tokens (id, clinic_id, doctor_id, date, number, token_prefix, patient_id, patient_snapshot,
                             booked_by_user_id, patient_owner_uid, source, status, follow_up_id, created_at)
  values (v_token_id, p_clinic_id, p_doctor_id, p_date, v_number, coalesce(v_doctor.token_prefix, 'A'), p_patient_id,
          jsonb_build_object('name', v_patient.name, 'birthYear', v_patient.birth_year, 'gender', v_patient.gender,
                             'relation', v_patient.relation, 'phone', v_patient.phone),
          v_uid, v_patient.owner_uid, case when v_followup is null then 'app' else 'followUp' end, 'booked',
          v_followup, v_now);

  if v_followup is not null then
    update public.follow_ups set status = 'booked', booked_token_id = v_token_id where id = v_followup;
  end if;

  -- The clinic can now find this patient (BW-6); monthly counters for the dashboard.
  update public.patients set clinic_ids = array_append(clinic_ids, p_clinic_id)
   where id = p_patient_id and not (p_clinic_id = any (clinic_ids));
  insert into public.clinic_stats (clinic_id, month, app, tokens) values (p_clinic_id, left(p_date, 7), 1, 1)
  on conflict (clinic_id, month) do update set app = public.clinic_stats.app + 1, tokens = public.clinic_stats.tokens + 1;

  return jsonb_build_object('tokenId', v_token_id, 'number', v_number);
end $$;

-- ================================================================ cancel_token (cancelToken.ts, PRD F-05)

create or replace function public.cancel_token(p_token_id text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  t     public.tokens;
begin
  if v_uid is null or not private.is_patient() then
    raise exception 'unauthenticated' using hint = 'Please log in again.';
  end if;
  select * into t from public.tokens where id = p_token_id;
  if t.id is null or t.booked_by_user_id is distinct from v_uid then
    raise exception 'not-found' using hint = 'Token not found.';
  end if;

  perform 1 from public.queue_days where doctor_id = t.doctor_id and date = t.date for update;
  select * into t from public.tokens where id = p_token_id for update;

  if t.status = 'cancelled' then
    return jsonb_build_object('ok', true);          -- cancelling twice is safe
  end if;
  if t.status not in ('booked', 'arrived') then
    raise exception 'cannot-cancel' using hint = 'This token can no longer be cancelled.';
  end if;

  update public.tokens
     set status = 'cancelled', cancelled_at = private.now_utc(), cancelled_by = 'patient'
   where id = p_token_id;
  return jsonb_build_object('ok', true);
end $$;

-- ================================================================ auto-close old tokens (autoClose.ts, D-21)

-- Tokens from BEFORE today (PKT) that are still open: Booked → noShow; Arrived / On hold / Called → completed.
-- Scheduled at 03:00 PKT by pg_cron (phase 3). Safe to run again.
create or replace function private.auto_close_tokens() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_today text := private.pkt_today();
  v_now   timestamptz := private.now_utc();
  v_count integer;
begin
  -- Lock the affected queue days first, in a fixed order (see the locking rule above).
  perform 1 from public.queue_days d
   where (d.doctor_id, d.date) in (select x.doctor_id, x.date from public.tokens x
                                    where x.date < v_today and x.status in ('booked', 'arrived', 'onHold', 'called'))
   order by d.doctor_id, d.date
   for update;

  update public.tokens x
     set status       = case when x.status = 'booked' then 'noShow' else 'completed' end,
         auto_closed  = true,
         completed_at = case when x.status = 'booked' then x.completed_at else coalesce(x.completed_at, v_now) end,
         history      = x.history || jsonb_build_array(jsonb_build_object(
                          'action', case when x.status = 'booked' then 'Auto-closed · No-show' else 'Auto-closed · Completed' end,
                          'by', 'System', 'at', v_now))
   where x.date < v_today and x.status in ('booked', 'arrived', 'onHold', 'called');
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- ================================================================ who may call what
revoke execute on all functions in schema private from public, anon;
grant execute on function private.jwt_role(), private.jwt_clinic(), private.is_super_admin(), private.is_clinic(),
  private.is_clinic_of(text), private.staff_of(text), private.is_patient() to authenticated;

revoke execute on function public.book_token(text, text, text, text), public.cancel_token(text) from public, anon;
grant execute on function public.book_token(text, text, text, text), public.cancel_token(text) to authenticated;
