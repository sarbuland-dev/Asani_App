# 04 — Authentication and Security (Supabase, D-52)

How users log in, who can read or write what, and how patient data is protected. The Firebase version of this file is
in git history (before 2026-11-27).

---

## 1. Identity model

| Who | How they log in | Identity | Role source |
|---|---|---|---|
| **Patient app user** (account owner) | "Continue with email" + 6-digit **email code** (valid 10 min) | Supabase Auth user (uuid, email) + `public.users` row | no `app_metadata.role` → patient |
| Patient profile (mother, child…) | Does not log in | `patients` row (`owner_uid` = the account) | n/a |
| **Clinic login** (one per clinic, D-18) | Email + password, set from the invite email | Auth user + `clinic_accounts` row | `app_metadata.role = clinic`, `clinic_id` |
| **Super Admin** | Email + password | Auth user + `admin_users` row | `app_metadata.role = superAdmin` |

- `app_metadata` can only be set with the service role: the `admin-clinic-login` Edge Function (clinics) or
  `tools/db-test/create-login.js` (dev). `user_metadata` is editable by users and is **never** used for access.
- The patient app signs out a staff account; the clinic web refuses a patient account.

### Phone number (D-52)
- Required in profile setup (`+92 3XX XXXXXXX`), stored in `users.phone` and on the family's profiles.
- **Not verified** (`phone_verified = false`). Because of that: **one phone = one app account** (unique index,
  `phone-taken`), and walk-in profiles are **never** attached to an account by phone. Reception links them in person
  with "Link to app account" (S-2), and the phone lookup labels app profiles "App account (number not verified)" (S-3).

---

## 2. Who can read and write what

Row Level Security is **on for every table** (`supabase/migrations/20261124000200_security.sql`); the table-by-table
summary is DATABASE.md §1. The rules in short:

- `anon` (not signed in): no access to anything.
- A patient reads only their own account, devices, notifications, family profiles, tokens (booked by them or on their
  profiles) and follow-ups; everyone signed in reads clinics, doctors and queue days (numbers only, no names).
- A clinic login reads only its own clinic's billing, stats, tokens, follow-ups, invoices, activity, and the patients
  who visited it (`clinic_ids`). It can never read patient accounts or PMDC numbers.
- The Super Admin reads everything admin screens need, including PMDC numbers and same-doctor suggestions.
- Nobody (not even the Super Admin through the API) reads `clinic_pins`, `rate_limits` or `push_outbox`.
- **Writes:** clients may only update a few columns of their own account, their own devices, and their own family
  profiles (owner, phone, status and Self are enforced by the database). Everything else goes through Postgres
  functions (`security definer`) that check the caller and every input. The client never writes a token number.

Tests: `supabase/tests/database/01_rls.test.sql` (37) plus the access checks in every other test file;
`tools/db-test/client-smoke.js` repeats them through the public API.

---

## 3. Protecting patient data

- Minimum data: name, birth year, gender, relation, phone. No diagnosis, medicines or reports.
- The queue day holds token numbers only, so a patient never needs other patients' tokens to see "patients ahead".
- The full-phone lookup at reception returns only name, relation, gender, age and two flags; it is rate limited
  (30 / 10 min per clinic).
- PMDC numbers live in `doctor_private` (Super Admin only); the clinic sees only "on file".
- Clinics can edit only walk-in profiles (D-40); app profiles belong to the family.
- **Delete account** (`delete_my_account()`, PRD F-10): waiting tokens cancelled, app-created profiles and visit
  snapshots anonymised ("Deleted user", no phone), login + account + devices + notifications deleted; clinic visit
  records stay without personal data.

---

## 4. Manager PIN (D-41)

4 digits, stored as a bcrypt hash in `clinic_pins`, checked only in the database. 5 wrong tries lock it for 15 minutes;
a correct PIN unlocks the protected actions (Billing, Export, Add / Deactivate doctor, Change password) for 15 minutes.
The Super Admin can reset it.

---

## 5. Secrets and keys

| What | Where | Public? |
|---|---|---|
| Project URL + publishable key | in both apps (`Env`) | yes (RLS protects the data) |
| Database URL (with password) | `supabase/.db-url.local` | **no**, git-ignored |
| CLI access token (Edge Functions + Secrets) | `supabase/.access-token.local` | **no**, git-ignored |
| Service role key | Supabase only (Edge Functions get it automatically) | **no**, never in an app |
| FCM service account | `tools/admin-scripts/serviceAccount.dev.json` + Edge Function secret `FCM_SERVICE_ACCOUNT` | **no** |
| `push_url`, `push_secret` | Supabase Vault (+ Edge Function secret `PUSH_SECRET`) | **no** |
| Dev test logins | `tools/admin-scripts/dev-test-logins.local.txt` | **no** |

Never commit, print or paste any of the "no" items (AGENTS.md §7).

---

## 6. Open risks (before the pilot)

- The phone is not verified (accepted by D-52; mitigated by one-phone-one-account and in-person linking).
- No App Check equivalent: anyone with the public key can call the API, but RLS and the function checks decide what
  they can do. Optional later: CAPTCHA (Turnstile) on the email code.
- Free plan: no daily backups and the project pauses after a week without use (docs/10 §6, S-7).
