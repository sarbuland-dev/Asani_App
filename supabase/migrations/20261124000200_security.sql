-- Row Level Security (D-52): same access as the old firestore.rules.
-- Clients mostly READ. Direct client writes allowed (as before): own user row (some columns), own devices,
-- own family profiles. Everything else goes through Postgres functions (security definer, phase 2+).
-- Roles come from app_metadata, which only the server can set; user_metadata is never trusted.

-- ---------------------------------------------------------------- role helpers
create or replace function private.jwt_role() returns text
language sql stable as $$ select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') $$;

create or replace function private.jwt_clinic() returns text
language sql stable as $$ select auth.jwt() -> 'app_metadata' ->> 'clinic_id' $$;

create or replace function private.is_super_admin() returns boolean
language sql stable as $$ select auth.uid() is not null and private.jwt_role() = 'superAdmin' $$;

create or replace function private.is_clinic() returns boolean
language sql stable as $$ select auth.uid() is not null and private.jwt_role() = 'clinic' and private.jwt_clinic() is not null $$;

create or replace function private.is_clinic_of(p_clinic text) returns boolean
language sql stable as $$ select private.is_clinic() and private.jwt_clinic() = p_clinic $$;

create or replace function private.staff_of(p_clinic text) returns boolean
language sql stable as $$ select private.is_super_admin() or private.is_clinic_of(p_clinic) $$;

-- A patient-app user: signed in and no staff role.
create or replace function private.is_patient() returns boolean
language sql stable as $$ select auth.uid() is not null and private.jwt_role() = '' $$;

grant usage on schema private to authenticated;
grant execute on all functions in schema private to authenticated;

-- ---------------------------------------------------------------- table privileges
-- Nothing for anonymous visitors. Signed-in users: read everything RLS lets them see, write only where granted below.
revoke all on all tables in schema public from anon, authenticated;
grant select on all tables in schema public to authenticated;
revoke select on public.clinic_pins, public.rate_limits, public.push_outbox from authenticated;

grant update (name, city, consent_accepted_at, consent_version, queue_alerts_enabled, notifications_seen_at, last_login_at)
  on public.users to authenticated;
grant insert, update, delete on public.devices to authenticated;
grant insert (name, birth_year, gender, relation, patient_phone) on public.patients to authenticated;
grant update (name, birth_year, gender, relation, patient_phone, status) on public.patients to authenticated;

-- New tables later must opt in explicitly.
alter default privileges in schema public revoke all on tables from anon, authenticated;

-- ---------------------------------------------------------------- RLS on every table
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- users
create policy users_read_own on public.users for select to authenticated using (id = auth.uid());
create policy users_update_own on public.users for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- devices
create policy devices_own on public.devices for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and private.is_patient());

-- notifications (D-45): owner reads, backend writes
create policy notifications_read_own on public.notifications for select to authenticated using (user_id = auth.uid());

-- patients: owner, or a clinic the patient booked/visited (BW-6)
create policy patients_read on public.patients for select to authenticated
  using (owner_uid = auth.uid() or (private.is_clinic() and private.jwt_clinic() = any (clinic_ids)));
create policy patients_insert_own on public.patients for insert to authenticated
  with check (owner_uid = auth.uid() and private.is_patient());
create policy patients_update_own on public.patients for update to authenticated
  using (owner_uid = auth.uid()) with check (owner_uid = auth.uid());

-- clinics, doctors, queue days: every signed-in user (queue days hold numbers only)
create policy clinics_read on public.clinics for select to authenticated using (true);
create policy doctors_read on public.doctors for select to authenticated using (true);
create policy queue_days_read on public.queue_days for select to authenticated using (true);

-- billing, stats: own clinic + Super Admin (BW-9)
create policy clinic_billing_read on public.clinic_billing for select to authenticated using (private.staff_of(clinic_id));
create policy clinic_stats_read on public.clinic_stats for select to authenticated using (private.staff_of(clinic_id));

-- PMDC and same-doctor suggestions: Super Admin only (D-32, D-33)
create policy doctor_private_read on public.doctor_private for select to authenticated using (private.is_super_admin());
create policy doctor_link_suggestions_read on public.doctor_link_suggestions for select to authenticated
  using (private.is_super_admin());

-- tokens: the booker, the profile owner (walk-ins, D-22), or the clinic / Super Admin
create policy tokens_read on public.tokens for select to authenticated
  using (booked_by_user_id = auth.uid() or patient_owner_uid = auth.uid() or private.staff_of(clinic_id));

-- follow-ups
create policy follow_ups_read on public.follow_ups for select to authenticated
  using (owner_uid = auth.uid() or private.staff_of(clinic_id));

-- clinic web
create policy clinic_accounts_read on public.clinic_accounts for select to authenticated
  using (private.is_super_admin() or (private.is_clinic() and id = auth.uid()));
create policy admin_users_read on public.admin_users for select to authenticated using (private.is_super_admin());
create policy invoices_read on public.invoices for select to authenticated using (private.staff_of(clinic_id));
create policy activity_logs_read on public.activity_logs for select to authenticated
  using (private.is_super_admin() or (clinic_id is not null and private.is_clinic_of(clinic_id)));
create policy billing_settings_read on public.billing_settings for select to authenticated
  using (private.is_super_admin() or private.is_clinic());

-- clinic_pins, rate_limits, push_outbox: RLS on and no policy → no client access (backend only).

-- ---------------------------------------------------------------- guards for direct client writes
-- Runs only for statements made by the client role itself (current_user = 'authenticated');
-- backend functions run as their owner and are not limited here.
-- Not security definer on purpose: it must see the caller's role in current_user.
create or replace function private.guard_patient_write() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_phone text;
  v_this_year integer := extract(year from now() at time zone 'Asia/Karachi')::integer;
begin
  if current_user <> 'authenticated' then
    return new;
  end if;

  if new.birth_year < v_this_year - 120 or new.birth_year > v_this_year then
    raise exception 'invalid-age' using errcode = 'check_violation';
  end if;

  if tg_op = 'INSERT' then
    select u.phone into v_phone from public.users u where u.id = auth.uid();
    if v_phone is null then
      raise exception 'no-profile' using errcode = 'check_violation', hint = 'Finish profile setup first.';
    end if;
    if new.relation = 'self' then
      raise exception 'self-profile' using errcode = 'check_violation', hint = 'The Self profile is created by profile setup.';
    end if;
    new.owner_uid   := auth.uid();
    new.phone       := v_phone;
    new.status      := 'active';
    new.created_by  := 'app';
    new.clinic_ids  := '{}';
    new.merged_into := null;
    new.person_id   := null;
    return new;
  end if;

  -- UPDATE
  if old.status <> 'active' then
    raise exception 'not-active' using errcode = 'check_violation';
  end if;
  if new.status not in ('active', 'deleted') then
    raise exception 'invalid-status' using errcode = 'check_violation';
  end if;
  if old.relation = 'self' and (new.status = 'deleted' or new.relation <> 'self') then
    raise exception 'self-profile' using errcode = 'check_violation', hint = 'The Self profile cannot be removed or changed to another relation.';
  end if;
  if old.relation <> 'self' and new.relation = 'self' then
    raise exception 'self-profile' using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger guard_patient_write before insert or update on public.patients
  for each row execute function private.guard_patient_write();

create or replace function private.guard_device_write() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user = 'authenticated' then
    new.updated_at := now();
  end if;
  return new;
end $$;

create trigger guard_device_write before insert or update on public.devices
  for each row execute function private.guard_device_write();

-- ---------------------------------------------------------------- Realtime (live queue and lists)
-- Realtime applies the same RLS, so a patient only receives their own token rows.
do $$
declare t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  foreach t in array array['users', 'notifications', 'patients', 'clinics', 'doctors', 'queue_days', 'tokens',
                           'follow_ups', 'clinic_accounts', 'clinic_billing', 'invoices', 'activity_logs',
                           'doctor_link_suggestions', 'billing_settings']
  loop
    execute format('alter publication supabase_realtime add table public.%I', t);
  end loop;
end $$;
