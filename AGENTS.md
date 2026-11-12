# AGENTS.md — Instructions for AI coding agents

This file is for **Codex, Claude Code and any other AI agent** working on Asani. Read it completely before writing code. If anything here conflicts with a request, stop and ask.

---

## 1. Project in one paragraph

Asani is a clinic token and live-queue system for small and medium private clinics in Pakistan. Patients use a Flutter app (Android + iOS) to search a clinic, pick a doctor at that clinic, book a token for themselves or a family member, watch the live queue and get notified when their turn is near. The backend is Firebase (Auth with phone OTP, Firestore, Cloud Functions in TypeScript, FCM). The owner is **Sarbuland**.

---

## 2. Current scope — READ THIS FIRST

| Part | Status | Agent rule |
|---|---|---|
| `apps/patient_app` | ✅ Active | Build here |
| `functions/` | ✅ Active | Only functions the patient app needs (see ARCHITECTURE.md §5) |
| `packages/asani_core` | ✅ Active | Shared models only |
| `tools/queue-sim`, `tools/admin-scripts` | ✅ Active | Dev tooling |
| `apps/clinic_web` | 🟡 Phase 2 (demo backend) | Flutter Web clinic dashboard **and** super admin panel (PRD-CLINIC-WEB.md). UI runs on an in-memory demo backend; Firebase wiring not started |
| Clinic desktop (.exe) | ⛔ Dropped | Replaced by Flutter Web (D-06 updated). **Do not create** `apps/clinic_desktop` |

The clinic side is **Flutter Web** in Chrome (PRD-CLINIC-WEB.md D-06). Super admin screens live inside the same web app, shown by role (D-15).

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
2. **Flow:** search **clinic** first → pick a **doctor at that clinic**. There is **no direct doctor search**.
3. **Platforms:** patient app is Flutter for **Android and iOS**.
4. **Language:** English UI only.
5. **Patient identity:** the phone number identifies the *family account*; each patient is a *profile* (`patients` collection). Tokens point to `patientId`.
6. **Token numbers** are assigned only by the `bookToken` Cloud Function inside a transaction. The client never writes a token number.
7. **Clinic staff** log in to the clinic web with **email + password** and set their own password from an invite email (PRD-CLINIC-WEB.md D-07 updated). Roles come from custom claims set only by Cloud Functions.

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
- **Structure:** feature-first (see ARCHITECTURE.md §4). UI never calls Firebase directly; it goes **UI → provider → repository → Firebase**.
- Models live in `packages/asani_core`, with `fromMap`/`toMap`. Dates are stored as Firestore `Timestamp`; queue day IDs are `yyyy-MM-dd` in **Asia/Karachi** time.
- Use theme tokens from `lib/core/theme/` only. No hard-coded colors or font sizes in widgets.
- Every async screen handles **loading, empty, error and offline** states (DESIGN.md §6).
- No `print`. Use the `AppLogger` in `lib/core/utils/logger.dart`.

### Cloud Functions
- TypeScript, Node 20+, Firebase Functions v2, region `asia-south1`.
- Validate every callable input. Throw `HttpsError` with clear codes.
- Anything that must be atomic (token numbers, queue counters) uses a Firestore **transaction**.
- Triggers must be **idempotent** (safe to run twice).

### Firestore
- Schema source of truth: **DATABASE.md**. Change DATABASE.md in the same PR as any schema change.
- Every new query needs an index check; add it to `firestore.indexes.json`.
- Security rules change → add or update a rules test (docs/07).

---

## 7. Safety rules

- **Never** run commands against the production Firebase project (`asani-prod`). Use emulators or `asani-dev`.
- **Never** commit `serviceAccount*.json`, `.env`, keystores, `GoogleService-Info.plist` for prod, or any secret.
- **Never** deploy (`firebase deploy`) unless Sarbuland asks in that session.
- **Never** delete data, collections or users without explicit permission.
- **Never** loosen security rules "to make it work". Find the real cause (docs/08).
- Through MCP (docs/05), Firebase tools are for **dev only**.

---

## 8. Commands

```bash
# App
cd apps/patient_app
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=ENV=dev --dart-define=USE_EMULATOR=true

# Functions
cd functions
npm run lint
npm run build
npm test                       # runs against emulators

# Emulators (from repo root)
firebase emulators:start --import=./emulator-data --export-on-exit

# Rules tests
cd functions && npm run test:rules

# Queue simulator (acts as receptionist)
cd tools/queue-sim
node queue-sim.js status --doctor <doctorId>
node queue-sim.js next   --doctor <doctorId>
```

---

## 9. Definition of done (every task)

- [ ] Behaviour matches PRD.md; anything unclear was confirmed (§3)
- [ ] UI matches DESIGN.md (tokens, states, copy)
- [ ] `flutter analyze` has zero warnings; `flutter test` passes
- [ ] Functions: `npm run lint && npm run build && npm test` pass
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
