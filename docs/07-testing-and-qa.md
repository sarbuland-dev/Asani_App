# 07 — Testing and QA

> **D-52 (2026-11-27): the backend is Supabase; the Firebase backend (Firestore, Cloud Functions, rules, emulators) was
> removed.** Parts of this file still describe the Firebase way and are kept as background only. Current sources:
> docs/10-supabase-migration.md, DATABASE.md, ARCHITECTURE.md, docs/02 §2b (setup), TESTING_CHECKLIST.md.

What is tested, how, and the manual QA scripts that must pass before any release.

---

## 1. Test pyramid

| Level | Tool | What | Where |
|---|---|---|---|
| Unit (Dart) | `test` | `asani_core` models, availability, date (PKT), patients-ahead, validators | `packages/asani_core/test/` |
| Unit (TS) | Jest/Vitest | Notification step logic, validators, date helpers | `functions/test/unit/` |
| Function integration | Jest + Firebase emulators | `bookToken`, `cancelToken`, triggers, scheduled jobs | `functions/test/integration/` |
| Security rules | `@firebase/rules-unit-testing` | Every allow/deny in `firestore.rules` | `functions/test/rules/` |
| Widget | `flutter_test` + Riverpod overrides | Screens in loading/empty/error/data states | `apps/patient_app/test/` |
| Integration (app) | `integration_test` against emulators | Login → book → queue moves → token screen updates | `apps/patient_app/integration_test/` |
| Manual | Real devices | Push, OTP, permissions, MIUI, iOS | §5 scripts |

Coverage goals: `asani_core` ≥ 90%, functions business logic ≥ 85%. UI coverage is not a goal; state coverage is.

---

## 2. Must-have automated tests

### `asani_core`
- `doctorAvailability(doctor, date, day, now)` returns: available / notStarted / onLeave / noSchedule / full / sessionEnded. Include PKT midnight edges.
- `patientsAhead(activeNumbers, myNumber)`: empty list, I'm first, gaps from cancellations.
- `estimatedWait(ahead, avgMinutes)` formatting ("about 25 min", "less than 5 min").
- `ageFromBirthYear`, phone validation (`+923XXXXXXXXX`).
- Specialities (D-31): every key has a label and icon; unknown key → `other`; old free-text values map to the right key.
- `distanceKm(a, b)` (haversine): same point = 0; Johar Town ↔ DHA Lahore ≈ 14 km (±1).
- Doctor search order: with location → nearest first; without → same area first, then the rest A–Z by area.
- Grouping (D-32): two records with the same `doctorGroupId` → one card, nearest as main, other in "Also sits at"; inactive or other-city members left out; no group → separate cards.
- PMDC format check: `12345`, `12345-P`, ` 12345-p ` (normalised to `12345-P`) ✅; `abc`, `12-34-5`, empty string when typed ❌.
- `nameKey`: "Dr. Ayesha Malik", "dr ayesha  malik", "Ayesha Malik." → `ayesha malik`.

### Doctor linking functions (D-32)
- `saveDoctor`: same PMDC at another clinic → `strong` suggestion; same `nameKey` + speciality → `weak`; weak upgraded to strong when PMDC matches later; **no** suggestion for the same clinic, or for a pair that is `notSame` / `unlinked`; the doctor is saved and active either way.
- `saveDoctor` rejects a free-text speciality and a badly formatted PMDC number.
- `adminLinkDoctors`: both get one `doctorGroupId`; linking into an existing group reuses it; second call on the same pair is a no-op; activity log entry written.
- `adminMarkNotSame`: status `notSame`; re-saving either doctor never recreates the pair.
- `adminUnlinkDoctor`: clears the record's group (and the last member's); pair status `unlinked`; re-saving never re-suggests it; activity log entry written.
- `saveDoctor` never writes `pmdcNumber` to the public doctor document; doctor list responses carry `hasPmdc` only.
- No suggestion for doctors in different cities.
- All three: clinic login → `permission-denied`.

### `bookToken`
- ✅ Happy path returns number 1, then 2.
- ✅ **Concurrency:** fire 20 parallel bookings for the same doctor/day → numbers are exactly 1..20, no duplicates.
- ❌ BR-1 suspended clinic → `clinic-unavailable`
- ❌ BR-2 leave day / no schedule → `doctor-unavailable`
- ❌ BR-3 after session end → `session-ended`
- ❌ BR-4 full → `tokens-full`
- ❌ BR-5 same patient twice → `duplicate-token` with existing number
- ❌ BR-6 6th active token → `too-many-active`
- ❌ patient owned by another user → `permission-denied`
- ❌ unauthenticated → `unauthenticated`
- ❌ invalid date format / unknown fields → `invalid-argument`

### Notifications (trigger logic, FCM mocked)
- Queue moves one by one: token #11 gets `ahead3`, `ahead2`, `ahead1`, `yourTurn`, **exactly 4 sends**.
- Jump (skip two tokens): goes 3 → 1 ahead: only `ahead1` sent; `ahead2` marked without sending.
- Booked with 2 ahead: first send is `ahead2` (N-4).
- Trigger runs twice for the same change: no duplicate sends.
- Cancelled tokens don't count as ahead; cancelling a token ahead advances others' steps correctly.
- Walk-in token (`bookedByUserId: null`): no sends.
- Invalid FCM token → device doc deleted.
- D-34 skip push: copy is "You missed your turn" / "Token A-7 · Go to reception to be called next." (`skipNotice.test.ts`); skipping twice sends it once (`skipNotifiedAt`).
- D-35 repeat turn: skip after "Your turn now" clears `yourTurn` once and sets `turnRepeatUsed`; a second skip does not clear it again; a skip before the patient was called clears nothing (`turnRepeatOnSkip`).
- D-35 app: Skipped stays live today and is not live on a past day; `isNextUp` only for Arrived + `priorityAt` (`asani_core/test/live_token_test.dart`).

### `onTokenWrite` counters
- `activeNumbers` sorted and correct after book / arrive / call / cancel / skip / hold / noShow.

### Rules (each with allow + deny case)
- users: read own ✅ / other ❌; create with someone else's phone ❌; role ≠ patient ❌; update `role` or `phone` ❌.
- devices: own ✅ / other ❌; extra fields ❌.
- patients: create own ✅; create with another phone ❌; second `self` ❌; edit other's ❌; delete ❌; soft delete self ❌; change `ownerUid` ❌.
- clinics/doctors/days: read signed-in ✅; unauthenticated ❌; any write ❌; `clinics/*/private/*` read ❌.
- tokens: read own (`bookedByUserId`) ✅; read via `patientOwnerUid` ✅; read other ❌; any client write ❌; query without owner filter ❌.
- followUps: own ✅ / other ❌ / write ❌.
- doctors/{id}/private/admin: super admin read ✅; clinic login read ❌ (even its own doctor); patient read ❌; any client write ❌.
- doctorLinkSuggestions: super admin read ✅; clinic login read ❌; patient read ❌; any client write ❌.
- doctors: patient query `city + speciality + active` ✅; clinic login writing `doctorGroupId` ❌.

### Widget tests
- Token screen: booked / called / completed / cancelled / not started / offline.
- Clinic page: available, on leave, full, suspended clinic.
- Booking confirm: error code → correct message (DESIGN §7).

---

## 3. Running tests

```bash
# Dart
cd packages/asani_core && dart test
cd apps/patient_app && flutter test

# Backend: see the Supabase block below (the Firebase functions and rules tests were removed, D-52)
```

**Supabase (D-52)**: pgTAP tests in `supabase/tests/database/*.test.sql` run against the `asani-dev` cloud database
inside a transaction that is rolled back (needs `supabase/.db-url.local`, docs/02 §2b):

```powershell
node tools/db-test/run.js            # 01 RLS (37), 02 booking + queue (59)
node tools/db-test/concurrency.js    # 20 bookings on 10 connections at once → numbers 1..20, no duplicates
node tools/db-test/client-smoke.js   # the patient app's calls through the public API: RLS, RPCs, Realtime
node tools/db-test/admin-login-smoke.js  # admin-clinic-login Edge Function: refusals + rollback, no real email
```

`concurrency.js` must commit, so it creates its own `cc_` rows and deletes only those afterwards.
Every new Postgres function or policy gets a pgTAP test in the same change.

CI (GitHub Actions) on every PR: `flutter analyze`, `flutter test`, `dart test` (core); `supabase.yml`: SQL syntax + pgTAP (needs the `SUPABASE_DB_URL` secret).

---

## 4. Test devices

| Device | Why |
|---|---|
| **Redmi (physical)** | Main Android device, MIUI notification behaviour, real-world performance |
| Android emulator API 26 | Minimum supported version |
| Android emulator API 35 | Latest permissions (POST_NOTIFICATIONS) |
| iPhone (physical, via TestFlight) | Push via APNs, phone auth, App Attest |
| Small screen (≤ 5.5") + text scale 1.3× | Layout overflow |

---

## 5. Manual QA scripts

Run on Redmi and iPhone before every release. Use `asani-dev` + queue-sim.

### QA-1 Login
1. Fresh install → phone entry → invalid number shows error, button disabled.
2. Valid number → OTP arrives (real SMS on dev, or test number).
3. Wrong OTP → error; correct OTP → name & consent screen.
4. Can't continue without consent checkbox.
5. Kill app → reopen → still logged in, lands on Home.
6. Logout → login again → no name screen.

### QA-2 Discovery
1. Home lists Lahore clinics; search "shifa" and an area name.
2. Change city → list updates; empty city shows empty state.
3. Clinic with one doctor → its clinic page shows (D-66); **Book token** starts booking.
4. Doctor on leave / full / not started labels are correct.
5. Suspended clinic → banner, no book buttons.

### QA-2b Search by doctor (D-31)
1. Search shows **Clinics | Doctors** tabs; the Clinics tab works exactly as before.
2. First open of Doctors → location primer → Allow → system popup. Pick "Heart (Cardiologist)" → heart doctors in Lahore, nearest first, with km.
3. Deny location → same area first, then the rest; no km; "Turn on location" note shown.
4. Doctors not available today come last, greyed, with **Book another day**; clinics without a location come after the others without km.
5. Card shows clinic + area, available today, timing, booked / max, now serving, wait; numbers match the clinic page.
6. Book token from the card → booking for that clinic + doctor; book for a future date too.
7. Speciality with no doctors in the city → empty state → [Search clinics] switches tab.
8. Change city → list follows the city. Suspended clinic's doctors are not shown.
9. Clinic web: Add doctor offers only the speciality picker; Save clinic settings without a location is blocked.

### QA-2c Same doctor at two clinics (D-32)
1. Add "Dr. Test Same" with PMDC `12345-P` at Clinic A and at Clinic B → both bookable at once; app shows **two** cards.
2. Super Admin → Doctors → strong suggestion with both records side by side → **Link** → app shows **one** card, nearest clinic main, "Also sits at: Clinic B"; tap it → booking at Clinic B.
3. Same name + speciality, no PMDC → **weak** suggestion → **Not the same** → edit and re-save either doctor → never suggested again.
4. **Unlink** → two cards again. Activity log shows Link, Not the same and Unlink.
5. Clinic login never sees suggestions, the other clinic's doctor, or any PMDC number (its own shows "on file").
6. Patient app: the doctor documents it reads contain no `pmdcNumber` (check in the network tab / emulator UI).

### QA-3 Booking
1. Book for Self today → token screen with number.
2. Book for Mother (new profile from the bottom sheet) → token in her name.
3. Try booking Mother again same doctor/day → duplicate message with her number.
4. Two phones book the same doctor within the same second → different numbers.
5. Airplane mode at confirm → "No internet…" and no token created.
6. Cancel token → status Cancelled; it disappears from Active.

### QA-4 Live queue + notifications (most important)
Setup: book token #6 for doctor X; queue-sim `start`.
| Step | queue-sim action | Expected on phone |
|---|---|---|
| 1 | `next` → #1 called | Token screen: Now serving #1, 4 ahead. **No notification** |
| 2 | `next` → #2 | 3 ahead → notification "3 patients ahead of you" |
| 3 | `next` → #3 | "2 patients ahead of you" (replaces previous in tray) |
| 4 | `next` → #4 | "You're next" |
| 5 | `next` → #5 | 0 ahead (#5 is with the doctor). **No notification** |
| 6 | `next` → #6 | "Your turn now"; screen turns to Called state |
Total queue notifications received: **4**.

Repeat with: app in foreground, background, killed; phone locked; Redmi with battery saver on.
Jump test: from 4 ahead, `skip` two tokens → only the applicable step arrives.
Tap each notification → opens the right token screen.

### QA-4b Skipped patient (D-24, D-34, D-35)
Setup: book token #6 from the app, do **not** check in; clinic web Queue Board for doctor X.
| Step | Clinic web action | Expected |
|---|---|---|
| 1 | Next until #6 is due → "not arrived" → **Skip** | Phone: push "You missed your turn · Token #6 · Go to reception to be called next" (once). Token screen: amber "Your turn passed · Go to reception" card, slip buttons still there, **no** Book again. Tokens tab: still under **Active**, chip "Turn passed" |
| 2 | Skip #6 again after recalling it (or press Skip on another device) | **No** second skip push |
| 3 | Check in #6 by code (or "Arrived · call next") | Board: #6 right under the Called patient with a **Next up** label. Phone: "You're next · called right after the current patient", Ahead = 0 |
| 4 | **Next** | #6 is called. Phone: "Your turn now" (first time, if #6 was skipped before being called) |
| 5 | Variant: call #6 (gets "Your turn now"), **Skip**, check in, **Next** | Phone gets "Your turn now" **once more**; a second skip → recall gives **no** third one |
| 6 | Session ends with #6 still Skipped | Token leaves Active (Past) like other tokens |

### QA-5 Family & history
1. Add, edit, remove a profile; Self can't be removed.
2. Duplicate name warning appears for "Shazia" vs "Shazia Begum".
3. Completed tokens appear in profile history with wait time.

### QA-6 Follow-ups
1. `create-followup.js --days 1` → tomorrow 9 AM reminder (or trigger the function manually in the emulator).
2. Tap reminder → booking pre-filled; confirm → follow-up status `booked`.

### QA-7 Account
1. Deny notifications → token screen shows "Notifications are off" card → "Turn on" opens settings.
2. Delete account → confirm with "DELETE" → logged out; logging in again creates a fresh account.

### QA-8 Accessibility & resilience
1. Text scale 1.3× on every screen: no overflow.
2. TalkBack/VoiceOver reads token number and status.
3. Kill network on the token screen → offline banner, last update time shown; reconnect → live again.

---

## 6. Bug reports

Template (GitHub issue):
```
Title: [Token screen] number overflows at 1.3x text

Device / OS / app version:
Build: dev / prod
Steps:
Expected:
Actual:
Screenshots / screen recording:
Crashlytics link (if crash):
```
Severity: **S1** blocks booking/login/notifications · **S2** wrong data shown · **S3** UI issue · **S4** cosmetic. S1/S2 block a release.
