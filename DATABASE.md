# DATABASE — Asani (Supabase Postgres)

Source of truth for all tables (D-52; the Firestore version is in git history before 2026-11-26).
**Any schema change: a NEW migration in `supabase/migrations/` + this file + a pgTAP test, in the same change.**
Never edit a migration that was already pushed.

- Database: Supabase Postgres 17, project `asani-dev` (Tokyo, `ap-northeast-1`); prod later in Mumbai.
- Time zone for business dates: **Asia/Karachi** (UTC+5, no DST). Queue day IDs and `date` columns are `yyyy-MM-dd`
  text in PKT. Timestamps are `timestamptz` (UTC).
- Columns `snake_case`; enum values `camelCase` text with `check` constraints. IDs are `text`
  (`gen_random_uuid()::text`, readable in the seed: `c_alshifa`, `d_ayesha`); account IDs are `uuid` (`auth.users.id`).
- `updated_at` is set by a trigger on every update.
- Migrations: `20261124000100_schema.sql` (tables), `…000200_security.sql` (RLS, grants, Realtime),
  `20261125000100_booking_queue.sql`, `…000200_push_cron.sql`, `…000300_patient_auth.sql`,
  `20261126000100_clinic_queue.sql`, `…000200_clinic_doctors_pin.sql`, `…000300_admin_accounts.sql`.

---

## 1. Tables

| Table | Written by | Who can read (RLS) |
|---|---|---|
| `users` | `create_profile` / `update_phone`; the app updates its own name, city, alerts, seen-at | own row |
| `devices` | the app (own) | own |
| `notifications` | backend (`notify_user`) | own |
| `patients` | the app (own family: insert / edit / soft-delete), backend | owner; a clinic whose id is in `clinic_ids` |
| `clinics` | backend / Super Admin | every signed-in user |
| `clinic_billing` | backend / Super Admin | own clinic, Super Admin |
| `clinic_stats` | backend | own clinic, Super Admin |
| `doctors` | backend (`save_doctor` …) | every signed-in user |
| `doctor_private` | backend (`save_doctor`) | Super Admin only (D-33) |
| `doctor_link_suggestions` | backend | Super Admin only (D-32) |
| `queue_days` | backend / triggers | every signed-in user (numbers only) |
| `tokens` | backend only | booker, profile owner (walk-ins, D-22), own clinic, Super Admin |
| `follow_ups` | backend only | owner, own clinic, Super Admin |
| `clinic_accounts` | backend / Edge Function | own login, Super Admin |
| `admin_users` | dev script | Super Admin |
| `invoices`, `activity_logs` | backend only | own clinic, Super Admin (global logs: Super Admin) |
| `billing_settings` | `save_admin_settings` | clinic logins, Super Admin |
| `clinic_pins`, `rate_limits`, `push_outbox` | backend only | nobody (no policy, no grant) |

`anon` has no access at all. `authenticated` has `select` on every table except the three backend-only ones; direct
writes are granted only on `users` (name, city, consent, queue alerts, notifications seen-at, last login), `devices`,
and `patients` (insert: name, birth year, gender, relation, patient phone; update: those + status).

Roles come from **`app_metadata`** (`role: clinic` + `clinic_id`, or `role: superAdmin`), set only on the server
(`admin-clinic-login` Edge Function, `tools/db-test/create-login.js` for dev). `user_metadata` is never trusted.
Helpers in schema `private`: `jwt_role()`, `jwt_clinic()`, `is_super_admin()`, `is_clinic()`, `is_clinic_of(id)`,
`staff_of(id)`, `is_patient()`.

---

## 2. Accounts

### `users` (patient app accounts)
| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK → `auth.users` | cascade delete |
| `email` | text | the login email (D-52) |
| `phone` | text **unique** | `+923XXXXXXXXX`; one phone = one app account (`phone-taken`) |
| `phone_verified` | bool | always `false` for now (D-52) |
| `name` | text | 2–60 chars |
| `role` | text | always `patient` (staff roles live in `app_metadata`) |
| `city` | text | default `Lahore` |
| `consent_accepted_at`, `consent_version` | | set by `create_profile` (`2026-11-v1`) |
| `self_patient_id` | text | the Self profile |
| `notifications_seen_at` | timestamptz | D-45: newer notifications are unread |
| `queue_alerts_enabled` | bool | D-18, account-wide; default true |
| `created_at`, `updated_at`, `last_login_at` | timestamptz | |

### `devices`
PK (`user_id`, `device_id`): `fcm_token`, `platform` (`android`/`ios`), `app_version`, `updated_at`. The phone saves its
FCM token after sign-in; `send-push` deletes tokens FCM reports as dead.

### `notifications` (D-45)
`id`, `user_id`, `type` (`queue`/`cancel`/`skip`/`followUp`), `title`, `body`, `route` (`/token/{id}` or a booking route),
`token_id`, `created_at`, `expire_at` (+30 days; deleted nightly by `asani-cleanup`). Written for every push, even when
queue alerts are off or the phone has no device.

### `clinic_accounts` (one login per clinic, D-18)
`id` (uuid → `auth.users`), `email`, `clinic_id` (**unique**), `name`, `status` (`invited`/`active`/`disabled`),
`pin_set` (D-41), `invited_at`, `last_login_at`, `password_changed_at`, `created_at`.

### `admin_users`
`id`, `email`, `name` (shown in logs and history).

---

## 3. `patients`

One row per person who sees a doctor. Walk-ins have no account (`owner_uid` null).

| Column | Notes |
|---|---|
| `phone` | account / contact phone, `+923…`; null only for `deleted` |
| `owner_uid` | the app account, or null (walk-in not linked) |
| `name`, `name_lower` (generated) | 2–60 chars |
| `birth_year` | nullable (walk-in age unknown) |
| `gender` | `male`/`female`/`other` |
| `relation` | `self`, `mother`, `father`, `spouse`, `son`, `daughter`, `brother`, `sister`, `other` |
| `patient_phone` | optional own number |
| `status` | `active` / `deleted` (soft delete) / `merged` (linked into another profile) |
| `merged_into` | the profile it was merged into (Link to app account, S-2) |
| `created_by` | `app` / `staff` / `script` |
| `clinic_ids` | clinics the patient booked or visited (BW-6; GIN index) |

- At most one active `self` per owner (unique partial index). The app cannot create or remove Self, change a
  profile to Self, or touch `owner_uid` / `phone` / `clinic_ids` (trigger `guard_patient_write` + column grants).
- **No auto-linking by phone (D-52):** a new walk-in is never attached to an app account; reception links it with
  `link_walk_in_to_account`.

---

## 4. Clinics and doctors

### `clinics`
`name`, `name_lower` (generated), `area`, `city`, `address`, `phone`, `lat`/`lng` (**required** for new clinics and
settings, inside Pakistan; D-31), `search_keywords`, `status` (`pilot`/`active`/`grace`/`suspended`/`cancelled`),
`doctor_count`, `timezone`, `print_format` (`thermal80`/`a5`/`none`), `next_doctor_letter` (BW-7, never reused).
Patients see `pilot`/`active`/`grace`; `suspended` only under Recent. Suspended / cancelled clinics have a read-only queue.

### `clinic_billing` (Super Admin + own clinic)
`plan` (`pilot`/`basic`/`premium`), `plan_after_pilot`, `monthly_fee`, `billing_day` (1–28), `pilot_ends_at`,
`paid_until`, `owner_name`, `owner_phone`, `email`.

### `clinic_stats`
PK (`clinic_id`, `month` `yyyy-MM`): `app`, `walk_in`, `tokens` counters.

### `doctors`
`clinic_id`, `name`, `speciality` (one key of the fixed list, D-31), `city` (copied from the clinic), `name_key` (weak
match), `doctor_group_id` (D-32, set only by the Super Admin), `speciality_flagged`, `has_pmdc` (the clinic only sees
"on file"), `qualification`, `avg_consult_minutes`, `max_tokens_per_day`, `booking_window_days`, `token_prefix`
(unique per clinic), `schedule` jsonb (`{mon: {start, end} | null, …}`), `on_leave_dates` (text[]), `active`,
`sort_order`, `added_by`.

### `doctor_private` (D-33)
`doctor_id` PK, `clinic_id`, `pmdc_number` (normalised, e.g. `12345-P`). Super Admin reads only; written by `save_doctor`.

### `doctor_link_suggestions` (D-32)
`id` = the two doctor ids sorted, joined with `_`; `doctor_ids`, `clinic_ids`, `strength` (`strong` = same PMDC,
`weak` = same name key + speciality), `status` (`open`/`linked`/`notSame`/`unlinked`), `decided_at`, `decided_by`.
Only for doctors at different clinics in the same city; decided pairs are never suggested again.

---

## 5. Queue

### `queue_days` (PK `doctor_id` + `date`)
`clinic_id`, `session_status` (`notStarted`/`running`/`paused`/`ended`), `current_token`, `last_token_number` (only
changed with the row locked), `active_numbers` int[] (booked / arrived / onHold, sorted; **kept by a trigger**),
`waiting_count`, `booked_count`, `undo` jsonb (`{at, completedId, calledId, calledPrevStatus, prevCurrent}`, 30 s).

### `tokens`
| Column | Notes |
|---|---|
| `clinic_id`, `doctor_id`, `date`, `number` | **unique (doctor_id, date, number)**; FK to its queue day |
| `token_prefix` | the doctor's letter at booking ("A-11", D-13) |
| `patient_id`, `patient_snapshot` jsonb | `{name, birthYear, gender, relation, phone}` at booking |
| `booked_by_user_id` | app booker; null for walk-ins |
| `patient_owner_uid` | the profile's account (walk-ins on app profiles, D-22) |
| `source` | `app` / `walkIn` / `followUp` |
| `status` | `booked`, `arrived`, `called`, `completed`, `cancelled`, `skipped`, `onHold`, `noShow` |
| `notified` jsonb | `{ahead3, ahead2, ahead1, yourTurn}` → time sent (the 4 queue pushes, never twice) |
| `follow_up_id` | |
| `arrived_at`, `called_at`, `completed_at`, `cancelled_at` | |
| `cancelled_by`, `cancel_reason` | `patient` / `clinic` (D-23) |
| `priority_at` | D-24: a Skipped patient who checked in again is called next |
| `cancel_notified_at`, `skip_notified_at` | claims for the D-23 / D-34 pushes (sent once) |
| `turn_repeat_used` | D-35 / D-38: one extra "Your turn now" at most |
| `history` jsonb | `[{action, by, at, note?}]` for every clinic action |
| `wait_minutes`, `auto_closed` | D-21 |

Active = `booked`, `arrived`, `called`, `onHold`. "Ahead" = booked / arrived / onHold with a lower number.

### `follow_ups`
`clinic_id`, `doctor_id`, `patient_id`, `owner_uid`, `source_token_id`, `due_date`, `note`, `status`
(`pending`/`booked`/`done`/`missed`), `booked_token_id`, `reminders_sent` (0–2). One pending per patient + doctor.

---

## 6. Billing and logs

- `invoices`: id `inv_{clinicId}_{yyyy-MM}`, `month`, `amount`, `due_date` (text), `status`
  (`unpaid`/`overdue`/`paid`/`waived`), `payment` jsonb (`{amount, method, reference, date, recordedBy}`),
  `waive_reason`, `reminder_sent_at`.
- `activity_logs`: `clinic_id` (null = global), `actor` jsonb (`{uid, name, role}`), `action`, `target`, `at`.
- `billing_settings` (one row `billing`): `prices` jsonb, `pilot_days`, `billing_day`, `due_days`, `grace_days`,
  `suspend_days`, `payment_instructions`.

## 7. Backend-only

- `clinic_pins`: bcrypt `hash` of the 4-digit manager PIN, `failed`, `locked_until` (5 wrong → 15 min),
  `unlocked_until` (15 min after a correct PIN).
- `rate_limits`: `phoneLookup_{clinicId}` window (30 lookups / 10 min).
- `push_outbox`: pushes waiting for `send-push` (`title`, `body`, `data`, `sent_at`, `attempts` ≤ 5, `claimed_at`,
  `last_error`); sent rows deleted after 7 days.

---

## 8. Functions, triggers, jobs

The full list with inputs, outputs and error codes is in **docs/10-supabase-migration.md §6b**. In short:
- Patient app: `book_token`, `cancel_token`, `create_profile`, `update_phone`, `delete_my_account`.
- Clinic web: `queue_action`, `clinic_create_walk_in`, `clinic_lookup_phone`, `clinic_update_patient`, `set_follow_up`,
  `save_doctor`, `set_doctor_active`, `set_doctor_leave`, `cancel_doctor_tokens`, `update_clinic_settings`,
  `log_export`, `clinic_set_pin`, `clinic_verify_pin`, `clinic_login_touch`, `clinic_password_changed`,
  `link_walk_in_to_account`.
- Super Admin: `admin_set_clinic_status`, `admin_change_plan`, `admin_extend_pilot`, `admin_reset_clinic_pin`,
  `record_payment`, `waive_invoice`, `give_extension`, `save_admin_settings`, `admin_run_billing_jobs`,
  `admin_link_doctors`, `admin_mark_not_same`, `admin_unlink_doctor`.
- Service role only: `claim_push_batch`, `finish_push`, `svc_*` (clinic logins).
- Triggers: `on_token_status` (active numbers, skip / clinic-cancel notices), `on_queue_day_change` (3/2/1/Your turn),
  `on_push_outbox_insert` (wakes `send-push`), `guard_patient_write`, `set_updated_at`.
- `pg_cron` (UTC): `asani-auto-close-tokens` 22:00, `asani-billing-jobs` 01:00, `asani-follow-up-reminders` 04:00,
  `asani-cleanup` 23:00, `asani-retry-push` every minute.
- Errors: the exception message is the code, the hint the text, the detail JSON extras.

## 9. Indexes

Defined in the migrations next to each table: clinics (city, status, name), doctors (clinic, active, sort),
(city, speciality, active), (group), (name key, speciality); patients (owner, status, created), phone, `clinic_ids` GIN,
one Self per owner; tokens (booker, created), (owner, source, created), (patient, created), (doctor, date, status,
number), (clinic, date), active statuses; follow-ups (owner, status, due), (status, due), (clinic, due),
(patient, doctor, status); invoices; activity logs (clinic, at); notifications (user, created), (expire);
doctor_private PMDC; suggestions (status, created); push outbox unsent. A new query → check the plan and add an
index in a new migration.

## 10. Data retention

- Tokens and visits: kept while the clinic is a customer.
- Deleted accounts (`delete_my_account`): waiting tokens cancelled; app-created profiles anonymised ("Deleted user",
  no phone, status `deleted`); token snapshots anonymised; the login, account row, devices and notifications deleted.
- No diagnosis, medicines or reports are stored.
