-- QA fixes of 2026-11-28 (D-68).
-- I1: a suspended or cancelled clinic is read-only, except that it can still cancel tokens (so patients are told
--     not to come). Viewing, exporting, billing, the manager PIN and the password keep working.
-- I3: a token can only be worked on its own day (no early "Your turn now").
-- I2: the Super Admin's live feeds for monthly token counts and PMDC numbers.
-- The functions below are copies of the earlier ones; the added lines are marked D-68.


create or replace function private.require_writable(p_clinic text) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if exists (select 1 from public.clinics c where c.id = p_clinic and c.status in ('suspended', 'cancelled')) then
    raise exception 'suspended' using hint = 'This clinic is suspended. It is read-only until the payment is recorded; you can still cancel tokens.';
  end if;
end $$;

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
  -- D-68: a suspended clinic can still cancel.
  if p_action not in ('reprint', 'cancel') then perform private.require_writable(v_clinic); end if;

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

  -- D-68: calling a patient on another day would send "Your turn now" on the wrong day. Cancel and reprint work on
  -- any day; No-show also for a past day.
  if (p_action in ('arrive', 'callNow', 'skip', 'hold', 'backToQueue') and t.date <> v_today)
     or (p_action = 'noShow' and t.date > v_today) then
    raise exception 'not-today' using hint = 'This token is for another day.';
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

create or replace function public.set_follow_up(p_token_id text, p_due_date text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a     jsonb := private.clinic_actor();
  t     public.tokens;
  v_id  text;
  v_own uuid;
  v_note text := nullif(left(btrim(coalesce(p_note, '')), 40), '');
begin
  perform private.require_writable(a ->> 'clinicId');  -- D-68
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

create or replace function public.clinic_update_patient(p_patient_id text, p_name text, p_gender text, p_age integer default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a      jsonb := private.clinic_actor();
  v_pat  public.patients;
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
begin
  perform private.require_writable(a ->> 'clinicId');  -- D-68
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

create or replace function public.save_doctor(
  p_doctor_id text, p_name text, p_speciality text, p_pmdc text, p_qualification text,
  p_avg_consult_minutes integer, p_max_tokens_per_day integer, p_booking_window_days integer, p_schedule jsonb
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a        jsonb := private.clinic_actor();
  v_clinic text := a ->> 'clinicId';
  v_name   text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_pmdc   text;
  v_sched  jsonb;
  v_city   text;
  v_cur    public.doctors;
  v_c      public.clinics;
  v_next   integer;
  v_id     text;
  v_letters text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
begin
  perform private.require_writable(a ->> 'clinicId');  -- D-68
  if char_length(v_name) < 2 or char_length(v_name) > 60 then raise exception 'invalid-argument' using hint = 'Enter the doctor''s name.'; end if;
  if p_speciality is null or p_speciality not in ('generalPhysician', 'child', 'heart', 'teeth', 'skin', 'womensHealth', 'eye',
       'ent', 'bones', 'diabetes', 'stomach', 'chest', 'kidney', 'brain', 'mentalHealth', 'physio', 'other') then
    raise exception 'invalid-argument' using hint = 'Pick a speciality from the list.';   -- D-31: never free text
  end if;
  if nullif(btrim(coalesce(p_pmdc, '')), '') is not null then
    v_pmdc := private.normalize_pmdc(p_pmdc);
    if v_pmdc is null then raise exception 'invalid-argument' using hint = 'Not a valid PMDC number.'; end if;
  end if;
  if p_avg_consult_minutes is null or p_avg_consult_minutes not between 2 and 120
     or p_max_tokens_per_day is null or p_max_tokens_per_day not between 1 and 300
     or p_booking_window_days is null or p_booking_window_days not between 0 and 60 then
    raise exception 'invalid-argument' using hint = 'Check consult minutes (2–120), tokens per day (1–300) and booking window (0–60).';
  end if;
  v_sched := private.clean_schedule(p_schedule);
  select city into v_city from public.clinics where id = v_clinic;

  if p_doctor_id is not null then
    select * into v_cur from public.doctors where id = p_doctor_id;
    if v_cur.id is null or v_cur.clinic_id <> v_clinic then raise exception 'not-found' using hint = 'Doctor not found.'; end if;
    update public.doctors
       set name = v_name, speciality = p_speciality, city = coalesce(v_city, ''), name_key = private.doctor_name_key(v_name),
           qualification = nullif(left(btrim(coalesce(p_qualification, '')), 60), ''),
           avg_consult_minutes = p_avg_consult_minutes, max_tokens_per_day = p_max_tokens_per_day,
           booking_window_days = p_booking_window_days, schedule = v_sched,
           has_pmdc = has_pmdc or v_pmdc is not null, speciality_flagged = false
     where id = p_doctor_id;
    if v_pmdc is not null then
      insert into public.doctor_private (doctor_id, clinic_id, pmdc_number) values (p_doctor_id, v_clinic, v_pmdc)
      on conflict (doctor_id) do update set pmdc_number = excluded.pmdc_number;
    end if;
    perform private.log_activity(a, v_clinic, 'updated doctor', v_name);
    perform private.build_suggestions(p_doctor_id);
    return jsonb_build_object('doctorId', p_doctor_id, 'tokenPrefix', v_cur.token_prefix, 'hasPmdc', v_cur.has_pmdc or v_pmdc is not null);
  end if;

  -- New: the letter is assigned here and never reused (BW-7).
  perform private.require_pin_unlocked(v_clinic);
  select * into v_c from public.clinics where id = v_clinic for update;
  select greatest(v_c.next_doctor_letter,
                  coalesce(max(strpos(v_letters, d.token_prefix)), 0))   -- strpos is 1-based = "max used index + 1"
    into v_next from public.doctors d where d.clinic_id = v_clinic;
  if v_next >= 26 then raise exception 'no-letters' using hint = 'No more doctor letters available.'; end if;

  insert into public.doctors (clinic_id, name, speciality, city, name_key, qualification, avg_consult_minutes,
                              max_tokens_per_day, booking_window_days, token_prefix, schedule, active, sort_order,
                              added_by, has_pmdc)
  values (v_clinic, v_name, p_speciality, coalesce(v_city, ''), private.doctor_name_key(v_name),
          nullif(left(btrim(coalesce(p_qualification, '')), 60), ''), p_avg_consult_minutes, p_max_tokens_per_day,
          p_booking_window_days, substr(v_letters, v_next + 1, 1), v_sched, true,
          (select count(*) + 1 from public.doctors where clinic_id = v_clinic), 'clinic', v_pmdc is not null)
  returning id into v_id;
  if v_pmdc is not null then
    insert into public.doctor_private (doctor_id, clinic_id, pmdc_number) values (v_id, v_clinic, v_pmdc);
  end if;
  update public.clinics
     set next_doctor_letter = v_next + 1,
         doctor_count = (select count(*) from public.doctors where clinic_id = v_clinic and active)
   where id = v_clinic;
  perform private.log_activity(a, v_clinic, 'added doctor', v_name || ' · ' || p_speciality);   -- D-19
  perform private.build_suggestions(v_id);   -- bookable at once; a match only creates a suggestion (D-32)
  return jsonb_build_object('doctorId', v_id, 'tokenPrefix', substr(v_letters, v_next + 1, 1), 'hasPmdc', v_pmdc is not null);
end $$;

create or replace function public.set_doctor_active(p_doctor_id text, p_active boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := private.clinic_actor(); d public.doctors;
begin
  perform private.require_writable(a ->> 'clinicId');  -- D-68
  select * into d from public.doctors where id = p_doctor_id;
  if d.id is null or d.clinic_id <> a ->> 'clinicId' then raise exception 'not-found' using hint = 'Doctor not found.'; end if;
  if not p_active then perform private.require_pin_unlocked(d.clinic_id); end if;
  update public.doctors set active = p_active where id = d.id;
  update public.clinics set doctor_count = (select count(*) from public.doctors where clinic_id = d.clinic_id and active)
   where id = d.clinic_id;
  perform private.log_activity(a, d.clinic_id, case when p_active then 'reactivated doctor' else 'deactivated doctor' end, d.name);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.set_doctor_leave(p_doctor_id text, p_date text, p_add boolean default true) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := private.clinic_actor(); d public.doctors;
begin
  perform private.require_writable(a ->> 'clinicId');  -- D-68
  select * into d from public.doctors where id = p_doctor_id;
  if d.id is null or d.clinic_id <> a ->> 'clinicId' then raise exception 'not-found' using hint = 'Doctor not found.'; end if;
  if p_date is null or p_date !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'invalid-argument' using hint = 'date must be yyyy-MM-dd.'; end if;
  update public.doctors
     set on_leave_dates = case when p_add then (select array_agg(distinct x order by x) from unnest(array_append(on_leave_dates, p_date)) x)
                               else array_remove(on_leave_dates, p_date) end
   where id = d.id;
  perform private.log_activity(a, d.clinic_id, case when p_add then 'added leave' else 'removed leave' end, d.name || ' · ' || p_date);
  return jsonb_build_object('activeTokens', (select count(*) from public.tokens t where t.doctor_id = d.id and t.date = p_date
                                               and t.status in ('booked', 'arrived', 'called', 'onHold')));
end $$;

create or replace function public.update_clinic_settings(
  p_address text, p_area text, p_phone text, p_print_format text, p_lat double precision, p_lng double precision
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := private.clinic_actor();
begin
  perform private.require_writable(a ->> 'clinicId');  -- D-68
  if p_print_format not in ('thermal80', 'a5', 'none') then raise exception 'invalid-argument' using hint = 'Unknown print format.'; end if;
  if coalesce(btrim(p_address), '') = '' or coalesce(btrim(p_area), '') = '' or coalesce(btrim(p_phone), '') = '' then
    raise exception 'invalid-argument' using hint = 'Address, area and phone are required.';
  end if;
  perform private.require_location(p_lat, p_lng);   -- D-31, BW-12
  update public.clinics
     set address = left(btrim(p_address), 120), area = left(btrim(p_area), 60), phone = left(btrim(p_phone), 20),
         print_format = p_print_format, lat = p_lat, lng = p_lng
   where id = a ->> 'clinicId';
  perform private.log_activity(a, a ->> 'clinicId', 'updated clinic settings', a ->> 'name');
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.link_walk_in_to_account(p_walk_in_id text, p_account_phone text, p_target_patient_id text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a        jsonb := private.clinic_actor();
  v_clinic text := a ->> 'clinicId';
  w        public.patients;
  tgt      public.patients;
  v_owner  uuid;
  v_phone  text := private.normalize_pk_mobile(p_account_phone);
  v_tokens integer;
begin
  perform private.require_writable(a ->> 'clinicId');  -- D-68
  select * into w from public.patients where id = p_walk_in_id for update;
  if w.id is null or w.status <> 'active' or not (v_clinic = any (w.clinic_ids)) then
    raise exception 'not-found' using hint = 'Walk-in profile not found at this clinic.';
  end if;
  if w.owner_uid is not null then raise exception 'already-linked' using hint = 'This profile already belongs to an app account.'; end if;
  if v_phone is null then raise exception 'invalid-argument' using hint = 'Enter the app account''s mobile number.'; end if;
  select u.id into v_owner from public.users u where u.phone = v_phone;
  if v_owner is null then raise exception 'no-account' using hint = 'No Asani app account uses this number.'; end if;

  if p_target_patient_id is not null then
    select * into tgt from public.patients where id = p_target_patient_id for update;
    if tgt.id is null or tgt.owner_uid is distinct from v_owner or tgt.status <> 'active' then
      raise exception 'not-found' using hint = 'Family member not found on that account.';
    end if;
    update public.tokens set patient_id = tgt.id, patient_owner_uid = v_owner where patient_id = w.id;
    get diagnostics v_tokens = row_count;
    update public.follow_ups set patient_id = tgt.id, owner_uid = v_owner where patient_id = w.id;
    update public.patients
       set clinic_ids = (select array_agg(distinct x) from unnest(tgt.clinic_ids || w.clinic_ids) x)
     where id = tgt.id;
    update public.patients set status = 'merged', merged_into = tgt.id where id = w.id;
    perform private.log_activity(a, v_clinic, 'linked walk-in to app account',
                                 w.name || ' → ' || tgt.name || ' (' || v_tokens || ' visits moved)');
    return jsonb_build_object('ok', true, 'patientId', tgt.id, 'merged', true, 'visitsMoved', v_tokens);
  end if;

  -- New member of the family (a walk-in "Self" becomes "Other": the account already has its own Self).
  update public.patients
     set owner_uid = v_owner, relation = case when relation = 'self' then 'other' else relation end
   where id = w.id;
  update public.tokens set patient_owner_uid = v_owner where patient_id = w.id;
  get diagnostics v_tokens = row_count;
  update public.follow_ups set owner_uid = v_owner where patient_id = w.id;
  perform private.log_activity(a, v_clinic, 'linked walk-in to app account', w.name || ' → new family member (' || v_tokens || ' visits)');
  return jsonb_build_object('ok', true, 'patientId', w.id, 'merged', false, 'visitsMoved', v_tokens);
end $$;

-- ------------------------------------------------------------------ I2: live feeds (RLS still applies)
do $$
declare t text;
begin
  foreach t in array array['clinic_stats', 'doctor_private'] loop
    if not exists (select 1 from pg_publication_tables
                    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
