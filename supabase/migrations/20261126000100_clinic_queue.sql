-- Phase 6 (D-52), part 1: clinic web queue work in Postgres.
-- Ports functions/src/lib/access.ts, clinic/queueAction.ts, clinic/nextOrder.ts, clinic/phoneLookup.ts and the
-- walk-in / patient / follow-up parts of clinic/clinicData.ts. Same rules (PRD-CLINIC-WEB C-02…C-09, BW-1…BW-7,
-- D-22…D-24, D-35, D-38, D-40). Change: a NEW walk-in profile is never attached to an app account by phone any more
-- (D-52, no auto-linking); reception links in person with link_walk_in_to_account (part 3).
--
-- Errors: message = code (permission-denied, not-found, invalid-argument, suspended, not-started, paused, ended,
-- empty, not-arrived, undo-expired, completed, bad-status, session-ended, tokens-full, duplicate-token,
-- managed-by-app, rate-limited); HINT = text for the receptionist; DETAIL = JSON extras.

-- A walk-in's age may be unknown (C-06), and a deleted app profile has no phone (F-10).
alter table public.patients alter column birth_year drop not null;
alter table public.patients alter column phone drop not null;
alter table public.patients add constraint patients_phone_unless_deleted check (phone is not null or status = 'deleted');

-- ================================================================ who is calling (access.ts)

-- The clinic login of its own clinic: {uid, role, clinicId, name}. Raises permission-denied otherwise.
create or replace function private.clinic_actor() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_clinic text := private.jwt_clinic(); v_name text;
begin
  if not private.is_clinic() then
    raise exception 'permission-denied' using hint = 'This account doesn''t have clinic access.';
  end if;
  select c.name into v_name from public.clinics c where c.id = v_clinic;
  return jsonb_build_object('uid', auth.uid(), 'role', 'clinic', 'clinicId', v_clinic, 'name', coalesce(v_name, 'Clinic'));
end $$;

create or replace function private.admin_actor() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_name text;
begin
  if not private.is_super_admin() then
    raise exception 'permission-denied' using hint = 'Super admin only.';
  end if;
  select a.name into v_name from public.admin_users a where a.id = auth.uid();
  return jsonb_build_object('uid', auth.uid(), 'role', 'superAdmin', 'clinicId', null, 'name', coalesce(nullif(v_name, ''), 'Super Admin'));
end $$;

-- "Al-Shifa Clinic (clinic login)" / "Sarbuland (Super Admin)" for token history.
create or replace function private.actor_label(a jsonb) returns text
language sql immutable as $$
  select (a ->> 'name') || case when a ->> 'role' = 'clinic' then ' (clinic login)' else ' (Super Admin)' end $$;

create or replace function private.history_entry(p_action text, a jsonb, p_note text default null) returns jsonb
language sql stable as $$
  select jsonb_build_object('action', p_action, 'by', private.actor_label(a), 'at', private.now_utc())
         || case when p_note is null or p_note = '' then '{}'::jsonb else jsonb_build_object('note', p_note) end $$;

-- A-07 / BW-10: every change writes one activity log row.
create or replace function private.log_activity(a jsonb, p_clinic text, p_action text, p_target text) returns void
language sql security definer set search_path = '' as $$
  insert into public.activity_logs (clinic_id, actor, action, target, at)
  values (p_clinic, jsonb_build_object('uid', a ->> 'uid', 'name', a ->> 'name', 'role', a ->> 'role'), p_action,
          coalesce(p_target, ''), private.now_utc()) $$;

-- A suspended or cancelled clinic's queue is read-only.
create or replace function private.require_writable(p_clinic text) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if exists (select 1 from public.clinics c where c.id = p_clinic and c.status in ('suspended', 'cancelled')) then
    raise exception 'suspended' using hint = 'This clinic is suspended. The queue is read-only until the payment is recorded.';
  end if;
end $$;

-- Creates today's queue day if needed and locks it (the locking rule of phase 2).
create or replace function private.lock_day(p_doctor text, p_date text, p_clinic text) returns public.queue_days
language plpgsql security definer set search_path = '' as $$
declare d public.queue_days;
begin
  insert into public.queue_days (doctor_id, date, clinic_id) values (p_doctor, p_date, p_clinic)
  on conflict (doctor_id, date) do nothing;
  select * into d from public.queue_days where doctor_id = p_doctor and date = p_date for update;
  return d;
end $$;

create or replace function private.minutes_since(p_from timestamptz) returns integer
language sql stable as $$ select case when p_from is null then null
                                      else greatest(0, round(extract(epoch from private.now_utc() - p_from) / 60))::integer end $$;

-- D-35 / D-38: a token that already got "Your turn now" gets ONE more when really called (turn_repeat_used).
create or replace function private.turn_repeat(t public.tokens) returns boolean
language sql immutable as $$ select t.notified ? 'yourTurn' and not t.turn_repeat_used $$;

-- ================================================================ queue_action (queueAction.ts)

create or replace function public.queue_action(
  p_action text, p_doctor_id text default null, p_token_id text default null,
  p_reason text default null, p_call_not_arrived text default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a        jsonb := private.clinic_actor();
  v_clinic text := a ->> 'clinicId';
  v_today  text := private.pkt_today();
  v_now    timestamptz := private.now_utc();
  v_reason text := nullif(left(btrim(coalesce(p_reason, '')), 80), '');
  v_day    public.queue_days;
  v_cur    public.tokens;
  v_next   public.tokens;
  t        public.tokens;
  v_undo   jsonb;
  v_called jsonb := null;
begin
  if p_action not in ('start', 'pause', 'end', 'next', 'undo',
                      'arrive', 'callNow', 'skip', 'hold', 'backToQueue', 'cancel', 'noShow', 'reprint') then
    raise exception 'invalid-argument' using hint = 'Unknown action.';
  end if;
  if p_action <> 'reprint' then perform private.require_writable(v_clinic); end if;

  -- ---------------------------------------------------------------- session actions (one doctor, today)
  if p_action in ('start', 'pause', 'end', 'next', 'undo') then
    if not exists (select 1 from public.doctors d where d.id = p_doctor_id and d.clinic_id = v_clinic) then
      raise exception 'not-found' using hint = 'Doctor not found.';
    end if;
    v_day := private.lock_day(p_doctor_id, v_today, v_clinic);

    if p_action in ('start', 'pause') then
      update public.queue_days set session_status = case when p_action = 'start' then 'running' else 'paused' end
       where doctor_id = p_doctor_id and date = v_today;

    elsif p_action = 'end' then
      -- C-02: remaining Booked → No-show; the patient being seen is completed.
      update public.tokens x
         set status = case when x.status = 'called' then 'completed' else 'noShow' end,
             completed_at = case when x.status = 'called' then v_now else x.completed_at end,
             history = x.history || jsonb_build_array(private.history_entry(
                         case when x.status = 'called' then 'Completed' else 'No-show (session ended)' end, a))
       where x.doctor_id = p_doctor_id and x.date = v_today and x.status in ('booked', 'called');
      update public.queue_days set session_status = 'ended', undo = null where doctor_id = p_doctor_id and date = v_today;

    elsif p_action = 'next' then
      if v_day.session_status = 'notStarted' then raise exception 'not-started' using hint = 'Start the session first.'; end if;
      if v_day.session_status = 'paused' then raise exception 'paused' using hint = 'The session is paused. Resume it first.'; end if;
      if v_day.session_status = 'ended' then raise exception 'ended' using hint = 'Today''s session has ended.'; end if;

      select * into v_cur from public.tokens x
       where x.doctor_id = p_doctor_id and x.date = v_today and x.status = 'called' limit 1 for update;
      -- D-24: a Skipped patient who checked in again (priority_at) first, else the lowest Booked / Arrived number.
      select * into v_next from public.tokens x
       where x.doctor_id = p_doctor_id and x.date = v_today
         and ((x.status = 'arrived' and x.priority_at is not null) or x.status in ('arrived', 'booked'))
       order by (x.status = 'arrived' and x.priority_at is not null) desc, x.priority_at nulls last, x.number
       limit 1 for update;
      if v_cur.id is null and v_next.id is null then raise exception 'empty' using hint = 'No patients waiting.'; end if;

      if v_next.id is not null and v_next.status = 'booked' and v_next.id is distinct from p_call_not_arrived then
        -- Nothing is written; the web asks "Skip / Call anyway" and calls again.
        raise exception 'not-arrived'
          using hint = private.token_label(v_next.token_prefix, v_next.number) || ' has not arrived.',
                detail = jsonb_build_object('tokenId', v_next.id, 'label', private.token_label(v_next.token_prefix, v_next.number),
                                            'name', v_next.patient_snapshot ->> 'name')::text;
      end if;

      if v_cur.id is not null then
        update public.tokens set status = 'completed', completed_at = v_now,
               history = history || jsonb_build_array(private.history_entry('Completed', a))
         where id = v_cur.id;
      end if;
      if v_next.id is not null then
        update public.tokens set status = 'called', called_at = v_now,
               wait_minutes = private.minutes_since(coalesce(v_next.arrived_at, v_next.created_at)),
               history = history || jsonb_build_array(private.history_entry('Called (Next)', a))
         where id = v_next.id;
        v_called := jsonb_build_object('id', v_next.id, 'label', private.token_label(v_next.token_prefix, v_next.number),
                                       'name', v_next.patient_snapshot ->> 'name');
      end if;
      -- C-03 "Undo last Next" for 30 seconds.
      update public.queue_days
         set current_token = coalesce(v_next.number, v_day.current_token),
             undo = jsonb_build_object('at', v_now, 'completedId', v_cur.id, 'calledId', v_next.id,
                                       'calledPrevStatus', v_next.status, 'prevCurrent', v_day.current_token)
       where doctor_id = p_doctor_id and date = v_today;

    else -- undo
      v_undo := v_day.undo;
      if v_undo is null or (v_undo ->> 'at') is null or v_now - (v_undo ->> 'at')::timestamptz > interval '30 seconds' then
        raise exception 'undo-expired' using hint = 'Undo is no longer available.';
      end if;
      if v_undo ->> 'calledId' is not null then
        select * into t from public.tokens where id = v_undo ->> 'calledId' for update;
        -- D-38: no push on undo; one more "Your turn now" when really called.
        update public.tokens set status = coalesce(v_undo ->> 'calledPrevStatus', 'arrived'), called_at = null, wait_minutes = null,
               notified = case when private.turn_repeat(t) then notified - 'yourTurn' else notified end,
               turn_repeat_used = turn_repeat_used or private.turn_repeat(t),
               history = history || jsonb_build_array(private.history_entry('Undo last Next', a))
         where id = t.id;
      end if;
      if v_undo ->> 'completedId' is not null then
        update public.tokens set status = 'called', completed_at = null,
               history = history || jsonb_build_array(private.history_entry('Undo last Next', a))
         where id = v_undo ->> 'completedId';
      end if;
      update public.queue_days set current_token = coalesce((v_undo ->> 'prevCurrent')::integer, 0), undo = null
       where doctor_id = p_doctor_id and date = v_today;
    end if;

    return jsonb_build_object('ok', true, 'called', v_called);
  end if;

  -- ---------------------------------------------------------------- one token
  select * into t from public.tokens where id = p_token_id;
  if t.id is null or t.clinic_id <> v_clinic then raise exception 'not-found' using hint = 'Token not found.'; end if;
  perform private.lock_day(t.doctor_id, t.date, t.clinic_id);
  select * into t from public.tokens where id = p_token_id for update;

  if t.status = 'completed' and p_action <> 'reprint' then
    raise exception 'completed' using hint = 'A completed token cannot be changed.';   -- BW-4
  end if;
  if not (t.status = any (case p_action
            when 'arrive'      then array['booked', 'skipped']       -- D-24: a Skipped patient may check in later
            when 'callNow'     then array['booked', 'arrived', 'onHold', 'skipped']
            when 'skip'        then array['booked', 'arrived', 'called']
            when 'hold'        then array['booked', 'arrived', 'called']
            when 'backToQueue' then array['onHold', 'skipped']
            when 'cancel'      then array['booked', 'arrived', 'onHold']
            when 'noShow'      then array['booked', 'arrived', 'onHold', 'skipped']
            when 'reprint'     then array['arrived', 'called', 'completed', 'onHold'] end)) then
    raise exception 'bad-status' using hint = 'This token is ' || t.status || '; that action is not possible now.';
  end if;

  if p_action = 'arrive' then
    update public.tokens set status = 'arrived', arrived_at = v_now,
           priority_at = case when t.status = 'skipped' then v_now else priority_at end,
           history = history || jsonb_build_array(private.history_entry(
                       case when t.status = 'skipped' then 'Arrived after skip · called next' else 'Arrived' end, a))
     where id = t.id;
  elsif p_action = 'callNow' then
    -- BW-3: one Called token per doctor; the current one is completed.
    update public.tokens set status = 'completed', completed_at = v_now,
           history = history || jsonb_build_array(private.history_entry('Completed', a))
     where doctor_id = t.doctor_id and date = t.date and status = 'called' and id <> t.id;
    update public.tokens set status = 'called', called_at = v_now, arrived_at = coalesce(arrived_at, v_now),
           wait_minutes = private.minutes_since(coalesce(t.arrived_at, t.created_at)),
           history = history || jsonb_build_array(private.history_entry(
                       case when t.status = 'skipped' then 'Recalled' else 'Called (out of order)' end, a))
     where id = t.id;
    update public.queue_days set current_token = t.number, undo = null where doctor_id = t.doctor_id and date = t.date;
  elsif p_action = 'skip' then
    -- D-35: one more "Your turn now" when recalled (max once per token). The skip push is sent by the trigger (D-34).
    update public.tokens set status = 'skipped', priority_at = null,
           notified = case when private.turn_repeat(t) then notified - 'yourTurn' else notified end,
           turn_repeat_used = turn_repeat_used or private.turn_repeat(t),
           history = history || jsonb_build_array(private.history_entry('Skipped', a))
     where id = t.id;
  elsif p_action = 'hold' then
    update public.tokens set status = 'onHold', priority_at = null,
           history = history || jsonb_build_array(private.history_entry('On hold', a, v_reason))
     where id = t.id;
  elsif p_action = 'backToQueue' then
    -- D-24: back from Skipped = checked in again → called right after the current patient.
    update public.tokens set status = 'arrived', arrived_at = coalesce(arrived_at, v_now),
           priority_at = case when t.status = 'skipped' then v_now else priority_at end,
           history = history || jsonb_build_array(private.history_entry(
                       case when t.status = 'skipped' then 'Back to queue · called next' else 'Back to queue' end, a))
     where id = t.id;
  elsif p_action = 'cancel' then
    -- The "cancelled by clinic" push is sent by the trigger (D-23).
    update public.tokens set status = 'cancelled', cancelled_at = v_now, cancelled_by = 'clinic', cancel_reason = v_reason,
           history = history || jsonb_build_array(private.history_entry('Cancelled', a, v_reason))
     where id = t.id;
  elsif p_action = 'noShow' then
    update public.tokens set status = 'noShow', history = history || jsonb_build_array(private.history_entry('Marked No-show', a))
     where id = t.id;
  else -- reprint
    update public.tokens set history = history || jsonb_build_array(private.history_entry('Reprinted', a)) where id = t.id;
  end if;
  return jsonb_build_object('ok', true, 'called', null);
end $$;

-- ================================================================ walk-in token (C-06, BW-2)

-- Existing profile: p_patient_id (+ p_phone = its full number when it is not yet at this clinic, D-22).
-- New profile: p_new = {phone, name, gender, relation?, age?}. Never attached to an app account by phone (D-52).
create or replace function public.clinic_create_walk_in(
  p_doctor_id text, p_patient_id text default null, p_phone text default null, p_new jsonb default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a        jsonb := private.clinic_actor();
  v_clinic text := a ->> 'clinicId';
  v_today  text := private.pkt_today();
  v_now    timestamptz := private.now_utc();
  v_doctor public.doctors;
  v_day    public.queue_days;
  v_pat    public.patients;
  v_dup    public.tokens;
  v_number integer;
  v_token  text := gen_random_uuid()::text;
  v_phone  text;
  v_name   text;
  v_age    integer;
begin
  perform private.require_writable(v_clinic);
  select * into v_doctor from public.doctors where id = p_doctor_id;
  if v_doctor.id is null or v_doctor.clinic_id <> v_clinic or not v_doctor.active then
    raise exception 'not-found' using hint = 'Doctor not found.';
  end if;

  if p_patient_id is null then
    v_phone := private.normalize_pk_mobile(p_new ->> 'phone');
    v_name := regexp_replace(btrim(coalesce(p_new ->> 'name', '')), '\s+', ' ', 'g');
    if v_phone is null then raise exception 'invalid-argument' using hint = 'Enter a valid Pakistani mobile number.'; end if;
    if char_length(v_name) < 2 or char_length(v_name) > 60 then raise exception 'invalid-argument' using hint = 'Enter the patient name.'; end if;
    if coalesce(p_new ->> 'gender', '') not in ('male', 'female', 'other') then
      raise exception 'invalid-argument' using hint = 'Pick a gender.';
    end if;
    if coalesce(p_new ->> 'relation', 'other') not in ('self', 'mother', 'father', 'spouse', 'son', 'daughter', 'brother', 'sister', 'other') then
      raise exception 'invalid-argument' using hint = 'Unknown relation.';
    end if;
    v_age := nullif(p_new ->> 'age', '')::integer;
    if v_age is not null and (v_age < 0 or v_age > 120) then raise exception 'invalid-argument' using hint = 'Age must be 0 to 120.'; end if;
  end if;

  v_day := private.lock_day(p_doctor_id, v_today, v_clinic);
  if v_day.session_status = 'ended' then
    raise exception 'session-ended' using hint = 'Today''s session has ended for this doctor.';
  end if;
  if v_day.last_token_number >= v_doctor.max_tokens_per_day then
    raise exception 'tokens-full' using hint = 'All ' || v_doctor.max_tokens_per_day || ' tokens for today are used.';
  end if;

  if p_patient_id is not null then
    select * into v_pat from public.patients where id = p_patient_id for update;
    -- A profile from another clinic (D-22 lookup) only with its full phone number.
    if v_pat.id is null or v_pat.status <> 'active'
       or (not (v_clinic = any (v_pat.clinic_ids)) and private.normalize_pk_mobile(p_phone) is distinct from v_pat.phone) then
      raise exception 'not-found' using hint = 'Patient not found.';
    end if;
    select * into v_dup from public.tokens
     where patient_id = v_pat.id and doctor_id = p_doctor_id and date = v_today
       and status in ('booked', 'arrived', 'called', 'onHold') limit 1;
    if v_dup.id is not null then
      raise exception 'duplicate-token'
        using hint = v_pat.name || ' already has token ' || private.token_label(v_dup.token_prefix, v_dup.number) || ' today.';
    end if;
    update public.patients set clinic_ids = array_append(clinic_ids, v_clinic)
     where id = v_pat.id and not (v_clinic = any (clinic_ids));
  else
    insert into public.patients (phone, owner_uid, name, birth_year, gender, relation, created_by, clinic_ids)
    values (v_phone, null, v_name,
            case when v_age is null then null else extract(year from v_now at time zone 'Asia/Karachi')::integer - v_age end,
            p_new ->> 'gender', coalesce(p_new ->> 'relation', 'other'), 'staff', array[v_clinic])
    returning * into v_pat;
  end if;

  v_number := v_day.last_token_number + 1;
  update public.queue_days set last_token_number = v_number, booked_count = booked_count + 1
   where doctor_id = p_doctor_id and date = v_today;
  insert into public.tokens (id, clinic_id, doctor_id, date, number, token_prefix, patient_id, patient_snapshot,
                             booked_by_user_id, patient_owner_uid, source, status, arrived_at, created_at, history)
  values (v_token, v_clinic, p_doctor_id, v_today, v_number, v_doctor.token_prefix, v_pat.id,
          jsonb_build_object('name', v_pat.name, 'birthYear', v_pat.birth_year, 'gender', v_pat.gender,
                             'relation', v_pat.relation, 'phone', v_pat.phone),
          null, v_pat.owner_uid, 'walkIn', 'arrived', v_now, v_now,
          jsonb_build_array(private.history_entry('Walk-in created · Arrived', a)));
  insert into public.clinic_stats (clinic_id, month, walk_in, tokens) values (v_clinic, left(v_today, 7), 1, 1)
  on conflict (clinic_id, month) do update set walk_in = public.clinic_stats.walk_in + 1, tokens = public.clinic_stats.tokens + 1;

  return jsonb_build_object('tokenId', v_token, 'number', v_number, 'label', private.token_label(v_doctor.token_prefix, v_number),
                            'patientId', v_pat.id);
end $$;

-- ================================================================ phone lookup (D-22, S-3)

-- Profiles on a FULL phone number from any clinic: only id, name, relation, gender, age, atThisClinic and
-- appAccount (the web labels those "App account (number not verified)", S-3). 30 lookups / 10 minutes per clinic.
create or replace function public.clinic_lookup_phone(p_phone text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a        jsonb := private.clinic_actor();
  v_clinic text := a ->> 'clinicId';
  v_phone  text := private.normalize_pk_mobile(p_phone);
  v_now    timestamptz := private.now_utc();
  v_rl     public.rate_limits;
  v_year   integer := extract(year from v_now at time zone 'Asia/Karachi')::integer;
begin
  if v_phone is null then raise exception 'invalid-argument' using hint = 'Enter the full mobile number.'; end if;
  insert into public.rate_limits (id, clinic_id, window_start, count) values ('phoneLookup_' || v_clinic, v_clinic, v_now, 0)
  on conflict (id) do nothing;
  select * into v_rl from public.rate_limits where id = 'phoneLookup_' || v_clinic for update;
  if v_now - v_rl.window_start >= interval '10 minutes' then
    update public.rate_limits set window_start = v_now, count = 1 where id = v_rl.id;
  elsif v_rl.count >= 30 then
    raise exception 'rate-limited' using hint = 'Too many phone lookups. Please try again in a few minutes.';
  else
    update public.rate_limits set count = count + 1 where id = v_rl.id;
  end if;

  return jsonb_build_object('profiles', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', p.id, 'name', p.name, 'relation', p.relation, 'gender', p.gender,
             'age', case when p.birth_year is null then null else greatest(0, v_year - p.birth_year) end,
             'atThisClinic', v_clinic = any (p.clinic_ids),
             'appAccount', p.owner_uid is not null)
           order by (p.owner_uid is not null) desc, (p.relation = 'self') desc, p.created_at)
      from (select * from public.patients x where x.phone = v_phone and x.status = 'active'
             order by x.created_at limit 20) p), '[]'::jsonb));
end $$;

-- ================================================================ patient details (C-08, D-40)

create or replace function public.clinic_update_patient(p_patient_id text, p_name text, p_gender text, p_age integer default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a      jsonb := private.clinic_actor();
  v_pat  public.patients;
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
begin
  select * into v_pat from public.patients where id = p_patient_id;
  if v_pat.id is null or not ((a ->> 'clinicId') = any (v_pat.clinic_ids)) then
    raise exception 'not-found' using hint = 'Patient not found.';
  end if;
  if v_pat.owner_uid is not null then
    raise exception 'managed-by-app' using hint = 'This patient manages their details in the Asani app.';
  end if;
  if char_length(v_name) < 2 or char_length(v_name) > 60 then raise exception 'invalid-argument' using hint = 'Enter the patient name.'; end if;
  if p_gender not in ('male', 'female', 'other') then raise exception 'invalid-argument' using hint = 'Pick a gender.'; end if;
  if p_age is not null and (p_age < 0 or p_age > 120) then raise exception 'invalid-argument' using hint = 'Age must be 0 to 120.'; end if;
  update public.patients
     set name = v_name, gender = p_gender,
         birth_year = case when p_age is null then birth_year
                           else extract(year from private.now_utc() at time zone 'Asia/Karachi')::integer - p_age end
   where id = v_pat.id;
  perform private.log_activity(a, a ->> 'clinicId', 'edited patient details', v_name);
  return jsonb_build_object('ok', true);
end $$;

-- ================================================================ follow-up (C-09)

-- One pending follow-up per patient and doctor: setting another updates it.
create or replace function public.set_follow_up(p_token_id text, p_due_date text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a     jsonb := private.clinic_actor();
  t     public.tokens;
  v_id  text;
  v_own uuid;
  v_note text := nullif(left(btrim(coalesce(p_note, '')), 40), '');
begin
  select * into t from public.tokens where id = p_token_id;
  if t.id is null or t.clinic_id <> a ->> 'clinicId' then raise exception 'not-found' using hint = 'Token not found.'; end if;
  if p_due_date is null or p_due_date !~ '^\d{4}-\d{2}-\d{2}$' or p_due_date <= private.pkt_today() then
    raise exception 'invalid-argument' using hint = 'Pick a date after today.';
  end if;
  select p.owner_uid into v_own from public.patients p where p.id = t.patient_id;
  select f.id into v_id from public.follow_ups f
   where f.patient_id = t.patient_id and f.doctor_id = t.doctor_id and f.status = 'pending' limit 1 for update;
  if v_id is null then
    insert into public.follow_ups (clinic_id, doctor_id, patient_id, owner_uid, source_token_id, due_date, note)
    values (t.clinic_id, t.doctor_id, t.patient_id, v_own, t.id, p_due_date, v_note)
    returning id into v_id;
  else
    update public.follow_ups set source_token_id = t.id, due_date = p_due_date, note = v_note, owner_uid = v_own,
           reminders_sent = 0, booked_token_id = null
     where id = v_id;
  end if;
  update public.tokens set history = history || jsonb_build_array(private.history_entry('Follow-up set', a, p_due_date))
   where id = t.id;
  return jsonb_build_object('ok', true, 'followUpId', v_id);
end $$;

-- ================================================================ grants
revoke execute on all functions in schema private from public, anon;
grant execute on function private.jwt_role(), private.jwt_clinic(), private.is_super_admin(), private.is_clinic(),
  private.is_clinic_of(text), private.staff_of(text), private.is_patient() to authenticated;
revoke execute on function public.queue_action(text, text, text, text, text), public.clinic_create_walk_in(text, text, text, jsonb),
  public.clinic_lookup_phone(text), public.clinic_update_patient(text, text, text, integer),
  public.set_follow_up(text, text, text) from public, anon;
grant execute on function public.queue_action(text, text, text, text, text), public.clinic_create_walk_in(text, text, text, jsonb),
  public.clinic_lookup_phone(text), public.clinic_update_patient(text, text, text, integer),
  public.set_follow_up(text, text, text) to authenticated;
