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

1. Find a clinic → pick a doctor at that clinic, **or** pick a speciality → pick a doctor near them (D-31)
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
- ~~Direct doctor search across clinics~~: now **in scope** as search by speciality (D-31, F-13). Free-text doctor-name search is still not built.
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

### F-01 Email code login (P0) (D-52, was phone OTP)
- On the very first launch, three short intro pages explain the app before login; they can be skipped and are not shown again (D-29).
- **"Continue with email"**: the user enters an email and receives a **6-digit code** by email (Supabase email OTP; no password, no magic link). The code is valid **10 minutes**.
- Resend after 60 seconds, at most 3 times per login. Clear error messages for invalid email, wrong code, expired code, too many attempts and no internet.
- First login ("Tell us about you"): **name, age, gender and mobile number** (`+92 3XX XXXXXXX`), accept the **Terms and Privacy Policy** (checkbox, links). A `self` patient profile is created from this (D-15). "Use another email" signs out.
- The mobile number is **required but not verified** (`phoneVerified = false`). **One phone = one app account**: a number already used by another account shows "This number is already used by another Asani account" (`phone-taken`). The field accepts `3001234567`, `03001234567`, `923001234567` and `+92 300 1234567`.
- The number can be changed later in **Account → Mobile number** (same checks; the account's family profiles get the new number).
- **No auto-linking**: walk-in profiles a clinic created with the same number are **not** attached on login (the number is not verified). Reception links them in person (D-52, phase 6).
- Clinic or Super Admin logins cannot use the patient app (they are signed out).
- Session persists; the user stays logged in until logout.

**Acceptance:** valid email + correct code → profile setup (first time) or Home. Wrong code → error, can retry. Returning user is not asked for details again. A number already on another account is refused.

### F-02 Clinic search and discovery (P0)
- Search has two tabs: **Clinics** | **Doctors** (D-31). Both use the selected city. This feature (F-02) is the **Clinics** tab and stays exactly as it is; the Doctors tab is F-13.
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
- Speciality is shown with its patient label, e.g. "Heart (Cardiologist)" (fixed list, F-13).
- If the doctor is linked to the same doctor at another Asani clinic (F-14), the card shows "Also sits at: {clinic} · {days/timing}", tappable.
- Patients can also find doctors across clinics by **speciality** (F-13, D-31).

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
- Actions: **Cancel token** (only while `booked` or `arrived`, with confirmation), **Call clinic**, **Directions** (opens maps at the clinic location, which every clinic now has, D-31).
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
- N-8 (D-34): When the clinic **skips** a token, the account owner gets **one** push: "You missed your turn" · "Token #11 · Go to reception to be called next." Sent at most once per token (`skipNotifiedAt`). It is **outside** the 4 queue notifications.
- N-9 (D-35): Exception to N-2: if a token that already got "Your turn now" is skipped, it gets **one** more "Your turn now" when it is called again (recall, or Next after checking in again). At most once per token (`turnRepeatUsed`).
- N-10 (D-39): 0 ahead counts as step 3 ("You're next") when a patient is with the doctor (a `called` token on that doctor/day).
- N-11 (D-38): undoing the Next that called a token sends nothing and allows one more "Your turn now" (shares `turnRepeatUsed` with N-9).

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
- Crashlytics on. Analytics events: `login_success`, `token_booked`, `token_cancelled`, `notification_opened`, `doctor_search` (speciality key only). No personal data in events.

### F-15 Notifications list (P1) (D-45)
- Home header: bell with the unread count → **Notifications** (S-19): every push of the last 30 days, newest first (title, text, time).
- Saved by the backend with every push (`users/{uid}/notifications`), even if the push was blocked or alerts are off.
- Opening the list marks all read (`users.notificationsSeenAt`); a tap opens the token, or booking for follow-ups / clinic cancel.

### F-13 Search by doctor speciality (P0) (D-31)
Flow: **Search → Doctors tab → speciality chip → doctor card → booking for that clinic + doctor** → the same steps as F-04 (patient, date, confirm) with the same rules (BR-1..BR-7).

- The **Doctors** tab shows speciality **chips** only; there is **no free-text** doctor search.
- Only doctors who are `active`, at clinics with status `active`, `pilot` or `grace`, in the **selected city**, are shown. Each doctor has **one** speciality (D-33).
- Doctors **not available today** (no schedule, on leave, full, session ended) are shown **greyed at the end** with **Book another day** (D-33).
- Doctors at clinics **without a location** are shown after the others, without distance (D-33).
- **Fixed speciality list** (the clinic picks one from a picker, never free text):

| Key | Patient label | Icon (Material Symbols) |
|---|---|---|
| `generalPhysician` | General Physician | `stethoscope` |
| `child` | Child Specialist | `child_care` |
| `heart` | Heart (Cardiologist) | `cardiology` |
| `teeth` | Teeth (Dentist) | `dentistry` |
| `skin` | Skin (Dermatologist) | `dermatology` |
| `womensHealth` | Women's Health (Gynecologist) | `gynecology` |
| `eye` | Eye (Eye Specialist) | `ophthalmology` |
| `ent` | Ear Nose Throat (ENT) | `hearing` |
| `bones` | Bones & Joints (Orthopedic) | `orthopedics` |
| `diabetes` | Diabetes & Hormones (Endocrinologist) | `glucose` |
| `stomach` | Stomach & Liver (Gastro) | `gastroenterology` |
| `chest` | Chest & Lungs (Pulmonologist) | `pulmonology` |
| `kidney` | Kidney (Nephrologist) | `nephrology` |
| `brain` | Brain & Nerves (Neurologist) | `neurology` |
| `mentalHealth` | Mental Health (Psychiatrist) | `psychology` |
| `physio` | Physiotherapy | `physical_therapy` |
| `other` | Other | `medical_services` |

- **Order: nearest clinic first**, by the distance from the patient's location to `clinics.location`. Distance is calculated **in the app** for the selected city's doctors (no server geo-query).
- **Location permission** is asked the **first time** the Doctors tab is opened, after a short primer (DESIGN S-18). If it is denied or unavailable: doctors in the **same area** as the patient's last-used area come first, then the rest of the city (A–Z by area); no distance is shown.
- **Doctor card** shows: name, speciality label, clinic name + area + **distance** ("2.4 km"), **available today** or not, today's timing, **tokens booked / max** ("18 of 40"), **now serving** and **estimated wait** (same numbers as F-03).
- The patient can book for **today or a future date** (same date rules as F-04).
- One card per doctor **group** (F-14): the nearest clinic is the main card.
- Empty: "No {label} doctors on Asani in {city} yet." + [Search clinics].

**Acceptance:** with location on, picking "Heart (Cardiologist)" lists heart doctors in Lahore, nearest clinic first; tapping a card opens booking for that clinic and doctor.

### F-14 Same doctor at two clinics (P0) (D-32)
- If one doctor works at two (or more) Asani clinics **in the same city** and the records are **linked** by the Super Admin, the Doctors tab shows **one card**. The nearest clinic is the main one; below it: **"Also sits at: {clinic} · {days/timing}"**, one line per other **same-city** clinic (D-33), each **tappable to book there**.
- The same "Also sits at" line appears on the doctor card of the clinic page (F-03).
- Each clinic keeps its **own** doctor record, queue, timings, token letter and numbering; linking only groups the cards (`doctorGroupId`).
- Until linked, the doctor shows as **separate cards**. Linking never blocks booking.
- How records get linked (Super Admin, clinic web A-09): the system **suggests**, it never links on its own.

**Acceptance:** after the Super Admin links Dr. X at Clinic A and Clinic B, the Doctors tab shows one Dr. X card with "Also sits at: Clinic B"; after Unlink it shows two cards again.

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
| D-03 | 2026-11-07 | Flow is clinic first → doctor. **No direct doctor search.** *(Replaced by D-31.)* |
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
| D-21 | 2026-11-14 | **Old tokens are closed automatically.** A job runs every night at **3:00 AM Pakistan time** and closes only tokens whose date is **before today** (clinics may run past midnight): *Booked* → **No-show**; *Arrived*, *On hold* and *Called* → **Completed**. Every token it changes gets `autoClosed: true` so reports can tell them apart. Skipped, Completed, Cancelled and No-show are left as they are. |
| D-22 | 2026-11-14 | **Walk-in of an app user is linked to the app.** At the clinic web, typing the **full phone number** shows that number's family profiles from **any** clinic, but **only name, relation, age and gender**; visits and history from other clinics are never shown. A partial number or a name still searches only this clinic's patients. The full-number lookup goes through a **Cloud Function** with a **rate limit per clinic** (not direct Firestore reads; default 30 lookups per 10 minutes). When staff pick a profile, this `clinicId` is added to the patient's `clinicIds`, the token gets the account in `patientOwnerUid`, the app lists it in My Tokens and queue alerts go to that account. |
| D-23 | 2026-11-14 | **Clinic cancel notification** (closes Q-W08). When the clinic cancels a token (one token or a leave-day bulk cancel), the account gets a push: "Token A-5 cancelled by Al-Shifa Clinic: {reason}". Tapping it opens booking for the **same clinic and doctor** ("Book another day"). The app shows "Cancelled by clinic · {reason}" and the slip shows the **CANCELLED** stamp. No push for No-show. This push is **separate** from the 4 queue notifications (F-06), which stay at max 4 per token. |
| D-24 | 2026-11-14 | **Next follows the token number** (closes Q-W03). Next calls the **lowest number** among Booked and Arrived. If that token is not Arrived, the receptionist sees "A-7 has not arrived. **Skip** / **Call anyway**". A **Skipped** patient who checks in later is called **right after the patient now with the doctor**. The 3-2-1 alerts keep counting by token number, as now. |
| D-25 | 2026-11-14 | **Splash on every launch.** S-01 (logo, "asani", tagline on teal) stays about **1.5 s** on every app start, longer only while login state loads. The Android system splash (before Flutter) is the same teal with the white "a" mark, also on Android 12+. A notification tap that opens a token is not held back. |
| D-26 | 2026-11-14 | **Arrived only after the slip check.** On the clinic web every "Arrived" (board row, token panel, check-in by code) opens the check-in dialog with the patient's token slip; the token is marked Arrived and the form printed only when the receptionist confirms **"Slip matches · Arrived & Print"**. The row/panel button is called **Check in**. |
| D-27 | 2026-11-14 | **Closed now + session over.** A clinic shows **"Closed now"** (not "Open today") once every doctor working today is past their session end time; "Open now" is the search filter. A today token leaves **Active** (Home banner, My Tokens) **1 hour after its doctor's session end time**, or when the clinic ended the session; it then shows under Past as **"Session over"** until the 3 AM job (D-21) closes it. |
| D-28 | 2026-11-14 | **Intro pages removed** (replaces D-16). App start is Splash (S-01) → phone login, or Home when signed in. *(Replaced by D-29.)* |
| D-29 | 2026-11-17 | **Intro pages back** (replaces D-28), in the **"Bold type"** style: three skippable pages on the first launch only, before phone login ("Book your token." · "Wait at home." · "Go when called."). Stored on the device (`introSeen`). |
| D-30 | 2026-11-17 | **New brand colours.** Logo is forest green `#004741` + cream; the app uses palette **"Monochrome green"** (shades of `#004741`). **Dark mode is approved** (closes Q-07); it follows the phone's setting, no in-app switch. Built screen by screen after the light palette. |
| D-31 | 2026-11-19 | **Search by doctor speciality** (replaces D-03). Search has two tabs, **Clinics** \| **Doctors**, both for the selected city. Doctors tab: **speciality chips only** (no free text), from a **fixed list** with patient labels + icons (F-13); the clinic web picks speciality from a picker. Only doctors at Asani clinics. **Nearest clinic first** (patient's location, distance computed in the app); location permission is asked the first time the Doctors tab is used; if denied, same area first, then the rest of the city. Card: name, speciality, clinic + area + distance, available today, timing, booked/max, now serving, estimated wait; book today or a future date with the normal flow. Search by Clinic is unchanged. `clinics.location` becomes **required** (onboarding + clinic settings). |
| D-32 | 2026-11-19 | **Same doctor at two clinics = one card.** Linked doctor records share `doctors.doctorGroupId`; the nearest clinic is the main card, others show as "Also sits at: {clinic} · {timing}" (tappable). Each clinic keeps its own record, queue, timings and letter. Clinic web "Add doctor" gets an **optional PMDC number** (loose format check, e.g. `12345-P`; admin-only storage, D-33). A doctor is bookable **immediately**; linking never blocks. The system **never links automatically**: it creates **suggestions** for the Super Admin (strong = same PMDC at different clinics; weak = same normalised name + same speciality at different clinics). Super Admin: "Possible same doctor" list, side by side, **Link** / **Not the same** (remembered, never suggested again); linked records can be **Unlinked**. Link, Not the same and Unlink go into the activity log. |
| D-33 | 2026-11-19 | **Doctor search details** (closes Q-08..Q-14). **One** speciality per doctor. Doctors **not available today** are shown **greyed at the end** with "Book another day". Old free-text specialities are **mapped by a script**; unknown → `other`, flagged for the clinic. Clinics **without a location**: their doctors come **last, without distance**. "Also sits at" lists **same-city** clinics only. **PMDC number** lives in `doctors/{id}/private/admin`: the clinic writes it through `saveDoctor`, **only the Super Admin can read it**, patients never receive it. **Unlink = Not the same**: that pair is never suggested again. Approved dependencies: `geolocator` (permission text: "Asani uses your location to show clinics and doctors near you.") and Material Symbols icons. Roles: UI by Claude; backend (functions, rules, indexes, migration, native permission setup) by the integration side, task list in `docs/09-doctor-search-integration.md`. |
| D-34 | 2026-11-21 | **Push when skipped.** When the clinic skips a token, the patient's account gets one push: "You missed your turn · Token #11 · Go to reception to be called next." Sent **once per token** (claim `skipNotifiedAt`, then send, like D-23). Tap opens the token screen. **Outside** the 4 queue notifications (N-8). |
| D-35 | 2026-11-21 | **Skipped is a paused state in the app**, and one repeat "Your turn now". The token stays under **Active** with an amber card "Your turn passed · Go to reception. You'll be called right after the patient now with the doctor."; the slip stays, no "Book again". After the patient checks in again (`priorityAt` set), the app shows **"You're next · called right after the current patient"** instead of the number count. Exception to N-2: on recall, **one** extra "Your turn now" push, max once per token (`turnRepeatUsed`, N-9). Clinic web: re-checked-in Skipped patients are listed right after the Called patient with a **"Next up"** label. |
| D-36 | 2026-11-21 | **Logo loading indicator.** The plain circular spinner is replaced everywhere (both apps) by `AsaniLoader` in `asani_ui`, option **A "Draw"**: the logo "a" bowl, then the stem, write themselves like a pen, hold, then wipe away (2.4 s loop). Logo colours only (green on cream, cream on green); shown still when the phone asks for reduced motion. Full-screen waits show it over a **blurred** placeholder of the screen, with the message at the bottom (`LoadingScreen`). |
| D-37 | 2026-11-22 | **On hold in the app.** A token the reception puts **On hold** stays under **Active** with an amber note "You're on hold · The reception paused your turn. You'll be called when they're ready." No queue numbers and **no push**. |
| D-38 | 2026-11-22 | **Undo last Next.** If the clinic undoes the Next that called a patient, **no push** is sent; the app simply shows the queue again. When the patient is really called, they get **"Your turn now" once more** (the same one-time repeat as D-35, `turnRepeatUsed`). |
| D-39 | 2026-11-22 | **"You're next" at 0 ahead** (closes the open N-1 gap). A Booked/Arrived patient with **nobody waiting before them while someone is with the doctor** gets "You're next" (step 3 of the 4 queue pushes), once. With nobody at the doctor there is no early alert; "Your turn now" comes when called. |
| D-40 | 2026-11-22 | **Clinic edits walk-ins only** (closes Q-W07). The clinic web may fix the name, age and gender only of patients **without an app account**. Profiles that belong to an app family are read-only at the clinic ("Managed by the patient in the Asani app"); `clinicUpdatePatient` refuses them. Tokens keep the name as booked. |
| D-41 | 2026-11-22 | **Manager PIN** (closes Q-W11). The manager sets a **4-digit PIN** (Change password page). It protects **Billing, Export, Add doctor, Deactivate doctor and Change password**; never queue work, **leave or timings** (the reception must mark leave quickly). Stored **hashed** (salted scrypt) in `clinicPins/{clinicId}` and **checked by a Cloud Function**; a correct PIN unlocks for **15 minutes**; **5 wrong tries lock it for 15 minutes**. The **Super Admin can reset** it. No PIN set = nothing is locked. |
| D-42 | 2026-11-23 | **Upcoming bookings page** (clinic web, C-17). The clinic picks a day from tomorrow up to its longest booking window and sees each doctor's tokens for that day (token, patient, app or walk-in, when booked, cancelled marked), with booked / max. **View only**: check-in still happens on the day (BW-5). |
| D-43 | 2026-11-22 | **Palette "Deep forest"** replaces D-30's "Monochrome green" in **both apps** (shared `asani_ui` tokens): logo forest `#004741` + cream `#F0EDE4`; lime 400 for follow-ups; blue only for "Your turn"; logo never recoloured. The patient app UI is rebuilt from the Artifacts screens board **batch by batch** (palette, then P1…P9), each batch reviewed before the next. Maps are a **drawn map tile** (no map library, no API key); tap / Directions open Google Maps. |
| D-44 | 2026-11-22 | **Clinic web keeps the old colours for now** (narrows D-43). Only the patient app moves to Deep forest. The old "Monochrome green" palette lives in `asani_ui` as `WebColors`; the desktop theme and clinic web code use it (`AppColors` in the clinic web is an alias for `WebColors`). Shared widgets drawn on the web (loader, chips) may show small Deep forest differences. The web is redesigned later. |
| D-45 | 2026-11-23 | **Notifications list in the app** (S-19). A bell on Home with the **unread count** opens a list of **every push we send** (the 4 queue alerts, cancelled by clinic, missed your turn, follow-up reminders), saved by the backend **even when the phone blocks pushes or queue alerts are off**. Kept **30 days**. Opening the list **marks all read** (unread ones bold on that visit). A tap opens the same place as the push. |
| D-46 | 2026-11-23 | **flutter_svg in the patient app** (new dependency, approved by Sarbuland). Used for the speciality icons copied from the screens board (Doctors tab). The S-18 location primer becomes a **bottom sheet** (board P3), still shown once per phone. |
| D-47 | 2026-11-23 | **Doctor profile (S-07b, board P3b).** In the Doctors tab, Book token / Book another day / Also sits at open the doctor's profile at that clinic (`/doctor/{clinicId}/{doctorId}`) instead of going straight to booking: clinic header with call, address and drawn map; the doctor card with today's queue, or the reason (on leave / session ended / not today) and the **next available** day; the week's timings at this clinic; **Book for today** (or **Book for {day}**, opening booking on that date) and **Another day**. Search by clinic still books from the clinic page. |
| D-48 | 2026-11-23 | **No "Edit name" on Account.** Names are edited only in **Family → profile → Edit**. Editing the **Self** profile also updates the account name (as before). |
| D-49 | 2026-11-23 | **No Clinics / Doctors tabs** (amends D-31, follows the UI board). Home has two cards: **Search by clinic** opens the clinic search screen, **Search by doctor** opens the doctor search screen. They are two separate screens; neither shows tabs. |
| D-50 | 2026-11-23 | **App follows the UI board on these gaps** (Sarbuland's answers). Clinic search: field inside the green header, "Recent" search chips, "N clinics match '...'"; the area / Open now filter chips are **dropped**. Search by doctor: city chip + "Pick a speciality to see doctors near you". Pick a date: **month arrows**. Notification primer: a **bottom sheet** ("Open settings" when the phone already refused). Profile form: preview card **in the green header** (full-screen form; the add sheet keeps it at the top). Checked in again: "Checked in at reception · {time}" from `priorityAt`. Details tab: each alert's **sent time** from `token.notified` timestamps. Full-screen slip: **designed on the board first**, built after approval. |
| D-51 | 2026-11-24 | **Clinic web has no QR standee and no print templates screen.** Clinics make their own standees and printed forms. W-19 Settings drops the "Clinic QR standee" card; W-22 Print templates is removed from the board and the screen list. On the web screens **lime is used only for follow-ups** (D-43); everything else uses forest and cream. |
| D-52 | 2026-11-24 | **Backend moves from Firebase to Supabase** (Sarbuland and his senior; Blaze not needed). Firestore → Postgres + Row Level Security; Cloud Functions → Postgres functions (atomic booking/queue, token numbers stay atomic) + Edge Functions; listeners → Realtime; scheduled jobs → `pg_cron`; roles in `app_metadata`, set only on the server. **Push stays on FCM** (free Spark plan, HTTP v1 from an Edge Function). **Patient login = "Continue with email" + 6-digit email code** (no password, no magic link, 10 min expiry), replacing phone SMS OTP (F-01). **Phone is required in profile setup but not verified** (`phoneVerified = false`, `+92 3XX XXXXXXX`); **one phone = one app account** (`phone-taken`). **No auto-linking** of walk-in profiles by phone: reception links them in person (search by phone → confirm → "Link to app account", logged). Clinic web: email + password, invite email, forgot password; manager PIN unchanged. Dev data is reseeded fresh; the Firebase project is kept for FCM. Plan and risks (free project pauses after 1 week without use): docs/10-supabase-migration.md. |

## 10. Open questions (confirm before building the related part)

| # | Question | Affects |
|---|---|---|
| Q-01 | Clinic desktop technology (web dashboard in .exe shell vs native Flutter Windows vs API-only) | Phase 2 |
| Q-02 | Where the super admin panel lives | Phase 3 |
| Q-03 | Booking window: is 7 days right, or same-day only for the pilot? | F-04 |
| Q-04 | Should patients be allowed to book after the doctor's session has started? (Currently yes, until end time.) | F-04 |
| Q-05 | Max active tokens per account: is 5 right? | F-04 |
| Q-06 | Domain name for deep links and policy pages (`asani.app` is a placeholder) | F-11, store release |
| ~~Q-07~~ | ~~Dark mode in Phase 1?~~ **Closed**: yes, follows the phone setting (D-30). | DESIGN |
| ~~Q-08~~ | ~~One or two specialities?~~ **Closed**: **one** speciality per doctor (D-33). | F-13, C-11 |
| ~~Q-09~~ | ~~Doctors not available today?~~ **Closed**: shown **greyed, at the end**, with "Book another day" (D-33). | F-13 |
| ~~Q-10~~ | ~~Old free-text specialities?~~ **Closed**: mapped by a script; unknown → `other`, flagged for the clinic (D-33). | Migration |
| ~~Q-11~~ | ~~Clinics without a location?~~ **Closed**: their doctors are shown **last, without distance**, until the location is added (D-33). | F-13 |
| ~~Q-12~~ | ~~"Also sits at" city?~~ **Closed**: **same city only** (D-33). | F-14 |
| ~~Q-13~~ | ~~PMDC visible to patients?~~ **Closed**: stored in an **admin-only** place, `doctors/{id}/private/admin`; the clinic can write it (through `saveDoctor`), only the Super Admin can read it; patients never receive it (D-33). | F-14, DATABASE, rules |
| ~~Q-14~~ | ~~Re-suggest after Unlink?~~ **Closed**: Unlink counts as "Not the same": that pair is **never suggested again** (D-33). | F-14, A-09 |
