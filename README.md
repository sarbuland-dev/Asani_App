# Asani

**Smart clinic token and live queue system for Pakistan.**

Patients book a clinic token from their phone, watch the live queue, and arrive when their turn is near. Clinics get fewer phone calls, fewer queue disputes and a simple visit history.

> Asani was previously called *ClinicQ*. Any reference to ClinicQ in older documents means Asani.

---

## Current phase

| Part | Status | Notes |
|---|---|---|
| **Patient App** (Flutter, Android + iOS) | 🟢 Active | `apps/patient_app`, on Supabase (dev, D-52) |
| **Clinic Web** (Flutter Web: clinic dashboard + super admin) | 🟡 Phase 2 | `apps/clinic_web` ([PRD-CLINIC-WEB.md](PRD-CLINIC-WEB.md)); demo or Supabase backend |
| **Backend** (Supabase: Auth, Postgres + RLS, Realtime, Edge Functions, pg_cron; FCM for push) | 🟢 Active | `supabase/`, dev project `asani-dev` ([docs/10](docs/10-supabase-migration.md)) |
| Clinic Desktop App (Windows .exe) | ⛔ Dropped | Replaced by the clinic web (D-06) |

`tools/queue-sim` can still drive a doctor's queue from the command line for testing.

---

## Repository structure

```
Asani_App/
├── pubspec.yaml              ← Dart pub workspace root (one `flutter pub get` for everything)
├── README.md · AGENTS.md · CLAUDE.md · PRD.md · PRD-CLINIC-WEB.md · DESIGN.md
├── ARCHITECTURE.md · DATABASE.md · REMAINING_WORK.md
├── docs/                     ← 01…08 guides (setup, features, security, testing, debugging)
├── apps/
│   ├── patient_app/          ← Flutter app (Android + iOS)
│   └── clinic_web/           ← Flutter Web: clinic dashboard + super admin
├── packages/
│   ├── asani_core/           ← pure Dart: models, enums, PKT dates, phone utils, token code, Fmt, AppLogger
│   └── asani_ui/             ← Flutter: theme (colors, fonts, spacing) + shared widgets
├── functions/                ← Cloud Functions (TypeScript)
├── tools/
│   ├── queue-sim/            ← dev script: move a doctor's queue from the command line
│   └── admin-scripts/        ← seed data, logins, follow-up reminders, auto-close
├── .github/workflows/        ← CI per part, with path filters
├── firebase.json
├── firestore.rules
└── firestore.indexes.json
```

Never nest one app inside another; shared non-UI code goes to `asani_core`, shared UI to `asani_ui`.

---

## Quick start

Full guide: [`docs/02-setup.md`](docs/02-setup.md)

```bash
# 1. Install dependencies (from the repo root)
flutter pub get                       # all Flutter/Dart members of the workspace
cd tools/db-test && npm install && cd ../..   # database tests + dev login script (needs supabase/.db-url.local)

# 2. Patient app (demo data, no Firebase needed)
cd apps/patient_app && flutter run --flavor dev

# 3. Clinic web (demo data) in Chrome
cd apps/clinic_web && flutter run -d chrome

# 4. Both on the Supabase dev project (D-52; setup: docs/02 §2b)
cd apps/patient_app && flutter run --flavor dev --dart-define=BACKEND=supabase
cd apps/clinic_web && flutter run -d chrome --web-port 8092 --dart-define=BACKEND=supabase
node tools/db-test/run.js                     # database tests (rolled back)
```

---

## Documentation map

| I want to… | Read |
|---|---|
| Understand the product and its rules | [PRD.md](PRD.md) |
| Build a screen | [DESIGN.md](DESIGN.md) |
| Understand how the pieces talk to each other | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Read or write data | [DATABASE.md](DATABASE.md) |
| Work with an AI agent on this repo | [AGENTS.md](AGENTS.md), [docs/05-mcp-connection.md](docs/05-mcp-connection.md) |
| Know what to build this week | [docs/01-project-implementation.md](docs/01-project-implementation.md) |
| Set up my machine | [docs/02-setup.md](docs/02-setup.md) |
| Add a new feature the right way | [docs/03-feature-development.md](docs/03-feature-development.md) |
| Touch login, rules or user data | [docs/04-authentication-and-security.md](docs/04-authentication-and-security.md) |
| Connect Firebase services, notifications, deep links | [docs/06-integration.md](docs/06-integration.md) |
| Test before release | [docs/07-testing-and-qa.md](docs/07-testing-and-qa.md) |
| Fix something broken | [docs/08-debugging.md](docs/08-debugging.md) |

---

## Tech stack

- **Apps:** Flutter (stable, Dart 3.9+): patient app on Android + iOS, clinic web on Flutter Web
- **State management:** Riverpod · **Navigation:** go_router
- **Backend (D-52):** Supabase Auth (patients: email code; clinics: email + password), Postgres with Row Level Security and Postgres functions, Realtime, Edge Functions (Deno), pg_cron. Push: Firebase Cloud Messaging (free Spark plan)
- **Region:** dev in Tokyo (`ap-northeast-1`); prod planned in Mumbai (`ap-south-1`), the closest to Pakistan
- **Language:** English only (UI)

---

## Owner

Sarbuland (GitHub: `sarbuland-dev`)
