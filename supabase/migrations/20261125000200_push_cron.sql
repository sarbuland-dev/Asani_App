-- Phase 3 (D-52): sending pushes (FCM through the send-push Edge Function) and scheduled jobs (pg_cron).
-- Ports functions/src/followups/reminders.ts and the schedules of autoCloseTokens / followUpReminders.
--
-- How a push travels:
--   1. a Postgres function adds a row to push_outbox (phase 2: private.notify_user);
--   2. the statement trigger below calls the send-push Edge Function through pg_net (after COMMIT; a rolled-back
--      transaction sends nothing);
--   3. send-push claims rows with claim_push_batch, sends them through FCM HTTP v1 and reports with finish_push;
--   4. a pg_cron job every minute calls send-push again while claimable rows remain (retries, max 5 tries).
-- The Edge Function URL and its shared secret live in Supabase Vault (names push_url, push_secret), never in git.

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

alter table public.push_outbox add column claimed_at timestamptz;

-- ================================================================ outbox API for send-push (service role only)

-- Claims up to p_limit unsent rows (not claimed in the last 2 minutes, fewer than 5 tries) and returns them with the
-- account's device tokens. SKIP LOCKED: two send-push runs never get the same row.
create or replace function public.claim_push_batch(p_limit integer default 50)
returns table (id bigint, user_id uuid, title text, body text, data jsonb, attempts integer, devices jsonb)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  return query
  with picked as (
    select o.id from public.push_outbox o
     where o.sent_at is null and o.attempts < 5
       and (o.claimed_at is null or o.claimed_at < now() - interval '2 minutes')
     order by o.id
     limit greatest(1, least(p_limit, 200))
     for update skip locked
  ), claimed as (
    update public.push_outbox o set claimed_at = now(), attempts = o.attempts + 1
      from picked where o.id = picked.id
    returning o.*
  )
  select c.id, c.user_id, c.title, c.body, c.data, c.attempts,
         coalesce((select jsonb_agg(jsonb_build_object('deviceId', d.device_id, 'token', d.fcm_token, 'platform', d.platform))
                     from public.devices d where d.user_id = c.user_id), '[]'::jsonb)
    from claimed c
   order by c.id;
end $$;

-- p_error null = done (sent, or nothing to send). Otherwise the row is released for a retry (until 5 tries).
-- p_dead_tokens: device tokens FCM reported as unregistered; they are deleted (replaces cleanupStaleDevices).
create or replace function public.finish_push(p_id bigint, p_error text default null, p_dead_tokens text[] default '{}')
returns void
language plpgsql security definer set search_path = '' as $$
declare v_user uuid;
begin
  update public.push_outbox o
     set sent_at    = case when p_error is null then now() else o.sent_at end,
         claimed_at = case when p_error is null then o.claimed_at else null end,
         last_error = p_error
   where o.id = p_id
  returning o.user_id into v_user;
  if v_user is not null and cardinality(p_dead_tokens) > 0 then
    delete from public.devices d where d.user_id = v_user and d.fcm_token = any (p_dead_tokens);
  end if;
end $$;

revoke execute on function public.claim_push_batch(integer), public.finish_push(bigint, text, text[]) from public, anon, authenticated;
grant execute on function public.claim_push_batch(integer), public.finish_push(bigint, text, text[]) to service_role;

-- ================================================================ wake send-push

-- Calls the Edge Function when Vault has its URL and secret; otherwise does nothing (pushes wait in the outbox).
create or replace function private.kick_push() returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_url    text;
  v_secret text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'push_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'push_secret';
  if v_url is null or v_secret is null then return; end if;
  perform net.http_post(
    url := v_url,
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
    timeout_milliseconds := 10000);
end $$;

create or replace function private.on_push_outbox_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform private.kick_push();
  return null;
end $$;

-- Once per statement, not per row: one booking may queue several pushes.
create trigger on_push_outbox_insert after insert on public.push_outbox
  for each statement execute function private.on_push_outbox_insert();

-- Retry: only calls send-push while claimable rows exist.
create or replace function private.retry_push() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.push_outbox o
              where o.sent_at is null and o.attempts < 5
                and (o.claimed_at is null or o.claimed_at < now() - interval '2 minutes')) then
    perform private.kick_push();
  end if;
end $$;

-- ================================================================ follow-up reminders (reminders.ts, PRD F-09)

-- Pure decision for one follow-up: 'tomorrow', 'today', 'missed' or null.
create or replace function private.decide_reminder(p_status text, p_due text, p_sent integer, p_today text, p_tomorrow text)
returns text
language sql immutable as $$
  select case
    when p_status <> 'pending' then null
    when p_due < p_today then 'missed'
    when p_due = p_today and coalesce(p_sent, 0) < 2 then 'today'
    when p_due = p_tomorrow and coalesce(p_sent, 0) = 0 then 'tomorrow'
  end $$;

-- Daily at 09:00 PKT. Each follow-up is updated in the same transaction as its notice, so a re-run sends nothing twice.
create or replace function private.follow_up_reminders() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_today    text := private.pkt_today();
  v_tomorrow text := to_char(private.pkt_today()::date + 1, 'YYYY-MM-DD');
  v_count    integer := 0;
  v_action   text;
  v_title    text;
  v_body     text;
  f          record;
begin
  for f in
    select fu.*, coalesce(p.name, 'Your family member') as patient_name,
           coalesce(d.name, 'the doctor') as doctor_name, coalesce(c.name, 'the clinic') as clinic_name
      from public.follow_ups fu
      left join public.patients p on p.id = fu.patient_id
      left join public.doctors d on d.id = fu.doctor_id
      left join public.clinics c on c.id = fu.clinic_id
     where fu.status = 'pending' and fu.due_date <= v_tomorrow
     for update of fu
  loop
    v_action := private.decide_reminder(f.status, f.due_date, f.reminders_sent, v_today, v_tomorrow);
    if v_action is null then continue; end if;
    v_count := v_count + 1;
    if v_action = 'missed' then
      update public.follow_ups set status = 'missed' where id = f.id;
      continue;
    end if;
    update public.follow_ups set reminders_sent = case when v_action = 'tomorrow' then 1 else 2 end where id = f.id;
    if v_action = 'tomorrow' then
      v_title := 'Follow-up visit tomorrow';
      v_body  := f.patient_name || ' · ' || f.doctor_name || ', ' || f.clinic_name || '. Tap to book.';
    else
      v_title := 'Follow-up visit today';
      v_body  := f.patient_name || ' · ' || f.doctor_name || '. Tap to book your token.';
    end if;
    -- Tapping opens booking pre-filled (PRD F-09). Not blocked by the queue alerts switch.
    perform private.notify_user(f.owner_uid, 'followUp', v_title, v_body,
                                '/book/' || f.clinic_id || '/' || f.doctor_id || '?patient=' || f.patient_id || '&date=' || f.due_date,
                                null, jsonb_build_object('followUpId', f.id), false);
  end loop;
  return v_count;
end $$;

-- ================================================================ clean-up (D-45: inbox kept 30 days)
create or replace function private.cleanup_old_rows() returns integer
language plpgsql security definer set search_path = '' as $$
declare v_a integer; v_b integer;
begin
  delete from public.notifications where expire_at < now();
  get diagnostics v_a = row_count;
  delete from public.push_outbox where created_at < now() - interval '7 days' and (sent_at is not null or attempts >= 5);
  get diagnostics v_b = row_count;
  return v_a + v_b;
end $$;

revoke execute on all functions in schema private from public, anon;
grant execute on function private.jwt_role(), private.jwt_clinic(), private.is_super_admin(), private.is_clinic(),
  private.is_clinic_of(text), private.staff_of(text), private.is_patient() to authenticated;

-- ================================================================ schedules (pg_cron runs in UTC; PKT = UTC+5)
select cron.schedule('asani-auto-close-tokens',   '0 22 * * *', $$select private.auto_close_tokens()$$);   -- 03:00 PKT (D-21)
select cron.schedule('asani-follow-up-reminders', '0 4 * * *',  $$select private.follow_up_reminders()$$); -- 09:00 PKT
select cron.schedule('asani-cleanup',             '0 23 * * *', $$select private.cleanup_old_rows()$$);    -- 04:00 PKT
select cron.schedule('asani-retry-push',          '* * * * *',  $$select private.retry_push()$$);          -- every minute
