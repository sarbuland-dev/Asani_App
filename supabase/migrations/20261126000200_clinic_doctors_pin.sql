-- Phase 6 (D-52), part 2: the clinic's doctors (C-11, D-19, D-31…D-33), same-doctor suggestions, the manager PIN
-- (D-41), clinic settings (C-13), export log (C-14) and login bookkeeping (C-12, A-02).
-- Ports clinic/clinicData.ts (doctors + settings), clinic/pin.ts + pinRules.ts, doctors/linking.ts + suggest.ts.

-- ================================================================ pure helpers (linking.ts)

-- "Dr. Ayesha  Malik." → "ayesha malik" (weak match, D-32).
create or replace function private.doctor_name_key(p_name text) returns text
language sql immutable as $$
  select regexp_replace(btrim(regexp_replace(regexp_replace(lower(coalesce(p_name, '')), '[^a-z ]', ' ', 'g'), '\s+', ' ', 'g')),
                        '^(dr|doctor) ', '') $$;

-- "12345-p " → "12345-P"; null when it is not 3–7 digits with an optional "-" + 1–2 letters.
create or replace function private.normalize_pmdc(p_raw text) returns text
language sql immutable as $$
  select case when upper(regexp_replace(coalesce(p_raw, ''), '\s+', '', 'g')) ~ '^\d{3,7}(-[A-Z]{1,2})?$'
              then upper(regexp_replace(p_raw, '\s+', '', 'g')) end $$;

-- Weekly timings {mon: {start, end} | null, …}; raises invalid-argument with the day when a timing is wrong.
create or replace function private.clean_schedule(p jsonb) returns jsonb
language plpgsql immutable as $$
declare k text; s jsonb; out jsonb := '{}';
begin
  foreach k in array array['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'] loop
    s := coalesce(p, '{}') -> k;
    if s is null or jsonb_typeof(s) <> 'object' then
      out := out || jsonb_build_object(k, null);
      continue;
    end if;
    if coalesce(s ->> 'start', '') !~ '^([01]\d|2[0-3]):[0-5]\d$' or coalesce(s ->> 'end', '') !~ '^([01]\d|2[0-3]):[0-5]\d$'
       or private.hhmm_minutes(s ->> 'end') <= private.hhmm_minutes(s ->> 'start') then
      raise exception 'invalid-argument' using hint = 'Check the ' || k || ' timing: end must be after start.';
    end if;
    out := out || jsonb_build_object(k, jsonb_build_object('start', s ->> 'start', 'end', s ->> 'end'));
  end loop;
  return out;
end $$;

-- ================================================================ suggestions (suggest.ts)

-- After a doctor is saved: possible matches at OTHER clinics in the SAME city → doctor_link_suggestions.
-- strong = same PMDC number, weak = same name key + speciality. Never links, never fails the save (D-32, D-33).
create or replace function private.build_suggestions(p_doctor_id text) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  d       public.doctors;
  v_pmdc  text;
  o       record;
  v_pair  text;
  v_cur   public.doctor_link_suggestions;
  v_n     integer := 0;
begin
  select * into d from public.doctors where id = p_doctor_id;
  if d.id is null or not d.active or coalesce(d.city, '') = '' then return 0; end if;
  select pmdc_number into v_pmdc from public.doctor_private where doctor_id = d.id;

  for o in
    select x.id, x.clinic_id,
           bool_or(v_pmdc is not null and p.pmdc_number = v_pmdc) as strong
      from public.doctors x
      left join public.doctor_private p on p.doctor_id = x.id
     where x.id <> d.id and x.clinic_id <> d.clinic_id and x.city = d.city
       and ((v_pmdc is not null and p.pmdc_number = v_pmdc)
            or (d.name_key <> '' and x.name_key = d.name_key and x.speciality = d.speciality))
     group by x.id, x.clinic_id
  loop
    v_pair := least(d.id, o.id) || '_' || greatest(d.id, o.id);
    select * into v_cur from public.doctor_link_suggestions where id = v_pair for update;
    if v_cur.id is null then
      insert into public.doctor_link_suggestions (id, doctor_ids, clinic_ids, strength, status)
      values (v_pair, array[least(d.id, o.id), greatest(d.id, o.id)],
              case when d.id < o.id then array[d.clinic_id, o.clinic_id] else array[o.clinic_id, d.clinic_id] end,
              case when o.strong then 'strong' else 'weak' end, 'open');
      v_n := v_n + 1;
    elsif v_cur.status = 'open' and v_cur.strength = 'weak' and o.strong then
      update public.doctor_link_suggestions set strength = 'strong' where id = v_pair;
      v_n := v_n + 1;
    end if;  -- linked / notSame / unlinked are never touched (D-33)
  end loop;
  return v_n;
exception when others then
  raise warning 'build_suggestions(%) failed: %', p_doctor_id, sqlerrm;
  return 0;
end $$;

-- ================================================================ manager PIN (D-41)

-- Passes when no PIN is set yet, or within 15 minutes of a correct PIN.
create or replace function private.require_pin_unlocked(p_clinic text) returns void
language plpgsql stable security definer set search_path = '' as $$
declare v public.clinic_pins;
begin
  select * into v from public.clinic_pins where clinic_id = p_clinic;
  if v.clinic_id is null or coalesce(v.unlocked_until, '-infinity') > private.now_utc() then return; end if;
  raise exception 'pin-required' using hint = 'Enter the manager PIN first.';
end $$;

-- Checks a PIN and RECORDS the try. Returns {ok:true, unlockedUntil} or {ok:false, code: pin-wrong | pin-locked, …}.
-- It returns instead of raising, so a wrong try is saved (an exception would roll the counter back).
create or replace function private.check_pin(p_clinic text, p_pin text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v     public.clinic_pins;
  v_now timestamptz := private.now_utc();
  v_ok  boolean;
  v_failed integer;
begin
  select * into v from public.clinic_pins where clinic_id = p_clinic for update;
  if v.clinic_id is null then return jsonb_build_object('ok', true, 'unlockedUntil', null); end if;
  if v.locked_until is not null and v.locked_until > v_now then
    return jsonb_build_object('ok', false, 'code', 'pin-locked', 'lockedUntil', v.locked_until,
                              'message', 'Too many wrong PINs. Try again in 15 minutes.');
  end if;
  v_ok := coalesce(p_pin, '') ~ '^\d{4}$' and extensions.crypt(p_pin, v.hash) = v.hash;
  if v_ok then
    update public.clinic_pins set failed = 0, locked_until = null, unlocked_until = v_now + interval '15 minutes'
     where clinic_id = p_clinic;
    return jsonb_build_object('ok', true, 'unlockedUntil', v_now + interval '15 minutes');
  end if;
  v_failed := v.failed + 1;
  if v_failed >= 5 then
    update public.clinic_pins set failed = 0, locked_until = v_now + interval '15 minutes' where clinic_id = p_clinic;
    return jsonb_build_object('ok', false, 'code', 'pin-locked', 'lockedUntil', v_now + interval '15 minutes',
                              'message', 'Too many wrong PINs. Try again in 15 minutes.');
  end if;
  update public.clinic_pins set failed = v_failed where clinic_id = p_clinic;
  return jsonb_build_object('ok', false, 'code', 'pin-wrong', 'triesLeft', 5 - v_failed,
                            'message', 'Wrong PIN. ' || (5 - v_failed) || ' tries left.');
end $$;

-- Set or change the PIN (changing needs the current one). Same result shape as check_pin.
create or replace function public.clinic_set_pin(p_pin text, p_current_pin text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a      jsonb := private.clinic_actor();
  v_c    text := a ->> 'clinicId';
  v_has  boolean;
  v_chk  jsonb;
begin
  if coalesce(p_pin, '') !~ '^\d{4}$' then raise exception 'invalid-argument' using hint = 'The PIN must be 4 digits.'; end if;
  v_has := exists (select 1 from public.clinic_pins where clinic_id = v_c);
  if v_has then
    v_chk := private.check_pin(v_c, coalesce(p_current_pin, ''));
    if not (v_chk ->> 'ok')::boolean then return v_chk; end if;
  end if;
  insert into public.clinic_pins (clinic_id, hash, failed, locked_until, unlocked_until)
  values (v_c, extensions.crypt(p_pin, extensions.gen_salt('bf', 8)), 0, null, private.now_utc() + interval '15 minutes')
  on conflict (clinic_id) do update
     set hash = excluded.hash, failed = 0, locked_until = null, unlocked_until = excluded.unlocked_until;
  update public.clinic_accounts set pin_set = true where clinic_id = v_c;
  perform private.log_activity(a, v_c, case when v_has then 'changed manager PIN' else 'set manager PIN' end, a ->> 'name');
  return jsonb_build_object('ok', true, 'unlockedUntil', private.now_utc() + interval '15 minutes');
end $$;

-- Unlock the protected pages / actions for 15 minutes.
create or replace function public.clinic_verify_pin(p_pin text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := private.clinic_actor();
begin
  return private.check_pin(a ->> 'clinicId', p_pin);
end $$;

-- ================================================================ doctors (C-11, D-19, D-31…D-33)

-- New doctor (p_doctor_id null; needs the PIN, D-41) or edit. p_pmdc null = keep the saved number.
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

-- Deactivating needs the PIN (D-41); reactivating does not.
create or replace function public.set_doctor_active(p_doctor_id text, p_active boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := private.clinic_actor(); d public.doctors;
begin
  select * into d from public.doctors where id = p_doctor_id;
  if d.id is null or d.clinic_id <> a ->> 'clinicId' then raise exception 'not-found' using hint = 'Doctor not found.'; end if;
  if not p_active then perform private.require_pin_unlocked(d.clinic_id); end if;
  update public.doctors set active = p_active where id = d.id;
  update public.clinics set doctor_count = (select count(*) from public.doctors where clinic_id = d.clinic_id and active)
   where id = d.clinic_id;
  perform private.log_activity(a, d.clinic_id, case when p_active then 'reactivated doctor' else 'deactivated doctor' end, d.name);
  return jsonb_build_object('ok', true);
end $$;

-- Add / remove a leave date (no PIN). Returns how many active tokens that date has.
create or replace function public.set_doctor_leave(p_doctor_id text, p_date text, p_add boolean default true) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := private.clinic_actor(); d public.doctors;
begin
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

-- Bulk-cancel a doctor's tokens on a leave day, with a reason (C-11). Each patient gets the D-23 push (trigger).
create or replace function public.cancel_doctor_tokens(p_doctor_id text, p_date text, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a jsonb := private.clinic_actor();
  d public.doctors;
  v_reason text := left(btrim(coalesce(p_reason, '')), 80);
  v_n integer;
begin
  select * into d from public.doctors where id = p_doctor_id;
  if d.id is null or d.clinic_id <> a ->> 'clinicId' then raise exception 'not-found' using hint = 'Doctor not found.'; end if;
  if p_date is null or p_date !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'invalid-argument' using hint = 'date must be yyyy-MM-dd.'; end if;
  if v_reason = '' then raise exception 'invalid-argument' using hint = 'Pick a reason.'; end if;
  perform 1 from public.queue_days where doctor_id = d.id and date = p_date for update;
  update public.tokens
     set status = 'cancelled', cancelled_at = private.now_utc(), cancelled_by = 'clinic', cancel_reason = v_reason,
         history = history || jsonb_build_array(private.history_entry('Cancelled', a, v_reason))
   where doctor_id = d.id and date = p_date and status in ('booked', 'arrived', 'called', 'onHold');
  get diagnostics v_n = row_count;
  perform private.log_activity(a, d.clinic_id, 'cancelled ' || v_n || ' tokens', d.name || ' · ' || p_date);
  return jsonb_build_object('cancelled', v_n);
end $$;

-- ================================================================ settings, export, login (C-12…C-14, A-02)

create or replace function private.require_location(p_lat double precision, p_lng double precision) returns void
language plpgsql immutable as $$
begin
  if p_lat is null or p_lng is null then raise exception 'invalid-argument' using hint = 'Add the clinic location on the map.'; end if;
  if p_lat not between 23.5 and 37.5 or p_lng not between 60.5 and 77.5 then
    raise exception 'invalid-argument' using hint = 'The clinic location must be in Pakistan. Check the numbers.';
  end if;
end $$;

create or replace function public.update_clinic_settings(
  p_address text, p_area text, p_phone text, p_print_format text, p_lat double precision, p_lng double precision
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := private.clinic_actor();
begin
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

-- C-14: Export is a manager action (PIN, D-41); the file is made in the browser.
create or replace function public.log_export(p_range text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := private.clinic_actor();
begin
  perform private.require_pin_unlocked(a ->> 'clinicId');
  perform private.log_activity(a, a ->> 'clinicId', 'exported visits', left(coalesce(p_range, ''), 60));
  return jsonb_build_object('ok', true);
end $$;

-- Right after login: invite accepted + last login (A-02).
create or replace function public.clinic_login_touch() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_clinic() then return jsonb_build_object('ok', true); end if;
  update public.clinic_accounts
     set last_login_at = private.now_utc(), status = case when status = 'invited' then 'active' else status end
   where id = auth.uid();
  return jsonb_build_object('ok', true);
end $$;

-- C-12: after the web changed the password (and signed out the other sessions itself: signOut(scope: others)).
create or replace function public.clinic_password_changed() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := private.clinic_actor();
begin
  update public.clinic_accounts set password_changed_at = private.now_utc() where id = auth.uid();
  perform private.log_activity(a, a ->> 'clinicId', 'changed clinic login password', coalesce(auth.jwt() ->> 'email', ''));
  return jsonb_build_object('ok', true);
end $$;

-- ================================================================ grants
revoke execute on all functions in schema private from public, anon;
grant execute on function private.jwt_role(), private.jwt_clinic(), private.is_super_admin(), private.is_clinic(),
  private.is_clinic_of(text), private.staff_of(text), private.is_patient() to authenticated;
revoke execute on function
  public.clinic_set_pin(text, text), public.clinic_verify_pin(text),
  public.save_doctor(text, text, text, text, text, integer, integer, integer, jsonb),
  public.set_doctor_active(text, boolean), public.set_doctor_leave(text, text, boolean),
  public.cancel_doctor_tokens(text, text, text),
  public.update_clinic_settings(text, text, text, text, double precision, double precision),
  public.log_export(text), public.clinic_login_touch(), public.clinic_password_changed()
  from public, anon;
grant execute on function
  public.clinic_set_pin(text, text), public.clinic_verify_pin(text),
  public.save_doctor(text, text, text, text, text, integer, integer, integer, jsonb),
  public.set_doctor_active(text, boolean), public.set_doctor_leave(text, text, boolean),
  public.cancel_doctor_tokens(text, text, text),
  public.update_clinic_settings(text, text, text, text, double precision, double precision),
  public.log_export(text), public.clinic_login_touch(), public.clinic_password_changed()
  to authenticated;
