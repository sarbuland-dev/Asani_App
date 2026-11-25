-- Phase 6 (D-52), part 3: Super Admin (A-03…A-09), billing jobs, same-doctor links (D-32/D-33), reception's
-- "Link to app account" (D-52, S-2/S-3), account deletion (F-10) and the service-role helpers the
-- admin-clinic-login Edge Function uses to create clinics and their logins.
-- Ports admin/adminClinics.ts, admin/doctorLinks.ts, clinic/pin.ts (reset) and account/deleteAccount.ts.

-- ================================================================ clinic status, plan, pilot, PIN reset (A-03)

create or replace function public.admin_set_clinic_status(p_clinic_id text, p_status text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := private.admin_actor(); c public.clinics; v_reason text := nullif(left(btrim(coalesce(p_reason, '')), 80), '');
begin
  if p_status not in ('pilot', 'active', 'grace', 'suspended', 'cancelled') then
    raise exception 'invalid-argument' using hint = 'Unknown status.';
  end if;
  select * into c from public.clinics where id = p_clinic_id;
  if c.id is null then raise exception 'not-found' using hint = 'Clinic not found.'; end if;
  update public.clinics set status = p_status where id = c.id;
  perform private.log_activity(a, c.id,
    case p_status when 'suspended' then 'suspended clinic' when 'cancelled' then 'cancelled clinic' else 'reactivated clinic' end,
    c.name || coalesce(' · ' || v_reason, ''));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_change_plan(p_clinic_id text, p_plan text, p_monthly_fee integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := private.admin_actor();
begin
  if p_plan not in ('pilot', 'basic', 'premium') then raise exception 'invalid-argument' using hint = 'Unknown plan.'; end if;
  if p_monthly_fee is null or p_monthly_fee not between 0 and 1000000 then raise exception 'invalid-argument' using hint = 'Check the fee.'; end if;
  update public.clinic_billing set plan = p_plan, monthly_fee = p_monthly_fee where clinic_id = p_clinic_id;
  if not found then raise exception 'not-found' using hint = 'Clinic not found.'; end if;
  perform private.log_activity(a, p_clinic_id, 'changed plan', p_plan || ' · Rs ' || p_monthly_fee);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_extend_pilot(p_clinic_id text, p_days integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := private.admin_actor(); b public.clinic_billing; v_now timestamptz := private.now_utc();
begin
  if p_days is null or p_days not between 1 and 90 then raise exception 'invalid-argument' using hint = 'Days must be 1 to 90.'; end if;
  select * into b from public.clinic_billing where clinic_id = p_clinic_id for update;
  if b.clinic_id is null then raise exception 'not-found' using hint = 'Clinic not found.'; end if;
  update public.clinic_billing
     set plan = 'pilot', pilot_ends_at = greatest(coalesce(b.pilot_ends_at, v_now), v_now) + make_interval(days => p_days)
   where clinic_id = p_clinic_id;
  update public.clinics set status = 'pilot' where id = p_clinic_id;
  perform private.log_activity(a, p_clinic_id, 'extended pilot by ' || p_days || ' days', p_clinic_id);
  return jsonb_build_object('ok', true);
end $$;

-- Forgotten manager PIN (D-41): the clinic sets a new one.
create or replace function public.admin_reset_clinic_pin(p_clinic_id text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := private.admin_actor();
begin
  delete from public.clinic_pins where clinic_id = p_clinic_id;
  update public.clinic_accounts set pin_set = false where clinic_id = p_clinic_id;
  perform private.log_activity(a, p_clinic_id, 'reset manager PIN', coalesce((select name from public.clinics where id = p_clinic_id), p_clinic_id));
  return jsonb_build_object('ok', true);
end $$;

-- ================================================================ payments, invoices, settings (A-05, A-06, A-08)

create or replace function public.record_payment(
  p_invoice_id text, p_method text, p_amount integer, p_reference text default null, p_date date default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a     jsonb := private.admin_actor();
  inv   public.invoices;
  b     public.clinic_billing;
  v_now timestamptz := private.now_utc();
  v_day date := current_date;
begin
  if p_method not in ('bank', 'jazzCash', 'easypaisa', 'cash') then raise exception 'invalid-argument' using hint = 'Unknown method.'; end if;
  if p_amount is null or p_amount not between 1 and 10000000 then raise exception 'invalid-argument' using hint = 'Check the amount.'; end if;
  v_day := (v_now at time zone 'Asia/Karachi')::date;
  -- A payment date in the future or before 2020 counts as today.
  if p_date is not null and p_date <= v_day and p_date >= date '2020-01-01' then v_day := p_date; end if;

  -- Claim the invoice: a second click (or a second admin tab) must not record it again.
  select * into inv from public.invoices where id = p_invoice_id for update;
  if inv.id is null then raise exception 'not-found' using hint = 'Invoice not found.'; end if;
  if inv.status not in ('unpaid', 'overdue') then
    raise exception 'invoice-closed' using hint = 'This invoice is already ' || inv.status || '.';
  end if;
  update public.invoices
     set status = 'paid',
         payment = jsonb_build_object('amount', p_amount, 'method', p_method, 'reference', nullif(left(btrim(coalesce(p_reference, '')), 60), ''),
                                      'date', v_day, 'recordedBy', a ->> 'name')
   where id = inv.id;

  -- Paid until +1 month; a pilot clinic moves to its plan; Active unless another invoice is still overdue.
  select * into b from public.clinic_billing where clinic_id = inv.clinic_id for update;
  update public.clinic_billing
     set paid_until = greatest(coalesce(b.paid_until, v_now), v_now) + interval '1 month',
         plan = case when b.plan = 'pilot' then coalesce(b.plan_after_pilot, 'basic') else b.plan end
   where clinic_id = inv.clinic_id;
  if not exists (select 1 from public.invoices where clinic_id = inv.clinic_id and status = 'overdue') then
    update public.clinics set status = 'active' where id = inv.clinic_id;
  end if;
  perform private.log_activity(a, inv.clinic_id, 'recorded payment', inv.month || ' · Rs ' || p_amount || ' · ' || p_method);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.waive_invoice(p_invoice_id text, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := private.admin_actor(); inv public.invoices; v_reason text := left(btrim(coalesce(p_reason, '')), 80);
begin
  if v_reason = '' then raise exception 'invalid-argument' using hint = 'Give a reason.'; end if;
  select * into inv from public.invoices where id = p_invoice_id for update;
  if inv.id is null then raise exception 'not-found' using hint = 'Invoice not found.'; end if;
  if inv.status not in ('unpaid', 'overdue') then
    raise exception 'invoice-closed' using hint = 'This invoice is already ' || inv.status || '.';
  end if;
  update public.invoices set status = 'waived', waive_reason = v_reason where id = inv.id;
  perform private.log_activity(a, inv.clinic_id, 'waived invoice', inv.month || ' · ' || v_reason);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.give_extension(p_invoice_id text, p_due_date date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := private.admin_actor(); inv public.invoices;
begin
  if p_due_date is null then raise exception 'invalid-argument' using hint = 'Pick the new due date.'; end if;
  select * into inv from public.invoices where id = p_invoice_id for update;
  if inv.id is null then raise exception 'not-found' using hint = 'Invoice not found.'; end if;
  update public.invoices set status = 'unpaid', due_date = to_char(p_due_date, 'YYYY-MM-DD') where id = inv.id;
  update public.clinics set status = 'active' where id = inv.clinic_id and status in ('grace', 'suspended');
  perform private.log_activity(a, inv.clinic_id, 'gave payment extension', inv.month || ' · due ' || to_char(p_due_date, 'YYYY-MM-DD'));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.save_admin_settings(
  p_prices jsonb, p_pilot_days integer, p_billing_day integer, p_due_days integer, p_grace_days integer,
  p_suspend_days integer, p_payment_instructions text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := private.admin_actor();
begin
  if (p_prices ->> 'pilot') is null or (p_prices ->> 'basic') is null or (p_prices ->> 'premium') is null
     or (p_prices ->> 'pilot')::integer not between 0 and 1000000 or (p_prices ->> 'basic')::integer not between 0 and 1000000
     or (p_prices ->> 'premium')::integer not between 0 and 1000000
     or p_pilot_days not between 0 and 365 or p_billing_day not between 1 and 28 or p_due_days not between 0 and 60
     or p_grace_days not between 0 and 60 or p_suspend_days not between 1 and 90
     or coalesce(btrim(p_payment_instructions), '') = '' or char_length(p_payment_instructions) > 1000 then
    raise exception 'invalid-argument' using hint = 'Check the settings.';
  end if;
  if p_suspend_days <= p_grace_days then raise exception 'invalid-argument' using hint = 'Suspension must come after the reminder.'; end if;
  insert into public.billing_settings (id, prices, pilot_days, billing_day, due_days, grace_days, suspend_days, payment_instructions)
  values ('billing', jsonb_build_object('pilot', (p_prices ->> 'pilot')::integer, 'basic', (p_prices ->> 'basic')::integer,
                                        'premium', (p_prices ->> 'premium')::integer),
          p_pilot_days, p_billing_day, p_due_days, p_grace_days, p_suspend_days, btrim(p_payment_instructions))
  on conflict (id) do update set prices = excluded.prices, pilot_days = excluded.pilot_days, billing_day = excluded.billing_day,
     due_days = excluded.due_days, grace_days = excluded.grace_days, suspend_days = excluded.suspend_days,
     payment_instructions = excluded.payment_instructions;
  perform private.log_activity(a, null, 'updated admin settings', 'Plans & billing');
  return jsonb_build_object('ok', true);
end $$;

-- ================================================================ billing job (daily 06:00 PKT)

-- Idempotent: one invoice per clinic and month; statuses only move forward. Returns a log of what changed.
create or replace function private.billing_jobs() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  s        public.billing_settings;
  v_today  date := (private.now_utc() at time zone 'Asia/Karachi')::date;
  v_month  text := to_char((private.now_utc() at time zone 'Asia/Karachi')::date, 'YYYY-MM');
  v_system jsonb := jsonb_build_object('uid', 'system', 'role', 'superAdmin', 'name', 'System');
  v_log    jsonb := '[]';
  r        record;
  v_plan   text;
  v_late   integer;
begin
  select * into s from public.billing_settings where id = 'billing';
  if s.id is null then insert into public.billing_settings (id) values ('billing') returning * into s; end if;

  for r in select c.id, c.status, c.name, b.* from public.clinics c join public.clinic_billing b on b.clinic_id = c.id
            where c.status <> 'cancelled' loop
    v_plan := r.plan;
    -- Pilot over → the plan after pilot.
    if v_plan = 'pilot' and r.pilot_ends_at is not null and r.pilot_ends_at <= private.now_utc() then
      v_plan := coalesce(r.plan_after_pilot, 'basic');
      update public.clinic_billing set plan = v_plan where clinic_id = r.id;
      update public.clinics set status = 'active' where id = r.id and status = 'pilot';
      v_log := v_log || to_jsonb(r.id || ': pilot ended → ' || v_plan);
    end if;
    -- Billing day: one invoice per month (not during pilot).
    if v_plan <> 'pilot' and extract(day from v_today) >= r.billing_day then
      insert into public.invoices (id, clinic_id, month, amount, due_date, status)
      values ('inv_' || r.id || '_' || v_month, r.id, v_month,
              coalesce(r.monthly_fee, (s.prices ->> v_plan)::integer, 0),
              to_char(v_today + s.due_days, 'YYYY-MM-DD'), 'unpaid')
      on conflict (id) do nothing;
      if found then v_log := v_log || to_jsonb(r.id || ': invoice ' || v_month); end if;
    end if;
  end loop;

  -- Overdue → Grace; +grace days reminder; +suspend days Suspended.
  for r in select i.*, c.status as clinic_status, c.name as clinic_name
             from public.invoices i join public.clinics c on c.id = i.clinic_id
            where i.status in ('unpaid', 'overdue') and i.due_date::date <= v_today loop
    v_late := v_today - r.due_date::date;
    if r.status = 'unpaid' then update public.invoices set status = 'overdue' where id = r.id; end if;
    if v_late >= s.suspend_days and r.clinic_status not in ('suspended', 'cancelled') then
      update public.clinics set status = 'suspended' where id = r.clinic_id;
      perform private.log_activity(v_system, r.clinic_id, 'suspended clinic', r.clinic_name || ' · unpaid ' || v_late || ' days');
      v_log := v_log || to_jsonb(r.clinic_id || ': suspended');
    elsif r.clinic_status in ('active', 'pilot') then
      update public.clinics set status = 'grace' where id = r.clinic_id;
      perform private.log_activity(v_system, r.clinic_id, 'moved to grace', r.clinic_name || ' · invoice overdue');
      v_log := v_log || to_jsonb(r.clinic_id || ': grace');
    end if;
    if v_late >= s.grace_days and r.reminder_sent_at is null then
      -- Reminder email: needs a mail service; recorded here for now (REMAINING_WORK §10).
      update public.invoices set reminder_sent_at = private.now_utc() where id = r.id;
      v_log := v_log || to_jsonb(r.clinic_id || ': reminder due');
    end if;
  end loop;
  return v_log;
end $$;

create or replace function public.admin_run_billing_jobs() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform private.admin_actor();
  return jsonb_build_object('log', private.billing_jobs());
end $$;

select cron.schedule('asani-billing-jobs', '0 1 * * *', $$select private.billing_jobs()$$);   -- 06:00 PKT

-- ================================================================ same doctor (A-09, D-32, D-33)

create or replace function private.doctor_pair_label(p_ids text[]) returns text
language sql stable security definer set search_path = '' as $$
  select string_agg(coalesce(d.name, x) || ' (' || coalesce(c.name, d.clinic_id, '?') || ')', ' + ' order by o)
    from unnest(p_ids) with ordinality as u(x, o)
    left join public.doctors d on d.id = u.x
    left join public.clinics c on c.id = d.clinic_id $$;

-- Link: both records get one doctor_group_id (joining / merging existing groups). Decided once.
create or replace function public.admin_link_doctors(p_pair_id text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a jsonb := private.admin_actor();
  s public.doctor_link_suggestions;
  da public.doctors; db public.doctors;
  v_group text;
begin
  select * into s from public.doctor_link_suggestions where id = p_pair_id for update;
  if s.id is null then raise exception 'not-found' using hint = 'Suggestion not found.'; end if;
  if s.status <> 'open' then return jsonb_build_object('ok', true); end if;
  select * into da from public.doctors where id = s.doctor_ids[1] for update;
  select * into db from public.doctors where id = s.doctor_ids[2] for update;
  if da.id is null or db.id is null then raise exception 'not-found' using hint = 'Doctor not found.'; end if;
  v_group := coalesce(da.doctor_group_id, db.doctor_group_id, 'g_' || p_pair_id);
  if da.doctor_group_id is not null and db.doctor_group_id is not null and da.doctor_group_id <> db.doctor_group_id then
    update public.doctors set doctor_group_id = v_group where doctor_group_id = db.doctor_group_id;   -- merge b's group
  end if;
  update public.doctors set doctor_group_id = v_group where id in (da.id, db.id);
  update public.doctor_link_suggestions
     set status = 'linked', decided_at = private.now_utc(), decided_by = jsonb_build_object('uid', a ->> 'uid', 'name', a ->> 'name')
   where id = s.id;
  perform private.log_activity(a, null, 'linked doctors', private.doctor_pair_label(s.doctor_ids));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_mark_not_same(p_pair_id text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := private.admin_actor(); s public.doctor_link_suggestions;
begin
  select * into s from public.doctor_link_suggestions where id = p_pair_id for update;
  if s.id is null then raise exception 'not-found' using hint = 'Suggestion not found.'; end if;
  if s.status <> 'open' then return jsonb_build_object('ok', true); end if;
  update public.doctor_link_suggestions
     set status = 'notSame', decided_at = private.now_utc(), decided_by = jsonb_build_object('uid', a ->> 'uid', 'name', a ->> 'name')
   where id = s.id;
  perform private.log_activity(a, null, 'marked doctors not the same', private.doctor_pair_label(s.doctor_ids));
  return jsonb_build_object('ok', true);
end $$;

-- Unlink: this record leaves its group (a group of one is cleared too); its linked pairs become 'unlinked'
-- and are never suggested again (D-33).
create or replace function public.admin_unlink_doctor(p_doctor_id text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := private.admin_actor(); d public.doctors; v_rest integer;
begin
  select * into d from public.doctors where id = p_doctor_id for update;
  if d.id is null then raise exception 'not-found' using hint = 'Doctor not found.'; end if;
  if d.doctor_group_id is null then return jsonb_build_object('ok', true); end if;
  update public.doctors set doctor_group_id = null where id = d.id;
  select count(*) into v_rest from public.doctors where doctor_group_id = d.doctor_group_id;
  if v_rest = 1 then update public.doctors set doctor_group_id = null where doctor_group_id = d.doctor_group_id; end if;
  update public.doctor_link_suggestions
     set status = 'unlinked', decided_at = private.now_utc(), decided_by = jsonb_build_object('uid', a ->> 'uid', 'name', a ->> 'name')
   where d.id = any (doctor_ids) and status = 'linked';
  perform private.log_activity(a, null, 'unlinked doctor', private.doctor_pair_label(array[d.id]));
  return jsonb_build_object('ok', true);
end $$;

-- ================================================================ Link to app account (D-52, S-2, S-3)

-- Reception, with the patient in front of them: a walk-in profile of THIS clinic is linked to the Asani app account
-- whose (unverified) phone is p_account_phone.
--   p_target_patient_id = a profile of that account → "same person": the walk-in's visits and follow-ups move there,
--                         the walk-in becomes status 'merged' (merged_into).
--   p_target_patient_id = null → "New member": the walk-in profile joins the account's family.
-- Logged in the activity log. Errors: not-found, no-account, already-linked, invalid-argument.
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

-- ================================================================ delete my account (F-10, docs/04 §8)

-- 1. cancel waiting tokens  2. anonymise app-created profiles and the names in their tokens  3. drop follow-up links
-- 4. delete the login (auth.users; the account row, devices, notifications and pushes go with it).
-- Clinic visit records stay, without personal data.
create or replace function public.delete_my_account() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_cancelled integer;
begin
  if v_uid is null or not private.is_patient() then raise exception 'unauthenticated' using hint = 'Please log in again.'; end if;

  perform 1 from public.queue_days d
   where (d.doctor_id, d.date) in (select t.doctor_id, t.date from public.tokens t
                                    where t.booked_by_user_id = v_uid and t.status in ('booked', 'arrived', 'onHold'))
   order by d.doctor_id, d.date for update;
  update public.tokens set status = 'cancelled', cancelled_at = private.now_utc(), cancelled_by = 'patient'
   where booked_by_user_id = v_uid and status in ('booked', 'arrived', 'onHold');
  get diagnostics v_cancelled = row_count;

  update public.tokens
     set patient_snapshot = patient_snapshot || jsonb_build_object('name', 'Deleted user', 'phone', '')
   where booked_by_user_id = v_uid or patient_owner_uid = v_uid;
  update public.patients
     set name = 'Deleted user', patient_phone = null, phone = null, owner_uid = null, status = 'deleted'
   where owner_uid = v_uid and created_by = 'app';
  update public.patients set owner_uid = null where owner_uid = v_uid;   -- linked walk-ins stay with the clinic
  update public.follow_ups set owner_uid = null where owner_uid = v_uid;
  delete from auth.users where id = v_uid;
  return jsonb_build_object('ok', true, 'cancelled', v_cancelled);
end $$;

-- ================================================================ clinic logins (service role only, via admin-clinic-login)

-- A-04 step 1: validate everything and create the clinic + billing BEFORE the login exists.
create or replace function public.svc_create_clinic(p jsonb, p_actor uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a      jsonb;
  s      public.billing_settings;
  v_id   text;
  v_name text := btrim(coalesce(p ->> 'name', ''));
  v_lat  double precision := nullif(p ->> 'lat', '')::double precision;
  v_lng  double precision := nullif(p ->> 'lng', '')::double precision;
begin
  a := jsonb_build_object('uid', p_actor, 'role', 'superAdmin',
                          'name', coalesce((select nullif(name, '') from public.admin_users where id = p_actor), 'Super Admin'));
  if v_name = '' or coalesce(btrim(p ->> 'area'), '') = '' or coalesce(btrim(p ->> 'city'), '') = ''
     or coalesce(btrim(p ->> 'address'), '') = '' or coalesce(btrim(p ->> 'phone'), '') = ''
     or coalesce(btrim(p ->> 'ownerName'), '') = '' or coalesce(btrim(p ->> 'ownerPhone'), '') = '' then
    raise exception 'invalid-argument' using hint = 'Fill in every field.';
  end if;
  if coalesce(p ->> 'printFormat', '') not in ('thermal80', 'a5', 'none') then raise exception 'invalid-argument' using hint = 'Unknown print format.'; end if;
  if coalesce(p ->> 'planAfterPilot', '') not in ('basic', 'premium') then raise exception 'invalid-argument' using hint = 'Unknown plan.'; end if;
  if (p ->> 'pilotDays')::integer not between 0 and 365 or (p ->> 'monthlyFee')::integer not between 0 and 1000000
     or (p ->> 'billingDay')::integer not between 1 and 28 then
    raise exception 'invalid-argument' using hint = 'Check pilot days, fee and billing day.';
  end if;
  perform private.require_location(v_lat, v_lng);   -- D-31, BW-12
  select * into s from public.billing_settings where id = 'billing';

  insert into public.clinics (name, area, city, address, phone, lat, lng, search_keywords, status, print_format)
  values (left(v_name, 80), left(btrim(p ->> 'area'), 60), left(btrim(p ->> 'city'), 40), left(btrim(p ->> 'address'), 120),
          left(btrim(p ->> 'phone'), 20), v_lat, v_lng,
          (select coalesce(array_agg(distinct w), '{}') from regexp_split_to_table(lower(v_name || ' ' || (p ->> 'area')), '[^a-z0-9]+') w
            where length(w) >= 2),
          'pilot', p ->> 'printFormat')
  returning id into v_id;
  insert into public.clinic_billing (clinic_id, plan, plan_after_pilot, monthly_fee, billing_day, pilot_ends_at, owner_name, owner_phone, email)
  values (v_id, 'pilot', p ->> 'planAfterPilot', (p ->> 'monthlyFee')::integer, (p ->> 'billingDay')::integer,
          private.now_utc() + make_interval(days => (p ->> 'pilotDays')::integer),
          left(btrim(p ->> 'ownerName'), 60), left(btrim(p ->> 'ownerPhone'), 20), lower(btrim(p ->> 'email')));
  perform private.log_activity(a, v_id, 'created clinic', v_name);
  return jsonb_build_object('clinicId', v_id);
end $$;

-- A-04 step 3: the clinic's single login (D-18), after the Edge Function created and invited the Auth user.
create or replace function public.svc_attach_clinic_login(p_clinic_id text, p_uid uuid, p_email text, p_name text, p_actor uuid)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := jsonb_build_object('uid', p_actor, 'role', 'superAdmin',
                    'name', coalesce((select nullif(name, '') from public.admin_users where id = p_actor), 'Super Admin'));
begin
  insert into public.clinic_accounts (id, email, clinic_id, name, status, invited_at)
  values (p_uid, lower(p_email), p_clinic_id, coalesce(p_name, ''), 'invited', private.now_utc());
  perform private.log_activity(a, p_clinic_id, 'invited clinic login', lower(p_email));
  return jsonb_build_object('ok', true);
end $$;

-- A-04 rollback: the invite failed, so the half-made clinic is removed (no login, no tokens yet).
create or replace function public.svc_delete_new_clinic(p_clinic_id text) returns void
language sql security definer set search_path = '' as $$
  delete from public.activity_logs where clinic_id = p_clinic_id;
  delete from public.clinics c where c.id = p_clinic_id
     and not exists (select 1 from public.clinic_accounts x where x.clinic_id = c.id)
     and not exists (select 1 from public.tokens t where t.clinic_id = c.id) $$;

-- Resend invite / disable / enable (A-03): bookkeeping + log; the Auth side is done by the Edge Function.
create or replace function public.svc_clinic_login_event(p_clinic_id text, p_event text, p_actor uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a jsonb := jsonb_build_object('uid', p_actor, 'role', 'superAdmin',
               'name', coalesce((select nullif(name, '') from public.admin_users where id = p_actor), 'Super Admin'));
  acc public.clinic_accounts;
begin
  select * into acc from public.clinic_accounts where clinic_id = p_clinic_id for update;
  if acc.id is null then raise exception 'not-found' using hint = 'This clinic has no login yet.'; end if;
  if p_event = 'resend' then
    update public.clinic_accounts set invited_at = private.now_utc() where id = acc.id;
    perform private.log_activity(a, p_clinic_id, 'resent clinic login invite', acc.email);
  elsif p_event = 'disable' then
    update public.clinic_accounts set status = 'disabled' where id = acc.id;
    perform private.log_activity(a, p_clinic_id, 'disabled clinic login', acc.email);
  elsif p_event = 'enable' then
    update public.clinic_accounts set status = case when last_login_at is null then 'invited' else 'active' end where id = acc.id;
    perform private.log_activity(a, p_clinic_id, 'enabled clinic login', acc.email);
  else
    raise exception 'invalid-argument' using hint = 'Unknown event.';
  end if;
  return jsonb_build_object('uid', acc.id, 'email', acc.email);
end $$;

-- ================================================================ grants
revoke execute on all functions in schema private from public, anon;
grant execute on function private.jwt_role(), private.jwt_clinic(), private.is_super_admin(), private.is_clinic(),
  private.is_clinic_of(text), private.staff_of(text), private.is_patient() to authenticated;

revoke execute on function
  public.admin_set_clinic_status(text, text, text), public.admin_change_plan(text, text, integer),
  public.admin_extend_pilot(text, integer), public.admin_reset_clinic_pin(text),
  public.record_payment(text, text, integer, text, date), public.waive_invoice(text, text), public.give_extension(text, date),
  public.save_admin_settings(jsonb, integer, integer, integer, integer, integer, text), public.admin_run_billing_jobs(),
  public.admin_link_doctors(text), public.admin_mark_not_same(text), public.admin_unlink_doctor(text),
  public.link_walk_in_to_account(text, text, text), public.delete_my_account(),
  public.svc_create_clinic(jsonb, uuid), public.svc_attach_clinic_login(text, uuid, text, text, uuid),
  public.svc_delete_new_clinic(text), public.svc_clinic_login_event(text, text, uuid)
  from public, anon;
grant execute on function
  public.admin_set_clinic_status(text, text, text), public.admin_change_plan(text, text, integer),
  public.admin_extend_pilot(text, integer), public.admin_reset_clinic_pin(text),
  public.record_payment(text, text, integer, text, date), public.waive_invoice(text, text), public.give_extension(text, date),
  public.save_admin_settings(jsonb, integer, integer, integer, integer, integer, text), public.admin_run_billing_jobs(),
  public.admin_link_doctors(text), public.admin_mark_not_same(text), public.admin_unlink_doctor(text),
  public.link_walk_in_to_account(text, text, text), public.delete_my_account()
  to authenticated;
revoke execute on function public.svc_create_clinic(jsonb, uuid), public.svc_attach_clinic_login(text, uuid, text, text, uuid),
  public.svc_delete_new_clinic(text), public.svc_clinic_login_event(text, text, uuid) from authenticated;
grant execute on function public.svc_create_clinic(jsonb, uuid), public.svc_attach_clinic_login(text, uuid, text, text, uuid),
  public.svc_delete_new_clinic(text), public.svc_clinic_login_event(text, text, uuid) to service_role;
