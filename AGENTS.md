# AGENTS.md — Instructions for AI coding agents

This file is for **Codex, Claude Code and any other AI agent** working on Asani. Read it completely before writing code. If anything here conflicts with a request, stop and ask.

---

## 1. Project in one paragraph

Asani is a clinic token and live-queue system for small and medium private clinics in Pakistan. Patients use a Flutter app (Android + iOS) to search a clinic and pick a doctor there (or pick a speciality and a doctor near them), book a token for themselves or a family member, watch the live queue and get notified when their turn is near. The backend is **Supabase** (D-52: Auth with an email code for patients and email + password for clinics, Postgres with Row Level Security and Postgres functions, Realtime, Edge Functions, pg_cron); push stays on **Firebase Cloud Messaging**. The owner is **Sarbuland**. New session? Read CONTEXT_FOR_CLAUDE.md.

---

## 2. Current scope — READ THIS FIRST

| Part | Status | Agent rule |
|---|---|---|
| `apps/patient_app` | ✅ Active | Build here |
| `functions/`, `firestore.*` | ⛔ Retired (D-52) | Old Firebase backend, kept for reference until Sarbuland OKs its removal. Do not add to it |
| `packages/asani_core` | ✅ Active | **Pure Dart** shared code: models, enums, PKT dates, phone utils, token code, `Fmt`, `AppLogger`. No Flutter imports |
| `packages/asani_ui` | ✅ Active | **Flutter** shared look: theme tokens, `buildAppTheme` (phone) / `buildDesktopAppTheme` (web), common widgets |
| `tools/queue-sim`, `tools/admin-scripts` | ✅ Active | Dev tooling |
| root `pubspec.yaml` | ✅ Active | Dart pub workspace; run `flutter pub get` **at the root**; one `pubspec.lock` at the root |
| `apps/clinic_web` | 🟡 Phase 2 (demo backend) | Flutter Web clinic dashboard **and** super admin panel (PRD-CLINIC-WEB.md v0.4). One login per clinic, no staff/doctor accounts; the clinic manages its own doctors. Two backends: in-memory demo (default) and Firebase (`--dart-define=BACKEND=firebase`, clinic/admin functions in `functions/src/clinic` + `functions/src/admin`) |
| `supabase/`, `tools/db-test` | ✅ Active (D-52) | The backend is moving from Firebase to Supabase phase by phase (docs/10-supabase-migration.md). Firebase stays for push (FCM) only. Cloud project only, no Docker. Never edit a pushed migration; add a new one |
| Clinic desktop (.exe) | ⛔ Dropped | Replaced by Flutter Web (D-06 updated). **Do not create** `apps/clinic_desktop` |

The clinic side is **Flutter Web** in Chrome (PRD-CLINIC-WEB.md D-06). Super admin screens live inside the same web app, shown by role (D-15).

**Monorepo rules** (PRD-CLINIC-WEB §2.1): never nest one app inside another; move files with `git mv`; shared non-UI code → `asani_core`, shared UI → `asani_ui`; auth and Cloud Functions callables stay inside each app (phone OTP vs email + password).

**Branches** (Sarbuland, 2026-11-14): `main` is the only long-lived branch. For each task create a **short-lived branch** from `main` (e.g. `feature/queue-board`, `fix/token-slip`, `docs/setup`), commit there, merge it into `main` when the task is done, then delete the branch (local and GitHub). Never leave finished work on a side branch.

---

## 3. 🔴 Golden rule: confirm before building when unclear

Sarbuland's explicit instruction:

> If anything is confusing while building, or it is unclear how a feature should actually work, **confirm with me first** before building it.

In practice:

1. If PRD.md, DESIGN.md or DATABASE.md do not clearly answer how something should behave, **stop and ask**. Do not guess and build.
2. Ask in a short list: what is unclear, 2–3 options, and which one you recommend and why.
3. Small implementation details (variable names, private helper structure) do not need confirmation. **Behaviour the user or clinic will notice always does.**
4. If you find a contradiction between documents, report it. Do not silently pick one.
5. Record confirmed answers in the right document (usually PRD.md §9 "Decisions log") in the same change.

Examples that **must** be confirmed: a new notification, a new booking rule, changing a status flow, adding a field that patients or clinics see, any change to security rules, adding a paid service.

---

## 4. Fixed product decisions (do not change without asking)

1. **Queue notifications (4 total per token):**
   - when **3** patients are ahead → "3 patients ahead of you"
   - when **2** are ahead → "2 patients ahead of you"
   - when **1** is ahead → "You're next"
   - when the patient is **called** → "Your turn now"
   - Never send the same step twice. If the queue jumps (skip/cancel), send only the latest step that applies. Never more than 4 queue notifications per token.
2. **Flow:** search a **clinic** → pick a **doctor at that clinic**, **or** (D-31) pick a **speciality** in the Doctors tab → doctor card (nearest clinic first) → booking. Specialities come from a **fixed list** (chips, no free-text doctor search). The same doctor at two clinics is **one card** only after the Super Admin links the records (D-32); the system never links on its own.
3. **Platforms:** patient app is Flutter for **Android and iOS**.
4. **Language:** English UI only.
5. **Patient identity:** the patient logs in with an **email code** (D-52); the account's **phone** (required, not verified, one phone = one app account) is the family's contact number at clinics; each patient is a *profile* (`patients`). Tokens point to `patientId`. Walk-ins are never linked to an account automatically.
6. **Token numbers** are assigned only by the `book_token` / `clinic_create_walk_in` Postgres functions with the queue-day row locked (D-52). The client never writes a token number.
7. **One login per clinic** (PRD-CLINIC-WEB.md D-07, D-18): the clinic's email + password, set by the manager from an invite email; the receptionist uses the same login. No receptionist or doctor accounts; doctors are records the clinic adds itself (D-19). Roles (`clinic` + `clinic_id`, or `superAdmin`) live in Supabase `app_metadata`, set only on the server (D-52).

---

## 5. Communication with Sarbuland

- Explain in **Roman Urdu mixed with English technical terms**, short and direct.
- When giving code, give **complete, ready-to-paste files**, not partial snippets.
- Code, comments, commit messages and documents stay in **English**.

---

## 6. Tech rules

### Flutter app
- Flutter stable, Dart ≥ 3.9. Null safety everywhere.
- **State:** `flutter_riverpod` (Notifier/AsyncNotifier + providers). No GetX in this project.
- **Navigation:** `go_router`. All routes are declared in `lib/core/router/app_router.dart`.
- **Structure:** feature-first (see ARCHITECTURE.md §4). UI never calls the backend directly; it goes **UI → provider → repository → Supabase**.
- Models live in `packages/asani_core`, with `fromMap`/`toMap` (repositories map Postgres rows to them). Times are `timestamptz`; queue day IDs are `yyyy-MM-dd` in **Asia/Karachi** time.
- Use theme tokens from `package:asani_ui/asani_ui.dart` only (`AppColors`, `AppText`, `Gap`, `Radii`). No hard-coded colors or font sizes in widgets.
- Every async screen handles **loading, empty, error and offline** states (DESIGN.md §6). `ErrorState` lives in each app (`lib/core/widgets/error_state.dart`) because error messages differ.
- No `print`. Use `AppLogger` from `package:asani_core/asani_core.dart`.

### Supabase (D-52)
- Schema source of truth: **DATABASE.md**. Every change = a NEW migration in `supabase/migrations/` (never edit a pushed
  one) + DATABASE.md + a pgTAP test in `supabase/tests/database/`, in the same change.
- Business rules and anything atomic are Postgres functions (`security definer`, `set search_path = ''`), checking the
  caller (`private.is_patient()`, `private.clinic_actor()`, `private.admin_actor()`) and every input.
  Errors: `raise exception '<code>' using hint = '<text>'`.
- Anything that changes a token's status locks its `queue_days` row first. Triggers and jobs must be idempotent.
- RLS is on for every table; a policy or grant change needs an RLS test. Realtime filters on uuid / `id` columns don't fire.
- Edge Functions only for secrets or the Auth admin API (`send-push`, `admin-clinic-login`).
- Every new query needs an index check (add it in a migration).

---

## 7. Safety rules

- **Never** run commands against a production project (Supabase prod, Firebase `asani-prod`). Use `asani-dev`.
- **Never** commit `serviceAccount*.json`, `.env`, keystores, `GoogleService-Info.plist` for prod, or any secret.
- **Never** deploy or push to a hosted project (`supabase db push`, `functions deploy`, `secrets set`, `firebase deploy`) unless Sarbuland asked in that session.
- **Never** delete data, collections or users without explicit permission.
- **Never** loosen security rules "to make it work". Find the real cause (docs/08).
- Through MCP (docs/05), Firebase tools are for **dev only**.

---

## 8. Commands

```bash
# Install (pub workspace, from the repo root)
flutter pub get

# Patient app
cd apps/patient_app
flutter analyze
flutter test
flutter run --flavor dev                                            # demo data
flutter run --flavor dev --dart-define=BACKEND=firebase --dart-define=USE_FUNCTIONS_EMULATOR=true

# Clinic web
cd apps/clinic_web
flutter analyze
flutter run -d chrome                                               # demo data
flutter run -d chrome --dart-define=BACKEND=firebase --dart-define=USE_FUNCTIONS_EMULATOR=true
flutter run -d chrome --web-port 8092 --dart-define=BACKEND=supabase   # D-52 (dev logins: tools/db-test/create-login.js)

# Shared packages
cd packages/asani_core && dart test
cd packages/asani_ui && flutter analyze

# Functions
cd functions
npm run lint
npm run build
npm test                       # runs against emulators

# Emulators (from repo root)
firebase emulators:start --import=./emulator-data --export-on-exit

# Rules tests
cd functions && npm run test:rules

# Supabase (D-52): apply migrations + seed to the dev project, then run the pgTAP tests (rolled back)
npx supabase@latest db push --db-url "<url from supabase/.db-url.local>?sslmode=require" --include-seed
cd tools/db-test && node run.js

# Queue simulator (acts as the clinic on asani-dev, real Postgres functions)
cd tools/queue-sim
node queue-sim.js status --doctor <doctorId>
node queue-sim.js next   --doctor <doctorId> [--anyway]
```

---

## 9. Definition of done (every task)

- [ ] Behaviour matches PRD.md; anything unclear was confirmed (§3)
- [ ] UI matches DESIGN.md (tokens, states, copy)
- [ ] `flutter analyze` has zero warnings; `flutter test` passes
- [ ] Database: `node tools/db-test/run.js` passes (and `client-smoke.js` for app-facing changes)
- [ ] New queries have indexes; schema changes are in DATABASE.md
- [ ] Rules changes have tests
- [ ] Tested on a real Android device (Redmi) for anything involving notifications
- [ ] Short summary for Sarbuland in Roman Urdu: what changed, how to test, open questions

---

## 10. Where to look

| Question | File |
|---|---|
| What should this feature do? | PRD.md |
| How should this screen look? | DESIGN.md |
| Which function or collection? | ARCHITECTURE.md, DATABASE.md |
| How do I add a feature? | docs/03-feature-development.md |
| Auth, rules, privacy | docs/04-authentication-and-security.md |
| Something is broken | docs/08-debugging.md |
