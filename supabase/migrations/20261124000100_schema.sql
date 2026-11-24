-- Asani schema (D-52). Source of truth: DATABASE.md. Change both together.
-- Firestore collections → tables. Columns snake_case, IDs text (readable seed IDs),
-- account IDs uuid (auth.users.id), times timestamptz (UTC), queue day IDs 'yyyy-MM-dd' (Asia/Karachi).

create extension if not exists pgcrypto with schema extensions;

-- Internal helpers live in "private", which the API does not expose.
create schema if not exists private;

create or replace function private.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------- accounts
create table public.users (
  id                    uuid primary key references auth.users (id) on delete cascade,
  email                 text not null,
  phone                 text not null unique check (phone ~ '^\+923[0-9]{9}$'),   -- one phone = one app account (D-52)
  phone_verified        boolean not null default false,                          -- D-52: never verified for now
  name                  text not null check (char_length(name) between 2 and 60),
  role                  text not null default 'patient' check (role = 'patient'), -- staff roles live in app_metadata
  city                  text not null default 'Lahore',
  consent_accepted_at   timestamptz,
  consent_version       text,
  self_patient_id       text,
  notifications_seen_at timestamptz,                                              -- D-45
  queue_alerts_enabled  boolean not null default true,                            -- D-18
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  last_login_at         timestamptz
);

create table public.devices (
  user_id     uuid not null references public.users (id) on delete cascade,
  device_id   text not null,                       -- random UUID kept on the phone
  fcm_token   text not null,
  platform    text not null check (platform in ('android', 'ios')),
  app_version text,
  updated_at  timestamptz not null default now(),
  primary key (user_id, device_id)
);

create table public.notifications (                -- in-app list (D-45), written by the backend only
  id         text primary key default gen_random_uuid()::text,
  user_id    uuid not null references public.users (id) on delete cascade,
  type       text not null check (type in ('queue', 'cancel', 'skip', 'followUp')),
  title      text not null,
  body       text not null,
  route      text,
  token_id   text,
  created_at timestamptz not null default now(),
  expire_at  timestamptz not null default now() + interval '30 days'
);
create index notifications_user_created on public.notifications (user_id, created_at desc);
create index notifications_expire on public.notifications (expire_at);

-- ---------------------------------------------------------------- clinics
create table public.clinics (
  id                 text primary key default gen_random_uuid()::text,
  name               text not null,
  name_lower         text generated always as (lower(name)) stored,
  area               text not null default '',
  city               text not null,
  address            text not null default '',
  phone              text not null default '',
  lat                double precision,             -- D-31: required for new clinics (checked by the backend)
  lng                double precision,
  search_keywords    text[] not null default '{}',
  status             text not null default 'pilot'
                     check (status in ('pilot', 'active', 'grace', 'suspended', 'cancelled')),
  doctor_count       integer not null default 0,
  timezone           text not null default 'Asia/Karachi',
  print_format       text not null default 'thermal80' check (print_format in ('thermal80', 'a5', 'none')),
  next_doctor_letter integer not null default 0,   -- BW-7: letters never reused
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check ((lat is null) = (lng is null))
);
create index clinics_city_status_name on public.clinics (city, status, name_lower);

create table public.clinic_billing (               -- was clinics/{id}/private/billing
  clinic_id        text primary key references public.clinics (id) on delete cascade,
  plan             text not null default 'pilot' check (plan in ('pilot', 'basic', 'premium')),
  plan_after_pilot text check (plan_after_pilot in ('basic', 'premium')),
  monthly_fee      integer not null default 0,
  billing_day      integer not null default 1 check (billing_day between 1 and 28),
  pilot_ends_at    timestamptz,
  paid_until       timestamptz,
  owner_name       text,
  owner_phone      text,
  email            text,
  updated_at       timestamptz not null default now()
);

create table public.clinic_stats (                 -- was clinics/{id}/stats/{yyyy-MM}
  clinic_id text not null references public.clinics (id) on delete cascade,
  month     text not null check (month ~ '^\d{4}-\d{2}$'),
  app       integer not null default 0,
  walk_in   integer not null default 0,
  tokens    integer not null default 0,
  primary key (clinic_id, month)
);

-- ---------------------------------------------------------------- doctors
create table public.doctors (
  id                  text primary key default gen_random_uuid()::text,
  clinic_id           text not null references public.clinics (id) on delete cascade,
  name                text not null,
  speciality          text not null default 'other' check (speciality in (
                        'generalPhysician', 'child', 'heart', 'teeth', 'skin', 'womensHealth', 'eye', 'ent', 'bones',
                        'diabetes', 'stomach', 'chest', 'kidney', 'brain', 'mentalHealth', 'physio', 'other')),
  city                text not null default '',     -- copied from the clinic
  name_key            text not null default '',     -- D-32 weak match
  doctor_group_id     text,                         -- D-32, set only by the Super Admin
  speciality_flagged  boolean not null default false,
  has_pmdc            boolean not null default false,
  qualification       text,
  avg_consult_minutes integer not null default 10 check (avg_consult_minutes between 1 and 120),
  max_tokens_per_day  integer not null default 40 check (max_tokens_per_day between 1 and 500),
  booking_window_days integer not null default 7 check (booking_window_days between 0 and 60),
  token_prefix        text not null,
  schedule            jsonb not null default '{}', -- {"mon": {"start": "17:00", "end": "21:00"}, "sun": null, ...}
  on_leave_dates      text[] not null default '{}', -- 'yyyy-MM-dd'
  active              boolean not null default true,
  sort_order          integer not null default 0,
  added_by            text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (clinic_id, token_prefix)
);
create index doctors_clinic_active_sort on public.doctors (clinic_id, active, sort_order);
create index doctors_city_speciality_active on public.doctors (city, speciality, active);
create index doctors_group on public.doctors (doctor_group_id, active) where doctor_group_id is not null;
create index doctors_namekey_speciality on public.doctors (name_key, speciality);

create table public.doctor_private (               -- was doctors/{id}/private/admin (D-33): Super Admin reads only
  doctor_id   text primary key references public.doctors (id) on delete cascade,
  clinic_id   text not null references public.clinics (id) on delete cascade,
  pmdc_number text,
  updated_at  timestamptz not null default now()
);
create index doctor_private_pmdc on public.doctor_private (pmdc_number) where pmdc_number is not null;

create table public.doctor_link_suggestions (      -- D-32, Super Admin only
  id          text primary key,                    -- the two doctor IDs sorted, joined with '_'
  doctor_ids  text[] not null check (cardinality(doctor_ids) = 2),
  clinic_ids  text[] not null check (cardinality(clinic_ids) = 2),
  strength    text not null check (strength in ('strong', 'weak')),
  status      text not null default 'open' check (status in ('open', 'linked', 'notSame', 'unlinked')),
  created_at  timestamptz not null default now(),
  decided_at  timestamptz,
  decided_by  jsonb                                -- {uid, name}
);
create index doctor_link_suggestions_status on public.doctor_link_suggestions (status, created_at desc);

-- ---------------------------------------------------------------- patients
create table public.patients (
  id            text primary key default gen_random_uuid()::text,
  phone         text not null check (phone ~ '^\+923[0-9]{9}$'), -- account / contact phone
  owner_uid     uuid references public.users (id) on delete set null, -- null = walk-in not linked
  name          text not null check (char_length(name) between 2 and 60),
  name_lower    text generated always as (lower(name)) stored,
  birth_year    integer not null check (birth_year between 1880 and 2200),
  gender        text not null check (gender in ('male', 'female', 'other')),
  relation      text not null check (relation in
                ('self', 'mother', 'father', 'spouse', 'son', 'daughter', 'brother', 'sister', 'other')),
  patient_phone text check (patient_phone ~ '^\+923[0-9]{9}$'),
  status        text not null default 'active' check (status in ('active', 'deleted', 'merged')),
  merged_into   text references public.patients (id),
  person_id     text,
  created_by    text not null check (created_by in ('app', 'staff', 'script')),
  clinic_ids    text[] not null default '{}',     -- BW-6
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index patients_owner_status on public.patients (owner_uid, status, created_at);
create index patients_phone on public.patients (phone);
create index patients_clinic_ids on public.patients using gin (clinic_ids);
create unique index patients_one_self on public.patients (owner_uid) where relation = 'self' and status = 'active';

-- ---------------------------------------------------------------- queue
create table public.queue_days (                   -- was doctors/{id}/days/{yyyy-MM-dd}; numbers only, no personal data
  doctor_id         text not null references public.doctors (id) on delete cascade,
  date              text not null check (date ~ '^\d{4}-\d{2}-\d{2}$'),
  clinic_id         text not null references public.clinics (id) on delete cascade,
  session_status    text not null default 'notStarted'
                    check (session_status in ('notStarted', 'running', 'paused', 'ended')),
  current_token     integer not null default 0,
  last_token_number integer not null default 0,   -- only changed with the row locked
  active_numbers    integer[] not null default '{}',
  waiting_count     integer not null default 0,
  booked_count      integer not null default 0,
  undo              jsonb,
  updated_at        timestamptz not null default now(),
  primary key (doctor_id, date)
);
create index queue_days_clinic_date on public.queue_days (clinic_id, date);

create table public.tokens (
  id                 text primary key default gen_random_uuid()::text,
  clinic_id          text not null references public.clinics (id),
  doctor_id          text not null,
  date               text not null,
  number             integer not null check (number > 0),
  token_prefix       text not null,
  patient_id         text not null references public.patients (id),
  patient_snapshot   jsonb not null,               -- {name, birthYear, gender, relation, phone}
  booked_by_user_id  uuid references public.users (id) on delete set null,
  patient_owner_uid  uuid references public.users (id) on delete set null,
  source             text not null check (source in ('app', 'walkIn', 'followUp')),
  status             text not null default 'booked' check (status in
                     ('booked', 'arrived', 'called', 'completed', 'cancelled', 'skipped', 'onHold', 'noShow')),
  notified           jsonb not null default '{}',  -- {ahead3?, ahead2?, ahead1?, yourTurn?} → ISO times
  follow_up_id       text,
  created_at         timestamptz not null default now(),
  arrived_at         timestamptz,
  called_at          timestamptz,
  completed_at       timestamptz,
  cancelled_at       timestamptz,
  cancelled_by       text check (cancelled_by in ('patient', 'clinic')),
  cancel_reason      text,
  priority_at        timestamptz,                  -- D-24
  cancel_notified_at timestamptz,                  -- D-23 claim
  skip_notified_at   timestamptz,                  -- D-34 claim
  turn_repeat_used   boolean not null default false, -- D-35 / D-38
  history            jsonb not null default '[]',  -- [{action, by, at, note?}]
  wait_minutes       integer,
  auto_closed        boolean not null default false, -- D-21
  updated_at         timestamptz not null default now(),
  foreign key (doctor_id, date) references public.queue_days (doctor_id, date),
  unique (doctor_id, date, number)                 -- a duplicate token number can never be stored
);
create index tokens_booked_by on public.tokens (booked_by_user_id, created_at desc);
create index tokens_owner_source on public.tokens (patient_owner_uid, source, created_at desc);
create index tokens_patient on public.tokens (patient_id, created_at desc);
create index tokens_doctor_date_status on public.tokens (doctor_id, date, status, number);
create index tokens_clinic_date on public.tokens (clinic_id, date);
create index tokens_active on public.tokens (status) where status in ('booked', 'arrived', 'onHold', 'called');

create table public.follow_ups (
  id              text primary key default gen_random_uuid()::text,
  clinic_id       text not null references public.clinics (id),
  doctor_id       text not null references public.doctors (id),
  patient_id      text not null references public.patients (id),
  owner_uid       uuid references public.users (id) on delete set null,
  source_token_id text references public.tokens (id),
  due_date        text not null check (due_date ~ '^\d{4}-\d{2}-\d{2}$'),
  note            text,
  status          text not null default 'pending' check (status in ('pending', 'booked', 'done', 'missed')),
  booked_token_id text references public.tokens (id),
  reminders_sent  integer not null default 0 check (reminders_sent between 0 and 2),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index follow_ups_owner on public.follow_ups (owner_uid, status, due_date);
create index follow_ups_status_due on public.follow_ups (status, due_date);
create index follow_ups_clinic_due on public.follow_ups (clinic_id, due_date);
create index follow_ups_patient_doctor on public.follow_ups (patient_id, doctor_id, status);

-- ---------------------------------------------------------------- clinic web + super admin
create table public.clinic_accounts (              -- one login per clinic (D-18)
  id                  uuid primary key references auth.users (id) on delete cascade,
  email               text not null,
  clinic_id           text not null references public.clinics (id) on delete cascade,
  name                text not null default '',
  status              text not null default 'invited' check (status in ('invited', 'active', 'disabled')),
  pin_set             boolean not null default false, -- D-41
  invited_at          timestamptz,
  last_login_at       timestamptz,
  password_changed_at timestamptz,
  created_at          timestamptz not null default now()
);
create unique index clinic_accounts_one_per_clinic on public.clinic_accounts (clinic_id);

create table public.admin_users (
  id         uuid primary key references auth.users (id) on delete cascade,
  email      text not null,
  name       text not null default '',
  created_at timestamptz not null default now()
);

create table public.invoices (
  id               text primary key,               -- inv_{clinicId}_{yyyy-MM}
  clinic_id        text not null references public.clinics (id) on delete cascade,
  month            text not null check (month ~ '^\d{4}-\d{2}$'),
  amount           integer not null,
  due_date         text not null,
  status           text not null default 'unpaid' check (status in ('unpaid', 'overdue', 'paid', 'waived')),
  payment          jsonb,                          -- {amount, method, reference, date, recordedBy}
  waive_reason     text,
  reminder_sent_at timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index invoices_clinic_status on public.invoices (clinic_id, status);
create index invoices_clinic_month on public.invoices (clinic_id, month desc);

create table public.activity_logs (                -- written by the backend only (A-07, BW-10)
  id        text primary key default gen_random_uuid()::text,
  clinic_id text references public.clinics (id) on delete cascade, -- null = global
  actor     jsonb not null,                        -- {uid, name, role}
  action    text not null,
  target    text not null default '',
  at        timestamptz not null default now()
);
create index activity_logs_clinic_at on public.activity_logs (clinic_id, at desc);

create table public.billing_settings (             -- was settings/billing (one row)
  id                   text primary key default 'billing' check (id = 'billing'),
  prices               jsonb not null default '{"pilot": 0, "basic": 3000, "premium": 5000}',
  pilot_days           integer not null default 30,
  billing_day          integer not null default 1,
  due_days             integer not null default 7,
  grace_days           integer not null default 7,
  suspend_days         integer not null default 15,
  payment_instructions text not null default 'Payment details will be shared by Asani.',
  updated_at           timestamptz not null default now()
);

-- ---------------------------------------------------------------- backend only (no client access at all)
create table public.clinic_pins (                  -- D-41
  clinic_id      text primary key references public.clinics (id) on delete cascade,
  hash           text not null,                    -- bcrypt (pgcrypto crypt)
  failed         integer not null default 0,
  locked_until   timestamptz,
  unlocked_until timestamptz,
  updated_at     timestamptz not null default now()
);

create table public.rate_limits (
  id           text primary key,                   -- e.g. phoneLookup_{clinicId}
  clinic_id    text,
  window_start timestamptz not null default now(),
  count        integer not null default 0,
  updated_at   timestamptz not null default now()
);

create table public.push_outbox (                  -- pushes waiting for the send-push Edge Function (D-52)
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.users (id) on delete cascade,
  title      text not null,
  body       text not null,
  data       jsonb not null default '{}',
  created_at timestamptz not null default now(),
  sent_at    timestamptz,
  attempts   integer not null default 0,
  last_error text
);
create index push_outbox_unsent on public.push_outbox (created_at) where sent_at is null;

-- ---------------------------------------------------------------- updated_at
do $$
declare t text;
begin
  foreach t in array array['users', 'devices', 'clinics', 'clinic_billing', 'doctors', 'doctor_private', 'patients',
                           'queue_days', 'tokens', 'follow_ups', 'invoices', 'billing_settings', 'clinic_pins', 'rate_limits']
  loop
    execute format('create trigger set_updated_at before update on public.%I
                    for each row execute function private.set_updated_at()', t);
  end loop;
end $$;
