# PRD — Asani Patient App (Phase 1)

| | |
|---|---|
| **Product** | Asani: smart clinic token & live queue |
| **Document** | Product Requirements, Patient App |
| **Version** | 0.1 (draft) |
| **Date** | 2026-11-07 |
| **Owner** | Sarbuland |
| **Status** | Patient app in scope. Desktop app and super admin panel are later phases. |

---

## 1. Problem

In small private clinics in Pakistan, the queue is managed with a register or paper slips:

- Patients wait 1–2 hours without knowing when their turn will come.
- They cannot leave the clinic even briefly, in case they miss their turn.
- "I came first" disputes are common.
- Receptionists spend time answering phone calls about token numbers.
- Doctors have no clear data on patient load or returning patients.

## 2. Solution (this phase)

A **patient mobile app** that lets a patient:

1. Find a clinic → pick a doctor at that clinic
2. Book a token for themselves or a family member
3. See the live queue ("Now serving #7 · You are #11")
4. Get notified when their turn is near, so they can arrive on time
5. See their family's visit history and follow-ups

The clinic side (desktop app) comes next. Until then the queue is moved by a developer tool (`tools/queue-sim`), which writes exactly what the desktop app will write later.

## 3. Goals and non-goals

### Goals (Phase 1)
- G1: A patient can go from opening the app to holding a token in **under 60 seconds** (returning user).
- G2: Live queue position updates within **3 seconds** of the queue moving.
- G3: Queue notifications reach the patient reliably on Android (including Xiaomi/MIUI) and iOS.
- G4: Family members are booked under their own name, not the account owner's.

### Non-goals (Phase 1)
- Clinic desktop app, receptionist screens, printing (Phase 2)
- Super admin panel, invoices, subscriptions, activity logs (Phase 3)
- Payments inside the app (patients never pay)
- Medical records, prescriptions, diagnosis (Stage 3, needs consent and legal review)
- Direct doctor search across clinics (**will not be built**, decided)
- Urdu UI (decided: English only)
- SMS/WhatsApp tokens, AI features

## 4. Users

| User | Description | Phase 1 needs |
|---|---|---|
| **Account owner** | Person who logs in with their phone number. Often books for parents/children. | Fast booking, clear notifications |
| **Patient (profile)** | The person who will see the doctor. May never use the app (e.g. elderly mother). | Correct name/age/gender on token |
| **Clinic staff** | Receptionist/doctor | Not in this phase. Represented by `queue-sim`. |

Design for older and less tech-comfortable users: large text, few steps, clear status.

## 5. Features and requirements

Priority: **P0** = MVP must-have · **P1** = in Phase 1 if time allows · **P2** = later

### F-01 Phone OTP login (P0)
- On the very first launch, three short intro pages explain the app before login; they can be skipped and are not shown again (D-16).
- User enters a Pakistani mobile number (`+92` prefix fixed, 10 digits after it, starting with `3`).
- Receives a 6-digit OTP via Firebase Phone Auth; auto-read on Android where possible.
- Resend OTP after 60 seconds. Clear error messages for wrong code, expired code, too many attempts.
- First login ("Tell us about you"): ask for the user's **name, age and gender**, accept the **Terms and Privacy Policy** (checkbox, links). A `self` patient profile is created from this (D-15). "Use another number" signs out.
- The number field accepts `3001234567`, `03001234567`, `923001234567` and `+92 300 1234567`. Resend is limited to 3 times per login.
- After login, call `linkPatientProfiles`: any patient profiles created earlier for this phone number (e.g. by a receptionist in future) are attached to the account.
- Session persists; the user stays logged in until logout.

**Acceptance:** valid number + correct OTP → Home. Wrong OTP → error, can retry. Returning user is not asked for name again.

### F-02 Clinic search and discovery (P0)
- Home shows: search bar, **active token banner** (if any), **Recent clinics** (where the user booked before, latest first, max 5), then **All clinics** in the user's city.
- City: default **Lahore**; user can change the city from a selector (only cities that have clinics).
- Search matches clinic **name** or **area** (case-insensitive, partial match).
- Only clinics with status `active`, `pilot` or `grace` are listed. `suspended` clinics are hidden from search but still visible in Recent with a "Online booking not available" state.
- Clinic card: name, area, number of doctors, "Open today" / "Closed today".

**Acceptance:** typing "shifa" shows "Al-Shifa Clinic"; typing "johar" shows clinics in Johar Town.

### F-03 Clinic page and doctor selection (P0)
- Shows clinic name, address, phone (tap to call), and the **list of active doctors**.
- Each doctor card shows: name, speciality, today's timing, availability badge and **live queue** (now serving, number waiting, estimated wait).
- Availability states: `Available today`, `Not started yet` (session later today), `On leave today`, `Not available today` (no schedule), `Tokens full`.
- If the clinic has **exactly one doctor**, skip the list and go straight to booking for that doctor.
- No direct doctor search across clinics.

### F-04 Book a token (P0)
Flow: **Doctor → Who is the patient? → Date → Confirm → Token**

1. **Who is the patient?** List of the account's profiles (Self first). Option "+ Add family member" (F-07 form inline).
2. **Date:** Today + the next days allowed by the doctor's `bookingWindowDays` (default 7). Days with no schedule, leave, or full tokens are disabled with a reason.
3. **Confirm:** clinic, doctor, patient name, date, expected token number not shown (assigned on confirm).
4. On confirm, the app calls `bookToken`. On success show the **Token screen** with the assigned number.

**Business rules (enforced in `bookToken`):**
- BR-1: Clinic status must be `active`, `pilot` or `grace`.
- BR-2: Doctor must be active, scheduled that day, and not on leave.
- BR-3: Same-day booking is allowed until the doctor's session **end time**.
- BR-4: Tokens for a doctor/day cannot exceed `maxTokensPerDay`.
- BR-5: One patient profile can hold only **one active token per doctor per day**. (Active = `booked`, `arrived`, `called`, `onHold`.)
- BR-6: One account can hold at most **5 active tokens in total** (abuse protection).
- BR-7: Token numbers are sequential per doctor per day, starting at 1, shared with walk-ins (future desktop).

**Acceptance:** two users booking the same doctor at the same moment never get the same number.

### F-05 Live token screen (P0)
- Big token number, patient name, doctor, clinic, date.
- Live: **Now serving #N**, **patients ahead of you**, **estimated wait** (= patients ahead × doctor's `avgConsultMinutes`, shown as "about 25 min").
- Status chip: Booked · Arrived · Called (your turn) · Completed · Cancelled · No-show · Skipped · On hold.
- **QR code** of the token ID (the receptionist will scan it in the desktop phase).
- Actions: **Cancel token** (only while `booked` or `arrived`, with confirmation), **Call clinic**, **Directions** (opens maps if clinic location exists).
- Session states: "Doctor has not started yet", "Queue paused", "Session ended".
- Updates in real time via Firestore streams.

### F-06 Queue notifications (P0), fixed decision
For each token with status `booked` or `arrived`, the account owner receives:

| Step | Trigger | Title | Body |
|---|---|---|---|
| 1 | 3 patients ahead | "3 patients ahead of you" | "Token #11 · Dr. Ayesha Malik. Please start heading to the clinic." |
| 2 | 2 patients ahead | "2 patients ahead of you" | "Token #11 · Dr. Ayesha Malik" |
| 3 | 1 patient ahead | "You're next" | "Token #11 · Please be at the reception." |
| 4 | Token status → `called` | "Your turn now" | "Token #11 · Please go to Dr. Ayesha Malik." |

Rules:
- N-1: "Ahead" = number of tokens for the same doctor/day with a **lower number** and status `booked`, `arrived` or `onHold`, plus none for the patient currently `called`. (Cancelled, completed, skipped, no-show do not count.)
- N-2: Each step is sent **at most once** per token (tracked in `token.notified`).
- N-3: If the queue jumps (e.g. from 4 ahead to 1 ahead), send **only** the step that now applies and mark skipped steps as done. Max 4 queue notifications per token.
- N-4: A token booked when fewer than 3 are already ahead gets only the step that applies at that moment (e.g. booked with 2 ahead → starts at step 2).
- N-5: Notifications go to the **account owner** (`bookedByUserId`), on all their registered devices.
- N-6: Tapping a notification opens that token's live screen.
- N-7: No queue notifications for walk-in tokens without an app account (future SMS).

### F-07 Family profiles (P0)
- Account owner can add, edit and remove patient profiles: **name, age, gender, relation** (Self, Mother, Father, Spouse, Son, Daughter, Brother, Sister, Other). Optional: patient's own phone.
- Age is entered in years and stored as `birthYear`.
- Duplicate warning: when adding a profile whose name closely matches an existing one on the same account, show "Looks like *Shazia Begum* already exists. Use that instead?"
- "Self" profile cannot be removed.
- Removing a profile is a soft delete (`status: deleted`); its history is kept for clinics.
- Merging profiles: **not in Phase 1** (see Decisions log).

### F-08 Visit history (P0)
- Per profile: list of past tokens: date, clinic, doctor, token number, status, wait time.
- "My Tokens" tab: **Active** and **Past** tokens across all profiles.

### F-09 Follow-ups (P1)
- Created by clinic staff (desktop phase); in Phase 1 they are created by the admin script for testing.
- Patient sees upcoming follow-ups on Home and in the profile.
- Reminders: **1 day before** and **on the due date morning** (max 2), at 9:00 AM PKT.
- Tapping a reminder opens booking **pre-filled** with clinic, doctor, patient and date; the user only confirms.
- Statuses: `pending`, `booked`, `done`, `missed`.

### F-10 Account and settings (P0)
- Edit own name. View phone number (read-only).
- Notification permission status + "Open settings" shortcut.
- Links: Privacy Policy, Terms, Contact support.
- **Delete account** (required by Google Play and the App Store): confirmation, then `deleteAccount` function removes the user, devices and app-created profiles' personal fields; clinic visit records are anonymised.
- Logout.

### F-11 Clinic QR deep link (P1)
- `https://asani.app/c/{clinicId}` opens the clinic page directly (after login if needed). Clinics will display this QR at reception.

### F-12 Crash reporting and basic analytics (P0)
- Crashlytics on. Analytics events: `login_success`, `token_booked`, `token_cancelled`, `notification_opened`. No personal data in events.

## 6. Non-functional requirements

| Area | Requirement |
|---|---|
| Performance | Cold start < 3 s on a mid-range Android (Redmi). Home first content < 1.5 s on 4G. |
| Real-time | Queue updates on screen ≤ 3 s after a change. |
| Offline | Show last known data with an "Offline, showing last update at 4:32 PM" banner. Booking requires internet. |
| Devices | Android 8.0+ (API 26+), iOS 15+. Phones only; no tablet layout in Phase 1. |
| Accessibility | Text scaling up to 1.3× without broken layouts; tap targets ≥ 48 dp; colour is never the only signal. |
| Privacy | Collect minimum data; no medical data; see docs/04. |
| Reliability | `bookToken` must never assign duplicate numbers. |
| Cost | Stay on Firebase Blaze with budget alerts; phone OTP is the main variable cost. |

## 7. Success metrics (pilot)

- % of a pilot clinic's patients who book via the app
- Average time from app open to token booked
- Notification delivery/open rate
- Reduction in token-related phone calls (reported by the clinic)
- Token cancellation and no-show rates

## 8. Dependencies

- A Firebase project on the **Blaze** plan (phone auth SMS + Cloud Functions).
- Apple Developer account + a Mac (or cloud Mac CI) for iOS builds, push (APNs) and phone auth.
- Google Play Console account.
- A hosted Privacy Policy and Terms page before store release.

## 9. Decisions log

| # | Date | Decision |
|---|---|---|
| D-01 | 2026-11-07 | Product name is **Asani** (was ClinicQ). |
| D-02 | 2026-11-07 | Patient app in Flutter for **Android and iOS**. |
| D-03 | 2026-11-07 | Flow is clinic first → doctor. **No direct doctor search.** |
| D-04 | 2026-11-07 | Queue notifications: **3, 2, 1 ahead + "Your turn now"** (4 total). |
| D-05 | 2026-11-07 | English only. |
| D-06 | 2026-11-07 | Clinic side will be a **Windows .exe**. Exact technology **not confirmed** (FlutterFire on Windows is development-only). Build order: app → desktop → super admin. |
| D-07 | 2026-11-07 | Clinic staff will log in with **phone/username + password**. |
| D-08 | 2026-11-07 | Phone number identifies the family account; each patient is a profile. Profile merge is postponed. |
| D-09 | 2026-11-07 | Printed slip is produced on patient **arrival** by the desktop app (Phase 2). |
| D-10 | 2026-11-07 | Any unclear behaviour must be **confirmed with Sarbuland before building**. |
| D-11 | 2026-11-10 | Patient app first built against an in-app **demo backend** (`lib/data/demo/`) that mirrors `bookToken`, `cancelToken`, `onTokenWrite` and queue-sim. Firebase replaces it behind the same repository interfaces. |
| D-12 | 2026-11-10 | App icon and logo: the lowercase **"a" monogram with a small plus** (logo concept 06), as in the UI design. |
| D-13 | 2026-11-10 | Token numbers are shown with the doctor's letter, e.g. **A-11** (`doctors.tokenPrefix`), as in the UI design. Numbering is still per doctor per day. |
| D-14 | 2026-11-10 | The live token screen shows the token code instead of a QR code (UI design). QR returns with the desktop app if reception needs scanning. |
| D-15 | 2026-11-10 | First login asks **name, age and gender** (asani_auth screens), so the Self profile is complete for booking. |
| D-16 | 2026-11-11 | **Intro pages** (S-00): three skippable pages on first launch only, before phone login. Stored on the device, not in Firestore. |
| D-17 | 2026-11-12 | Until the dev project is on **Blaze**, Cloud Functions run on the **local Functions emulator** against the dev database (`USE_FUNCTIONS_EMULATOR=true`). `bookToken` / `cancelToken` and `tools/queue-sim` also update `day.activeNumbers` in their transaction, because Firestore triggers (`onTokenWrite`) do not fire from the live database into the emulator. |
| D-18 | 2026-11-12 | **Queue alerts on/off is account-wide** (`users.queueAlertsEnabled`), so turning it off on one phone turns it off everywhere. Intro, primer and notification permission stay per phone. Account shows "On" only when the account switch is on **and** this phone allows notifications. |
| D-19 | 2026-11-12 | Queue notifications are sent by one shared function (`functions/src/queue/notify.ts`), called by `bookToken`, `cancelToken`, the `onTokenWrite`/`onQueueDayWrite` triggers (Blaze) and `tools/queue-sim` (until Blaze). Token labels in alerts use the doctor's letter: "Token A-11" (D-13). The primer's "Allow" opens the phone's own permission popup; if the phone says no, the app offers to open the phone's settings. |
| D-20 | 2026-11-12 | Booking a doctor for a patient with a **pending follow-up** with that doctor marks the follow-up `booked` (any date) and the token gets `source: followUp`. Until Blaze, the 9 AM follow-up reminders are run by hand with `tools/admin-scripts/run-followup-reminders.js` (same code as the scheduled function). |

## 10. Open questions (confirm before building the related part)

| # | Question | Affects |
|---|---|---|
| Q-01 | Clinic desktop technology (web dashboard in .exe shell vs native Flutter Windows vs API-only) | Phase 2 |
| Q-02 | Where the super admin panel lives | Phase 3 |
| Q-03 | Booking window: is 7 days right, or same-day only for the pilot? | F-04 |
| Q-04 | Should patients be allowed to book after the doctor's session has started? (Currently yes, until end time.) | F-04 |
| Q-05 | Max active tokens per account: is 5 right? | F-04 |
| Q-06 | Domain name for deep links and policy pages (`asani.app` is a placeholder) | F-11, store release |
| Q-07 | Dark mode in Phase 1? (Currently light only.) | DESIGN |
