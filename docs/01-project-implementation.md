# 01 — Project Implementation Plan (Patient App)

How Phase 1 is built, in what order, and what "done" means for each milestone.

---

## 1. Phases of the whole product

| Phase | What | Status |
|---|---|---|
| **1** | Patient app (Android + iOS) + backend it needs + queue-sim | **Now** |
| 2 | Clinic Windows desktop app (reception, doctor, printing, walk-ins, staff password login) | After Phase 1. Tech decision pending (Q-01) |
| 3 | Super admin panel (clinics, staff activity, subscriptions, defaulters) | After Phase 2. Location pending (Q-02) |
| 4 | SMS/WhatsApp tokens, analytics, AI features, medical records with consent | Later |

---

## 2. Phase 1 milestones (about 8 weeks)

Estimates assume one developer working with an AI agent part-time alongside university.

### M0: Foundation (week 1)
- [ ] Create GitHub repo `asani` (private) with the structure from README.md
- [ ] Create Firebase projects `asani-dev` and `asani-prod` (Blaze, budget alerts, **Firestore location asia-south1**)
- [ ] Flutter app scaffold `apps/patient_app` with flavors/env (`ENV=dev|prod`), Riverpod, go_router, theme tokens
- [ ] `packages/asani_core` with models + enums from DATABASE.md
- [ ] `functions/` TypeScript scaffold, lint, emulator config
- [ ] `firestore.rules` (deny-all base + app rules), `firestore.indexes.json`
- [ ] `tools/admin-scripts/seed-dev.js` (2 clinics, 4 doctors, schedules)
- [ ] `tools/queue-sim` (status, start, next, arrive, skip, hold, end)
- [ ] MCP servers connected (docs/05)

**Done when:** `flutter run` shows an empty Home connected to emulators; seed + queue-sim work.

### M1: Auth (week 2)
- [ ] F-01 phone entry, OTP, name & consent screens
- [ ] `linkPatientProfiles` callable
- [ ] `users` doc + Self profile creation
- [ ] Router auth guard and splash
- [ ] App Check (debug provider in dev)

**Done when:** login works on a real Redmi with a real SMS (dev project) and on the emulator with emulator OTP.

### M2: Discovery (week 3)
- [ ] F-02 Home, city selector, recent clinics, clinic list, search
- [ ] F-03 Clinic page with doctor cards and live queue info
- [ ] Availability logic (schedule, leave, full, session state) in `asani_core`, with unit tests

### M3: Booking (weeks 4–5)
- [ ] F-07 family profiles (needed for booking): list, add/edit, duplicate warning
- [ ] F-04 booking flow (patient → date → confirm)
- [ ] `bookToken` with all rules BR-1..BR-7 + tests (including concurrent booking test)
- [ ] F-05 live token screen
- [ ] `cancelToken`
- [ ] `onTokenWrite` maintaining `activeNumbers` / `waitingCount`

**Done when:** two devices booking the same doctor at the same time get different numbers; queue-sim `next` updates the token screen in ≤ 3 s.

### M4: Notifications (week 6)
- [ ] FCM setup Android + iOS (APNs key), device registration
- [ ] `onQueueDayWrite` / `onTokenWrite` notification logic (3, 2, 1 ahead + Your turn)
- [ ] Notification tap → token screen (foreground, background, terminated)
- [ ] Permission primer (S-17), "notifications off" card
- [ ] Xiaomi/MIUI testing (autostart, battery saver) and in-app guidance

**Done when:** the full notification test script in docs/07 §5 passes on Redmi and an iPhone.

### M5: History, follow-ups, account (week 7)
- [ ] F-08 Tokens tab (Active/Past), profile history
- [ ] F-09 follow-ups list + `followUpReminders` scheduled function + pre-filled booking
- [ ] F-10 Account screen, logout, `deleteAccount`
- [ ] F-12 Crashlytics + analytics events

### M6: Hardening and pilot release (week 8)
- [ ] Full QA pass (docs/07), accessibility check at 1.3× text
- [ ] Production rules + App Check enforcement
- [ ] Privacy policy + terms pages hosted
- [ ] Play Store internal testing track, TestFlight
- [ ] Onboard pilot clinic data into `asani-prod` with admin script
- [ ] Pilot: queue driven by queue-sim operated by the developer **or** wait for Phase 2 desktop (decide with clinic)

---

## 3. Work breakdown per feature

Each feature follows docs/03. Order inside a feature:

1. Read PRD + DESIGN section; list unclear points → **confirm with Sarbuland**
2. Models / enums in `asani_core` (+ tests)
3. Function(s) and rules (+ emulator tests)
4. Repository
5. Providers
6. Screens + states
7. Manual test on device
8. Update docs if anything changed

---

## 4. Branching and releases

- `main`: always buildable. Protected.
- `feature/F-04-booking`, `fix/token-screen-offline`, `chore/...`
- Small PRs (one feature or less). PR template = Definition of Done from AGENTS.md §9.
- Versioning: `MAJOR.MINOR.PATCH+BUILD` (e.g. `0.3.0+12`). Tag releases `app-v0.3.0`, `functions-v0.3.0`.
- Functions and rules are deployed **before** an app release that depends on them.

---

## 5. Risks for Phase 1

| Risk | Mitigation |
|---|---|
| No Mac for iOS builds | Use Codemagic (cloud macOS CI) or a borrowed Mac for signing; test Android first |
| Phone OTP cost / abuse | App Check, SMS region policy (allow only Pakistan), Firebase budget alert |
| MIUI kills notifications | High-priority FCM, in-app "Allow autostart" guide, test on Redmi each release |
| Desktop not ready for pilot | queue-sim can run the pilot queue from a laptop if needed |
| Scope creep | Anything not in PRD → Decisions log + confirmation first |

---

## 6. Phase 1 exit criteria

- All P0 features done and passing QA
- Crash-free sessions ≥ 99% on internal testing
- One pilot clinic's data live in `asani-prod`
- Desktop technology decision (Q-01) taken, so Phase 2 can start
