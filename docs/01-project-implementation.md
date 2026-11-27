# 01 — Project Implementation Plan

Where the product stands, what was built in which order, and what comes next. Updated 2026-11-27 after the move to
Supabase (PRD D-52, docs/10-supabase-migration.md). Open items live in REMAINING_WORK.md.

---

## 1. Parts of the product

| Part | What | Status |
|---|---|---|
| Patient app | Flutter, Android + iOS: email login, clinic / doctor search, booking, live queue, family, follow-ups, notifications | Functionality done; full UI being built from the screens board |
| Clinic web | Flutter Web: queue board, walk-ins, check-in, patients, doctors, follow-ups, upcoming bookings, billing, settings | Functionality done (basic UI for the newest parts) |
| Super Admin | Inside the clinic web, by role: clinics, logins, plans, payments, defaulters, same-doctor links | Functionality done |
| Backend | Supabase: Postgres + RLS + functions, Realtime, Edge Functions, pg_cron; FCM for push | Done on `asani-dev` |
| Later | SMS / WhatsApp, payment proof uploads, analytics, medical records with consent | Not started |

The Windows desktop app was dropped for the web (D-06). The Firebase backend was removed (D-52).

---

## 2. How it was built (milestones)

| Milestone | Content | Done |
|---|---|---|
| M0 Foundation | Monorepo (`apps/`, `packages/asani_core`, `packages/asani_ui`), demo backend, theme, router | ✅ |
| M1 Discovery + booking | Search, clinic page, booking rules BR-1…BR-7, live token screen, cancel | ✅ |
| M2 Notifications | 3 / 2 / 1 ahead + Your turn (D-04), skip / cancel notices (D-23, D-34), inbox (D-45), MIUI guidance | ✅ (real-phone push re-test on Supabase pending) |
| M3 Clinic web | Board, walk-ins, check-in, doctors, PIN, billing, Super Admin | ✅ |
| M4 Doctor search | Specialities, distance, same-doctor links (D-31…D-33) | ✅ (Material Symbols icons open) |
| M5 Supabase (D-52) | 8 phases: schema + RLS, booking + queue, push + cron, email login, app data, clinic backend, clinic web, clean-up | ✅ |
| M6 UI to the board | Patient app screens P1…P9 and the web screens, batch by batch (D-43, D-50) | In progress |
| M7 Pilot | Email + domain, prod project, store releases, pilot clinic | Next |

---

## 3. How each feature is built

Every feature follows **docs/03**: understand → confirm unclear behaviour with Sarbuland → branch → database
(migration + RLS + pgTAP test) → repository → providers → screens (all states) → test → docs → merge.
Current phase rule: **functionality first, basic UI**; the polished UI follows the screens board.

---

## 4. Branches and releases

- `main` is the only long-lived branch. One short branch per task (`feature/…`, `fix/…`, `docs/…`, `chore/…`), merged
  into `main` when done, then deleted (AGENTS.md §2).
- Database changes go out as new migrations (`supabase db push`), only when Sarbuland asks, before an app release
  that needs them.
- Versioning: `MAJOR.MINOR.PATCH+BUILD` (e.g. `0.3.0+12`).

---

## 5. Risks before the pilot

| Risk | Mitigation |
|---|---|
| Free Supabase project pauses after a week without use; no daily backups | Decide Pro plan or keep-alive + backups before the pilot (S-7) |
| Login codes in spam / email limits | Brevo now; own domain with SPF / DKIM before the pilot (Q-06) |
| Phone numbers are not verified | One phone = one account; walk-ins linked only in person (D-52) |
| MIUI kills notifications | High-priority FCM, in-app Autostart guide, test on Redmi / Vivo each release |
| No Mac for iOS builds | Codemagic or a borrowed Mac; Android first |
| Scope creep | Anything not in the PRD → confirm first, record in the decisions log |

---

## 6. Pilot exit criteria

- All P0 features pass TESTING_CHECKLIST.md on a real phone and in Chrome
- Prod Supabase project (Mumbai) + prod Firebase for FCM, own email domain
- Crash-free sessions ≥ 99% in internal testing
- One pilot clinic live with its doctors and a trained receptionist
