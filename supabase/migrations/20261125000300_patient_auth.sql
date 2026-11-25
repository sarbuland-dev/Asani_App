-- Phase 4 (D-52): patient sign-up after the email code. The phone is required but NOT verified
-- (phone_verified = false), and ONE PHONE = ONE APP ACCOUNT (error 'phone-taken'). No auto-linking of walk-in
-- profiles by phone (linkPatientProfiles is gone); reception links them in person (phase 6).
--
-- Errors (message = code): unauthenticated, invalid-argument, invalid-phone, phone-taken.

-- '+923XXXXXXXXX' from 3001234567 / 03001234567 / 923001234567 / +92 300 1234567 (spaces, dashes allowed);
-- null when it is not a Pakistani mobile number. Same rules as PhoneUtils in asani_core.
create or replace function private.normalize_pk_mobile(p_phone text) returns text
language plpgsql immutable as $$
declare d text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
begin
  if d ~ '^92' and length(d) = 12 then d := substr(d, 3);
  elsif d ~ '^0' and length(d) = 11 then d := substr(d, 2);
  end if;
  if d ~ '^3[0-9]{9}$' then return '+92' || d; end if;
  return null;
end $$;

-- First login ("Tell us about you", F-01 / D-15): creates the account row and the Self profile in one transaction.
-- Calling it again for an account that already has a profile just returns it (safe on a retry).
create or replace function public.create_profile(p_name text, p_age integer, p_gender text, p_phone text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid   uuid := auth.uid();
  v_email text := auth.jwt() ->> 'email';
  v_name  text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_phone text := private.normalize_pk_mobile(p_phone);
  v_year  integer := extract(year from private.now_utc() at time zone 'Asia/Karachi')::integer;
  v_self  text := gen_random_uuid()::text;
  v_have  public.users;
begin
  if v_uid is null or not private.is_patient() then
    raise exception 'unauthenticated' using hint = 'Please log in again.';
  end if;
  select * into v_have from public.users where id = v_uid;
  if v_have.id is not null then
    return jsonb_build_object('selfPatientId', v_have.self_patient_id, 'created', false);
  end if;

  if char_length(v_name) < 2 or char_length(v_name) > 60 then
    raise exception 'invalid-argument' using hint = 'Name must be 2 to 60 characters.';
  end if;
  if p_age is null or p_age < 0 or p_age > 120 then
    raise exception 'invalid-argument' using hint = 'Age must be 0 to 120.';
  end if;
  if p_gender is null or p_gender not in ('male', 'female', 'other') then
    raise exception 'invalid-argument' using hint = 'Pick a gender.';
  end if;
  if v_phone is null then
    raise exception 'invalid-phone' using hint = 'Enter a Pakistani mobile number, e.g. 300 1234567.';
  end if;
  if exists (select 1 from public.users where phone = v_phone) then
    raise exception 'phone-taken' using hint = 'This number is already used by another Asani account.';
  end if;

  begin
    insert into public.users (id, email, phone, phone_verified, name, consent_accepted_at, consent_version, last_login_at)
    values (v_uid, coalesce(v_email, ''), v_phone, false, v_name, private.now_utc(), '2026-11-v1', private.now_utc());
  exception when unique_violation then
    -- Two sign-ups with the same number at the same moment: the second one loses.
    raise exception 'phone-taken' using hint = 'This number is already used by another Asani account.';
  end;

  insert into public.patients (id, phone, owner_uid, name, birth_year, gender, relation, created_by)
  values (v_self, v_phone, v_uid, v_name, v_year - p_age, p_gender, 'self', 'app');
  update public.users set self_patient_id = v_self where id = v_uid;

  return jsonb_build_object('selfPatientId', v_self, 'created', true);
end $$;

-- Account → Phone (S-4): change the contact phone. Still not verified; the account's own profiles get the new number.
create or replace function public.update_phone(p_phone text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid   uuid := auth.uid();
  v_phone text := private.normalize_pk_mobile(p_phone);
begin
  if v_uid is null or not private.is_patient() or not exists (select 1 from public.users where id = v_uid) then
    raise exception 'unauthenticated' using hint = 'Please log in again.';
  end if;
  if v_phone is null then
    raise exception 'invalid-phone' using hint = 'Enter a Pakistani mobile number, e.g. 300 1234567.';
  end if;
  if exists (select 1 from public.users where phone = v_phone and id <> v_uid) then
    raise exception 'phone-taken' using hint = 'This number is already used by another Asani account.';
  end if;
  begin
    update public.users set phone = v_phone, phone_verified = false where id = v_uid;
  exception when unique_violation then
    raise exception 'phone-taken' using hint = 'This number is already used by another Asani account.';
  end;
  update public.patients set phone = v_phone where owner_uid = v_uid and status = 'active';
  return jsonb_build_object('phone', v_phone);
end $$;

revoke execute on function private.normalize_pk_mobile(text) from public, anon;
revoke execute on function public.create_profile(text, integer, text, text), public.update_phone(text) from public, anon;
grant execute on function public.create_profile(text, integer, text, text), public.update_phone(text) to authenticated;
