# Asani

**Smart clinic token and live queue system for Pakistan.**

Patients book a clinic token from their phone, watch the live queue, and arrive when their turn is near. Clinics get fewer phone calls, fewer queue disputes and a simple visit history.

> Asani was previously called *ClinicQ*. Any reference to ClinicQ in older documents means Asani.

---

## Current phase: Patient App (Phase 1)

| Part | Status | Notes |
|---|---|---|
| **Patient App** (Flutter, Android + iOS) | 🟢 In scope now | This repo's current focus |
| **Backend** (Firebase: Auth, Firestore, Cloud Functions, FCM) | 🟢 In scope now | Only what the patient app needs |
| **Clinic Desktop App** (Windows .exe) | ⏸️ Next phase | Technology not confirmed yet. Do not build. |
| **Super Admin Panel** | ⏸️ Later phase | Location/technology not confirmed yet. Do not build. |

Until the desktop app exists, the queue is driven by a developer script (`tools/queue-sim`), so the patient app can be built and tested end to end.

---

## Repository structure

```
asani/
├── README.md                 ← you are here
├── AGENTS.md                 ← rules for AI coding agents (Codex, Claude Code)
├── CLAUDE.md                 ← points Claude Code to AGENTS.md
├── PRD.md                    ← what we are building and why
├── DESIGN.md                 ← UI/UX: screens, components, colors, copy
├── ARCHITECTURE.md           ← system design, data flow, Cloud Functions
├── DATABASE.md               ← Firestore collections, fields, indexes
├── docs/
│   ├── 01-project-implementation.md
│   ├── 02-setup.md
│   ├── 03-feature-development.md
│   ├── 04-authentication-and-security.md
│   ├── 05-mcp-connection.md
│   ├── 06-integration.md
│   ├── 07-testing-and-qa.md
│   └── 08-debugging.md
├── apps/
│   └── patient_app/          ← Flutter app (Android + iOS)
├── packages/
│   └── asani_core/           ← shared Dart models & constants (reused by desktop later)
├── functions/                ← Cloud Functions (TypeScript)
├── tools/
│   ├── queue-sim/            ← dev script: advance the queue without the desktop app
│   └── admin-scripts/        ← onboard clinics, seed data
├── firebase.json
├── firestore.rules
└── firestore.indexes.json
```

---

## Quick start

Full guide: [`docs/02-setup.md`](docs/02-setup.md)

```bash
# 1. Install dependencies
cd apps/patient_app && flutter pub get
cd ../../functions && npm install

# 2. Start Firebase emulators (Auth, Firestore, Functions)
cd .. && firebase emulators:start --import=./emulator-data --export-on-exit

# 3. Seed a demo clinic + doctors
cd tools/admin-scripts && node seed-dev.js

# 4. Run the app against the emulators
cd ../../apps/patient_app
flutter run --dart-define=ENV=dev --dart-define=USE_EMULATOR=true

# 5. Move the queue forward (simulates the receptionist)
cd ../../tools/queue-sim && node queue-sim.js next --doctor <doctorId>
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

## Tech stack (Phase 1)

- **App:** Flutter (stable, Dart 3.9+), Android + iOS
- **State management:** Riverpod · **Navigation:** go_router
- **Backend:** Firebase Auth (phone OTP), Cloud Firestore, Cloud Functions (TypeScript, Node 20+), Firebase Cloud Messaging, Crashlytics, App Check
- **Region:** `asia-south1` (Mumbai), the closest Firebase region to Pakistan
- **Language:** English only (UI)

---

## Owner

Sarbuland (GitHub: `sarbuland-dev`)
