# 10 — Moving the backend from Firebase to Supabase (D-52)

Status: **plan approved** by Sarbuland (2026-11-24), open questions answered (§7). Building phase by phase.
Decision: PRD.md §9 **D-52**. All earlier decisions D-01…D-51 keep their behaviour; only the backend under them changes.

---

## 1. Why

The Firebase dev project needs the paid **Blaze** plan for Cloud Functions, scheduled jobs, triggers, TTL and real SMS.
Supabase's free plan gives us a Postgres database, Row Level Security, Postgres functions, Edge Functions, Realtime,
`pg_cron` and Auth (email OTP + email/password) at no cost. Push stays on **Firebase Cloud Messaging**, which is free on the
Spark plan.

## 2. What changes for users

| | Before (Firebase) | After (Supabase) |
|---|---|---|
| Patient login | Phone number + SMS OTP | **"Continue with email"** + 6-digit **email** code (no password, no magic link), valid **10 minutes** |
| Patient phone | Verified by the SMS login | **Required** in profile setup (`+92 3XX XXXXXXX`), **not verified** (`phoneVerified = false`). **One phone = one app account** (`phone-taken`) |
| Walk-in profiles with the same phone | Attached automatically on login (`linkPatientProfiles`) | **Never automatic.** Reception links them in person: search by phone → walk-in profiles + the app account → patient confirms → **Link to app account** (activity log) |
| Clinic web login | Email + password (Firebase) | Email + password (Supabase). Super Admin creates the login → invite email → set password. **Forgot password** link on the login screen. Manager PIN unchanged |
| Everything else | — | Same screens, same rules, same notifications |

## 3. What moves where

### 3.1 Data: Firestore → Postgres tables

One table per collection. Columns are `snake_case`; IDs stay **text** (`gen_random_uuid()::text` by default) so the seed
can keep readable IDs like `d_ayesha` and the Dart models keep `String` IDs. Timestamps are `timestamptz` (UTC); queue day
IDs stay `yyyy-MM-dd` in Asia/Karachi.

| Firestore | Postgres | Notes |
|---|---|---|
| `users/{uid}` | `users` (PK = `auth.users.id`) | + `email`, `phone` (**unique**), `phone_verified` (false) |
| `users/{uid}/devices` | `devices` | FCM tokens |
| `users/{uid}/notifications` | `notifications` | Inbox (D-45). 30-day cleanup by `pg_cron` (no Blaze TTL needed) |
| `patients` | `patients` | `clinic_ids text[]` (GIN index) |
| `clinics` | `clinics` | `location` as `lat`/`lng` columns |
| `clinics/{id}/private/billing` | `clinic_billing` | Super Admin + own clinic only |
| `clinics/{id}/stats/{yyyy-MM}` | `clinic_stats` (PK clinic + month) | |
| `doctors` | `doctors` | `schedule jsonb`, `on_leave_dates date[]` |
| `doctors/{id}/private/admin` | `doctor_private` | PMDC, Super Admin read only (D-33) |
| `doctors/{id}/days/{date}` | `queue_days` (PK doctor + date) | `active_numbers int[]` kept by a **trigger** |
| `tokens` | `tokens` | `patient_snapshot`, `notified`, `history` as `jsonb`; unique (doctor, date, number) |
| `followUps` | `follow_ups` | |
| `clinicAccounts` | `clinic_accounts` | |
| `adminUsers` | `admin_users` | |
| `invoices`, `activityLogs`, `settings/billing` | `invoices`, `activity_logs`, `billing_settings` | |
| `doctorLinkSuggestions` | `doctor_link_suggestions` | Super Admin only |
| `clinicPins`, `rateLimits` | `clinic_pins`, `rate_limits` | No client access at all |
| — | `push_outbox` | **New.** Pushes waiting to be sent (see 3.5) |

The unique index on `tokens (doctor_id, date, number)` is a second guard: even a bug can never store a duplicate number.

### 3.2 Security: Firestore rules → Row Level Security

RLS is **on for every table**. Clients only **read** (plus the few direct writes the rules allow today: own user row,
own devices, own family profiles). Every other write goes through a Postgres function.

| Rule today | RLS policy |
|---|---|
| Patient reads own `users`, `devices`, `notifications`, `patients`, `tokens`, `follow_ups` | `auth.uid() = owner` columns (`booked_by_user_id`, `patient_owner_uid`, `owner_uid`) |
| Clinic reads only its own clinic's tokens, patients (`clinic_ids`), follow-ups, billing, stats, logs | `app_metadata.role = 'clinic' and app_metadata.clinic_id = clinic_id` |
| Signed-in users read clinics, doctors, queue days | `auth.role() = 'authenticated'` |
| PMDC, link suggestions, admin users: Super Admin only | `app_metadata.role = 'superAdmin'` |
| PIN hashes, rate limits, push outbox | No policy → nobody but the server |

Roles live in **`app_metadata`** (`role`, `clinic_id`), which only the server (service role) can set. `user_metadata` is
never used for roles because users can change it.

Rules tests (`functions/test/rules/*.test.js`) are rewritten as **pgTAP** tests (`supabase/tests/*.sql`) with the same cases.

### 3.3 Business logic: Cloud Functions → Postgres functions + Edge Functions

**Postgres functions (RPC, `security definer`, one transaction each)**: everything that must be atomic or follows booking
and queue rules. Called with `supabase.rpc(...)`. Each one checks the caller (`auth.uid()`, role, clinic) and its input,
and raises errors with the same codes we use today (`too-many-active`, `not-arrived`, `pin-locked`, …).

| Today (TypeScript) | Postgres function |
|---|---|
| `bookToken` | `book_token` — locks the queue day row (`select … for update`), BR-1…BR-7, number = last + 1 |
| `cancelToken` | `cancel_token` |
| `onTokenWrite` / `onQueueDayWrite` triggers | **Real Postgres triggers** on `tokens` / `queue_days` (they work on the free plan): keep `active_numbers`, then evaluate the 3/2/1/Your turn steps |
| `queue/steps.ts`, `notify.ts`, `skipNotice`, `cancelNotice` | `evaluate_queue`, `notify_skip`, `notify_clinic_cancel` (same rules, D-04, D-23, D-34, D-35, D-38, D-39) |
| `queueAction`, `nextOrder.ts` | `queue_action` (D-24 Next order, undo 30 s) |
| `clinicCreateWalkIn`, `clinicLookupPhone`, `clinicUpdatePatient`, `setFollowUp` | same names in snake_case |
| `saveDoctor`, `setDoctorActive`, `setDoctorLeave`, `cancelDoctorTokens`, suggestions | same, incl. PMDC to `doctor_private` and same-city suggestions (D-31…D-33) |
| PIN (`clinicSetPin`, `clinicVerifyPin`, `adminResetClinicPin`) | same; hash with `pgcrypto` (bcrypt) instead of scrypt; 5 wrong → 15 min lock |
| Admin: status, plan, pilot, payments, settings, doctor links | same names in snake_case |
| `billingJobs`, `followUpReminders`, `autoCloseTokens` | Postgres functions run by **`pg_cron`** |
| — | **New:** `link_walk_in_to_account` (reception flow, D-52) |

The pure rules already tested in TypeScript (`steps.ts`, `nextOrder.ts`, `rules.ts`, `pinRules.ts`, `linking.ts`) are
ported one by one, and their unit tests become pgTAP tests with the same cases.

**Edge Functions (Deno, TypeScript)**: only what needs secrets or the Auth admin API.

| Edge Function | Why not SQL |
|---|---|
| `send-push` | Signs a Google token with the Firebase service account and calls the **FCM HTTP v1 API** |
| `admin-clinic-login` | Create the clinic login, set `app_metadata`, send the invite, resend, disable/enable (Auth admin API) |
| `delete-account` | Deletes the Auth user after the SQL clean-up |
| `clinic-password-changed` | Signs out the clinic's other sessions (C-12) |

### 3.4 Live queue: Firestore listeners → Supabase Realtime

The apps subscribe to `postgres_changes` on `queue_days` (one doctor + date) and on the user's own `tokens`.
Realtime applies RLS, so a patient only receives their own token rows. The token screen still needs **two** subscriptions
(own token + queue day), as today.

### 3.5 Push notifications: FCM stays

1. A Postgres function decides a push is due and, **in the same transaction**, marks it (`notified`, `cancel_notified_at`,
   `skip_notified_at` — the same "claim" guards as today), writes the inbox row (`notifications`) and a `push_outbox` row.
2. A trigger on `push_outbox` calls the `send-push` Edge Function through `pg_net`.
3. `send-push` sends to every device of the account through FCM HTTP v1, marks the row sent, and deletes device tokens that
   FCM reports as unregistered (replaces `cleanupStaleDevices`).
4. A `pg_cron` job every minute retries rows that are still unsent.

The account-wide queue alerts switch (D-18) and the inbox-even-when-off rule (D-45) are unchanged.
Secret needed: the Firebase service account JSON of `asani-b2b17`, stored as a Supabase secret (never committed).

### 3.6 Scheduled jobs: Cloud Scheduler → `pg_cron`

`pg_cron` runs in UTC; Pakistan is UTC+5 with no daylight saving.

| Job | PKT | Cron (UTC) |
|---|---|---|
| Auto-close old tokens (D-21) | 03:00 | `0 22 * * *` |
| Follow-up reminders | 09:00 | `0 4 * * *` |
| Billing: invoices, overdue → grace → suspended, defaulters | 06:00 | `0 1 * * *` |
| Delete inbox rows older than 30 days (D-45) | 04:00 | `0 23 * * *` |
| Retry unsent pushes | every minute | `* * * * *` |

### 3.7 Auth

**Patient app** — Supabase email OTP:
- `signInWithOtp(email: …, shouldCreateUser: true)` then `verifyOTP(email: …, token: code, type: OtpType.email)`.
- Email template "Magic Link" / "Confirm signup" changed to show `{{ .Token }}` only (no link). OTP expiry **600 s**.
- Custom SMTP (Brevo or Resend free plan) in Supabase → Auth → SMTP; steps go in `docs/02-setup.md`.
- `AuthRepository` contract for the UI:

  ```dart
  Future<void> sendEmailOtp(String email);
  Future<void> verifyEmailOtp(String email, String code);
  Future<void> createProfile({required String name, required int age, required Gender gender, required String phone});
  Future<void> updatePhone(String phone);
  Future<void> signOut();
  // kept: watchAuth, current, setCity, setQueueAlerts, deleteAccount, cancelLogin
  ```

  Errors (`AuthException.code`): `invalid-email`, `invalid-code`, `code-expired`, `too-many-requests`, `phone-taken`,
  `invalid-phone`, `network`.
- `createProfile` and `updatePhone` are Postgres functions: they normalise the phone (`+923XXXXXXXXX`), check the format
  (`invalid-phone`), check the unique phone (`phone-taken`), and create the `users` row + Self profile in one transaction
  with `phone_verified = false`.
- `linkPatientProfiles` is **removed** (no auto-linking).
- A clinic or Super Admin login (it has `app_metadata.role`) is refused by the patient app and signed out.

**Clinic web** — Supabase email + password:
- Super Admin creates the clinic → `admin-clinic-login` creates the user with `app_metadata {role: clinic, clinic_id}` and
  sends the **invite** email → the link opens the web's "Set your password" page.
- **Forgot password**: `resetPasswordForEmail` → the link opens the same page.
- Manager PIN (D-41) unchanged.

## 4. Phases (Sarbuland tests after each one)

| # | Phase | Result you can test |
|---|---|---|
| 0 | **This plan** + D-52 | Read and approve |
| 1 | **Setup, tables, RLS, seed** — `supabase/` folder (migrations, `seed.sql`, `config.toml`), pgTAP RLS tests | Supabase Studio shows the tables with seed clinics/doctors; `supabase test db` passes |
| 2 | **Booking + queue logic in Postgres** — `book_token`, `cancel_token`, triggers, `evaluate_queue`, skip/cancel notices, inbox + outbox, auto-close; tests incl. 2 bookings at the same moment | Call the functions from Studio's SQL editor; tests pass |
| 3 | **Push + scheduled jobs** — `send-push` Edge Function, `pg_net` trigger, `pg_cron` jobs | A test row in `push_outbox` arrives on the Vivo / Redmi |
| 4 | **Patient app login** — email OTP, new `AuthRepository`, profile setup with phone, `phone-taken`, SMTP + email template steps | Log in with email on the phone, finish profile setup |
| 5 | **Patient app data** — Supabase repositories (clinics, doctors, doctor search, queue Realtime, tokens, family, follow-ups, notifications), `BACKEND=supabase`; Firebase Auth/Firestore/Functions packages removed (Messaging stays) | Full patient flow on the phone: search → book → live queue → pushes |
| 6 | **Clinic + Super Admin backend** — all clinic/admin Postgres functions, `admin-clinic-login`, `delete-account`, billing jobs, **Link to app account** | Tests pass; functions callable from Studio |
| 7 | **Clinic web on Supabase** — email/password, invite, forgot password, Realtime board, link-to-account dialog | Full clinic flow in Chrome with the app together |
| 8 | **Clean-up + docs** — `tools/queue-sim` and admin scripts on Supabase, CI, remove `functions/` + Firestore files (**only after your OK**), all docs | Fresh clone works from the setup doc |

The **demo backend stays** in both apps (`BACKEND=demo`, default) through all phases. The Firebase backend stays in the
code until phase 7 works, so we can always compare.

Docs are updated in the phase that changes them: DATABASE (1, 2, 6), ARCHITECTURE (2, 3, 5, 7), PRD auth F-01 and
PRD-CLINIC-WEB auth (4, 7), AGENTS.md commands + scope (1, 8), docs/02 setup (1, 3, 4), docs/04 security (1, 4),
docs/07 tests (every phase), REMAINING_WORK (every phase). `TESTING_CHECKLIST.md` and `CONTEXT_FOR_CLAUDE.md` do not
exist yet; they are created in phase 8 (the checklist grows from each phase's "how to test").

## 5. What you need to do (manual, when the phase needs it)

1. **Phase 1:** create a free Supabase account and a project **`asani-dev`**, region **South Asia (Mumbai)**. Send me the
   project URL and the **anon** key (public). Keep the service role key and DB password to yourself; I'll tell you where to
   paste them locally (git-ignored files).
2. **Phase 1:** install the Supabase CLI (no Docker, S-1). I give the steps.
3. **Phase 3:** in the Firebase console (`asani-b2b17`, stays on Spark): download a service account key for FCM; I give the
   steps to store it as a Supabase secret.
4. **Phase 4:** create the Brevo (or Resend) account; I give the SMTP steps.

## 6. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| **Free project pauses after 1 week without use** | During the pilot the app and clinic web stop working until someone un-pauses it in the dashboard; booked patients see errors | Before the pilot: Pro plan (paid, needs your OK) **or** a scheduled keep-alive request (e.g. GitHub Actions daily). Note: `pg_cron` jobs alone do not count as use |
| **No daily backups on the free plan** | Real clinic data could be lost | Nightly `pg_dump` from GitHub Actions to a private place, or Pro before real patients |
| **Email limits** | Supabase's built-in email is ~2/hour (testing only). Free SMTP: Brevo 300/day, Resend 100/day (needs our own domain, Q-06) | Custom SMTP before any real user; watch daily volume in the pilot |
| **Emails land in spam / unknown sender** | Patients don't get the code | Send from our own domain (Q-06) with SPF/DKIM; until then Brevo with a verified sender |
| **Phone not verified** | Someone can type another person's number | One phone = one account; never auto-link; reception links only after an in-person check (D-52) |
| **Big rewrite of tested logic** | New bugs in booking/queue rules | Port each rule with its existing test cases first; demo backend + Firebase code kept until phase 7 passes |
| **No App Check** | Fake clients can call the API with the public anon key | RLS + every write through checked Postgres functions; rate limits in SQL; optional Turnstile CAPTCHA on OTP later |
| **No offline cache like Firestore** | Offline screens could be empty after a restart | Keep the last data in memory + a small local cache for Home, My Tokens and the open token (offline banner unchanged) |
| **Realtime free limits** (200 connections, 2M messages/month) | Fine for a pilot of a few clinics, not for scale | One channel per screen, unsubscribe on leave; re-check before scaling |
| **Edge Function cold start** | First push after idle a little slower | Fine for pushes; booking and queue actions are SQL (no cold start) |

## 6b. Built so far

| Phase | Done | Files | Tests |
|---|---|---|---|
| 1 | 2026-11-25 | `supabase/migrations/…000100_schema.sql`, `…000200_security.sql`, `seed.sql` | `01_rls.test.sql` (37) |
| 2 | 2026-11-25 | `supabase/migrations/20261125000100_booking_queue.sql` | `02_booking_queue.test.sql` (59), `tools/db-test/concurrency.js` (20 bookings on 10 connections → 1..20, no duplicates) |

**Phase 2 API for the apps** (called with `supabase.rpc`):

| Function | Input | Returns |
|---|---|---|
| `book_token` | `p_clinic_id, p_doctor_id, p_patient_id, p_date` (`yyyy-MM-dd`) | `{tokenId, number}` |
| `cancel_token` | `p_token_id` | `{ok: true}` (cancelling twice is fine) |

Errors come back as a `PostgrestException` whose **message is the code**: `unauthenticated`, `invalid-argument`,
`not-found`, `permission-denied`, `clinic-unavailable`, `doctor-unavailable`, `session-ended`, `tokens-full`,
`duplicate-token` (DETAIL = `{"name", "label"}` JSON), `too-many-active`, `cannot-cancel`.

**Inside the database** (schema `private`, not callable from the apps):
- Trigger `on_token_status` (any status change) → recomputes `queue_days.active_numbers`; skip → `notify_skipped`
  (D-34); clinic cancel → `notify_clinic_cancel` (D-23).
- Trigger `on_queue_day_change` (`active_numbers`, `current_token` or `session_status` changed) → `evaluate_queue`
  (3/2/1/Your turn, N-1…N-4, D-39).
- `notify_user` writes the inbox row (`notifications`, always, D-45) and a `push_outbox` row (queue pushes only when
  `queue_alerts_enabled`, D-18). Phase 3 sends the outbox through FCM.
- `auto_close_tokens()` (D-21) is ready; `pg_cron` runs it at 03:00 PKT from phase 3.
- Locking rule: every status change locks the queue day row first, so bookings on one doctor/day run one at a time.
- Tests can pin the clock with `set asani.test_now = '…'` (honoured only for a direct `postgres` session, never the API).

Not yet: D-24 Next order, D-35 skip repeat, D-38 undo and `priority_at` live in `queue_action` (phase 6).

**Phase 3 (2026-11-25): how pushes are sent.** Files: `supabase/migrations/20261125000200_push_cron.sql`,
`supabase/functions/send-push/index.ts`; tests `03_push_cron.test.sql` (27) plus a real push end-to-end.
- Insert into `push_outbox` → statement trigger → `pg_net` POST to `send-push` (after commit) with `x-push-secret`.
- `send-push` (Edge Function, `verify_jwt = false`) → `claim_push_batch` (service role only, `skip locked`) → FCM HTTP v1
  per device (Android channel `queue_alerts`, or `follow_ups` for follow-ups; `tag` = token ID) → `finish_push`
  (done, or released for a retry; dead device tokens deleted).
- `pg_cron` every minute: `retry_push` (max 5 tries per row).
- Secrets: Vault `push_url`, `push_secret`; Edge Function secrets `PUSH_SECRET` (same value) and
  `FCM_SERVICE_ACCOUNT` (asani-b2b17 service account JSON, **base64**: a plain JSON value was mangled by the env file).
- Jobs (UTC): `asani-auto-close-tokens` 22:00 (03:00 PKT), `asani-follow-up-reminders` 04:00 (09:00 PKT),
  `asani-cleanup` 23:00 (inbox > 30 days, sent outbox rows > 7 days), `asani-retry-push` every minute.
- 2026-11-25 end-to-end on dev: a queued row reached FCM (`sent: 1`), and a stale device token was deleted.
- Deploy / secrets need `supabase/.access-token.local` (a scoped personal access token: Edge Functions + Secrets
  read & write). See docs/02 §2b.

**Phase 4 (2026-11-25): patient email login.**
- DB: `supabase/migrations/20261125000300_patient_auth.sql`: `create_profile(p_name, p_age, p_gender, p_phone)` (users row +
  Self profile in one transaction, `phone_verified = false`, idempotent) and `update_phone(p_phone)`; errors
  `invalid-phone`, `phone-taken`, `invalid-argument`, `unauthenticated`. Tests `04_patient_auth.test.sql` (20).
- App: `AuthRepository` = `sendEmailOtp`, `verifyEmailOtp`, `createProfile`, `updatePhone`, `updateName`, `setCity`,
  `setQueueAlerts`, `cancelLogin`, `signOut`, `deleteAccount` (delete comes in phase 6). Error codes in `AppException`.
  `SupabaseAuthRepository` (`lib/data/supabase/`), demo version in `DemoBackend` (code `123456`).
  Screens: S-02 "Continue with email", S-03 "Check your email", S-04 + mobile number, Account → Mobile number.
- `--dart-define=BACKEND=supabase` (URL and publishable key default to asani-dev in `Env`). In phase 4 only login is on
  Supabase; clinics, tokens and family still run on demo data. Pushes are off in this mode until phase 5 saves the
  device to Supabase. `BACKEND=firebase` can no longer log in (email needs Supabase).
- Dashboard settings (OTP 600 s / 6 digits, code-only templates, Brevo SMTP): docs/02 §2b.

**Phase 5 (2026-11-25): patient app data on Supabase.**
- `lib/data/supabase/supabase_repositories.dart`: clinics, doctors, queue day, tokens (`book_token` / `cancel_token`),
  family profiles (direct insert/update, the DB fills owner/phone/status), follow-ups, notifications list + seen-at.
  `rows.dart` maps rows (snake_case, ISO times) to the `asani_core` models. Reads are Realtime `.stream()`s.
- **Realtime filter quirk:** filters on uuid columns and on `id` never fire; `clinic_id`, `doctor_id`, `city`, `active`
  do. Streams that would need a broken filter are unfiltered and picked in the app (RLS already limits tokens,
  profiles, follow-ups and notifications to the user's own rows).
- Push: `PushService` stores the FCM token through a `PushAccount` (`SupabasePushAccount` → `devices` upsert); it
  registers when the account is signed in (the `devices` row needs the `users` row). Firebase starts only for FCM
  (`FirebaseSetup.initForPushOnly`).
- `tools/db-test/client-smoke.js`: signs in like the app (publishable key, temporary password logins, own `sm_` rows,
  all deleted afterwards) and checks profile, phone-taken, family, booking, duplicates, RLS, Realtime, notifications,
  cancel and devices end to end. 2026-11-25: PASS.
- Still demo in Supabase mode: local device settings (intro seen, primer) only. Account deletion: phase 6.

**Phase 6 (2026-11-26): clinic + Super Admin backend.** Migrations `20261126000100_clinic_queue.sql`,
`…000200_clinic_doctors_pin.sql`, `…000300_admin_accounts.sql`; Edge Function `admin-clinic-login`.
Tests `05_clinic_admin.test.sql` (76; 219 in total) and `tools/db-test/admin-login-smoke.js` (live, no real email).

| Who | Postgres function (`supabase.rpc`) | Replaces |
|---|---|---|
| clinic | `queue_action(p_action, p_doctor_id, p_token_id, p_reason, p_call_not_arrived)` → `{ok, called}` | `queueAction` |
| clinic | `clinic_create_walk_in(p_doctor_id, p_patient_id, p_phone, p_new)` → `{tokenId, number, label, patientId}` | `clinicCreateWalkIn` |
| clinic | `clinic_lookup_phone(p_phone)` → `{profiles: [{id, name, relation, gender, age, atThisClinic, appAccount}]}` | `clinicLookupPhone` |
| clinic | `clinic_update_patient`, `set_follow_up`, `save_doctor`, `set_doctor_active`, `set_doctor_leave`, `cancel_doctor_tokens`, `update_clinic_settings`, `log_export`, `clinic_login_touch`, `clinic_password_changed` | same names |
| clinic | `clinic_set_pin(p_pin, p_current_pin)`, `clinic_verify_pin(p_pin)` → `{ok, unlockedUntil}` or `{ok:false, code: pin-wrong \| pin-locked, triesLeft \| lockedUntil, message}` (returned, not raised, so a wrong try is saved) | PIN |
| clinic | **`link_walk_in_to_account(p_walk_in_id, p_account_phone, p_target_patient_id)`** (new, S-2) | — |
| Super Admin | `admin_set_clinic_status`, `admin_change_plan`, `admin_extend_pilot`, `admin_reset_clinic_pin`, `record_payment`, `waive_invoice`, `give_extension`, `save_admin_settings`, `admin_run_billing_jobs`, `admin_link_doctors`, `admin_mark_not_same`, `admin_unlink_doctor` | same names |
| patient | `delete_my_account()` (cancels waiting tokens, anonymises, deletes the login; no Edge Function needed) | `deleteAccount` |
| Edge Function | `admin-clinic-login` `{action: create, clinic}` / `{action: resend \| disable \| enable, clinicId}` | `adminCreateClinic`, `adminResendClinicInvite`, `adminSetClinicLogin` |

- Errors: the exception **message is the code** (e.g. `not-arrived`, `pin-required`, `managed-by-app`, `suspended`,
  `invoice-closed`, `already-linked`, `no-account`), the **hint** is the text to show, `detail` is JSON extras
  (`not-arrived`: `{tokenId, label, name}`).
- Skip / clinic-cancel pushes and queue alerts come from the phase 2 triggers, so `queue_action` only changes statuses.
- **D-52 change:** a NEW walk-in profile is never attached to an app account by phone (the old code did). The phone
  lookup marks app profiles `appAccount` (web label "App account (number not verified)"); reception links in person.
- Clinic password change (C-12): the web calls `auth.updateUser(password)`, then `signOut(scope: others)`, then
  `clinic_password_changed()`. Disabling a login bans it (`ban_duration`); its current access token ends within the hour.
- Billing job: `pg_cron` `asani-billing-jobs` at 01:00 UTC (06:00 PKT).
- Edge Function secret `CLINIC_WEB_URL` (set to `http://localhost:8092` on dev); `<url>/set-password` must be in Auth →
  URL Configuration → Redirect URLs. Invite / reset emails use the same SMTP as patient codes (Brevo).

**Phase 7 (2026-11-26): clinic web on Supabase.** `apps/clinic_web/lib/data/supabase_clinic_repository.dart`
(same live-cache shape as the Firebase one: Realtime streams on `clinic_id` / `date` / `month` or unfiltered + RLS;
writes through the phase 6 functions; PIN results `{ok:false, …}` become `AppException`s; Super Admin login actions
through `admin-clinic-login`). `--dart-define=BACKEND=supabase`.
- Login: `signInWithPassword`; role from `app_metadata`; patient accounts refused. Forgot password:
  `resetPasswordForEmail(redirectTo: web root)`. Change password (C-12): check the current one, `updateUser`,
  `signOut(scope: others)`, `clinic_password_changed()`.
- Invite / reset links: implicit flow, land on the web root; `main.dart` reads `type=invite|recovery` from the URL
  fragment, the router sends the signed-in browser to **`/set-password`** (`SetPasswordScreen`) first.
- New: **Link to app account** dialog on a walk-in's page (`link_account_dialog.dart`); the walk-in dialog labels app
  profiles "App account (number not verified)".
- Patient app: Account → Delete account calls `delete_my_account()`.
- Dev logins: `tools/db-test/create-login.js` (no email; password to the git-ignored logins file).
- 2026-11-26 checked in Chrome on asani-dev: clinic login → Queue Board from Supabase; Start → "Running" live; a walk-in
  made through the API appeared live; Next → "Now serving A-1" with Undo; no console errors. Test rows removed.

**Phase 8 part 1 (2026-11-26): clean-up without deleting.** `tools/queue-sim/queue-sim.js` now drives asani-dev
through `queue_action` / `clinic_create_walk_in` as the doctor's clinic (dev only; the Firestore one is
`queue-sim-firebase.js`); CI `supabase.yml`; clinic web CI builds `BACKEND=supabase`; DATABASE.md and ARCHITECTURE.md
rewritten for Supabase; new TESTING_CHECKLIST.md and CONTEXT_FOR_CLAUDE.md; README and AGENTS.md updated.
**Part 2 waits for Sarbuland's OK:** delete the Firebase backend code (list in REMAINING_WORK §13).

## 7. Decisions on the open questions (Sarbuland, 2026-11-24)

| # | Question | Answer |
|---|---|---|
| S-1 | Local development | **Cloud project only** (no Docker). Migrations are pushed to the free `asani-dev` project with the Supabase CLI; pgTAP tests run against it inside a transaction that is rolled back, so test rows never stay |
| S-2 | **Link to app account**: what happens to the walk-in profile? | Reception picks **which family member** it is, or **"New member"**. Picking a member moves the walk-in's visits (tokens, follow-ups) to that profile and marks the walk-in profile `merged` (`merged_into`); "New member" gives the walk-in profile the account as owner |
| S-3 | D-22 walk-in lookup by full phone: show the app account's family profiles? | **Yes**, labelled **"App account (number not verified)"** |
| S-4 | Can a patient change their phone later? | **Yes**, in Account (`updatePhone`), `phone-taken` checked; the account's own profiles get the new contact phone |
| S-5 | `phone-taken` compares with… | **Other app accounts only** (walk-in profiles with that phone are linked at reception) |
| S-6 | SMTP provider | **Brevo** free plan (300 emails/day) until we have a domain (Q-06) |
| S-7 | Pause risk for the pilot | **Decide before the pilot.** Note: the **Pro plan is the safe choice for real clinics** (no pausing, daily backups) |

With S-1 the "Docker Desktop" item in §5 is dropped; the CLI is still needed.
