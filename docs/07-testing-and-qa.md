# 07 — Testing and QA

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

### `onTokenWrite` counters
- `activeNumbers` sorted and correct after book / arrive / call / cancel / skip / hold / noShow.

### Rules (each with allow + deny case)
- users: read own ✅ / other ❌; create with someone else's phone ❌; role ≠ patient ❌; update `role` or `phone` ❌.
- devices: own ✅ / other ❌; extra fields ❌.
- patients: create own ✅; create with another phone ❌; second `self` ❌; edit other's ❌; delete ❌; soft delete self ❌; change `ownerUid` ❌.
- clinics/doctors/days: read signed-in ✅; unauthenticated ❌; any write ❌; `clinics/*/private/*` read ❌.
- tokens: read own (`bookedByUserId`) ✅; read via `patientOwnerUid` ✅; read other ❌; any client write ❌; query without owner filter ❌.
- followUps: own ✅ / other ❌ / write ❌.

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

# Functions + rules (starts emulators automatically)
cd functions
npm test                    # unit + integration
npm run test:rules
# script: "test:rules": "firebase emulators:exec --only firestore 'jest test/rules'"

# App integration test on a device/emulator with emulators running
cd apps/patient_app
flutter test integration_test --flavor dev --dart-define=USE_EMULATOR=true
```

CI (GitHub Actions) on every PR: `flutter analyze`, `flutter test`, `dart test` (core), `npm run lint && npm run build && npm test && npm run test:rules`.

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
3. Clinic with one doctor → goes straight to booking.
4. Doctor on leave / full / not started labels are correct.
5. Suspended clinic → banner, no book buttons.

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
