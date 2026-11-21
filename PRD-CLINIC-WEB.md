# PRD — Asani Clinic Web (Clinic Dashboard + Super Admin)

| | |
|---|---|
| **Product** | Asani: smart clinic token & live queue |
| **Document** | Product Requirements: Clinic Web App (Phase 2) incl. Super Admin (Phase 3) |
| **Version** | 0.4 (draft): clinic adds its own doctors; no doctor/receptionist logins |
| **Date** | 2026-11-12 |
| **Owner** | Sarbuland |
| **Related** | PRD.md (patient app), ARCHITECTURE.md, DATABASE.md, PROJECT_DOCUMENTATION.md |

---

## 1. Summary

The **Asani Clinic Web** app is a Flutter Web application opened in Chrome at the clinic's reception PC (or any computer). It lets the clinic (the receptionist, using the clinic's single login) run the daily token queue, check patients in, add walk-ins, print the clinic form, manage follow-ups, and keep doctor timings and leave up to date.

The **same web app** also contains the **Super Admin panel**. When Sarbuland logs in with a super admin account, he sees admin screens to register and manage all clinics and their doctors, see activity, subscriptions, payments and defaulters. **There is no separate admin app.**

It uses the **same Firebase project** as the patient app (same Auth, Firestore, Cloud Functions), so a token booked in the patient app appears on the clinic screen instantly, and pressing **Next** on the clinic screen updates the patient's phone instantly.

---

## 2. Decisions this PRD is based on

| # | Decision |
|---|---|
| D-06 (updated) | Clinic side is **Flutter Web**, not a Windows .exe. Runs in Chrome; can be "installed" as a desktop app from Chrome. |
| D-07 (updated) | The clinic logs in with the **clinic's email + password**. The manager/senior doctor **sets the password** through an emailed link. (Was: phone/username + password.) |
| D-18 | **One login per clinic.** Only the manager/senior doctor's clinic login (clinic email) exists; the **receptionist uses that same login** at reception. **No separate receptionist or doctor accounts.** Super Admin registers the clinic and its login. |
| D-19 | **The clinic adds and manages its own doctors.** The Super Admin can see every clinic's doctors and is shown when a **new doctor is added** (dashboard + activity log). |
| D-31..D-33 | Confirmed 2026-11-19, full text in PRD.md §9 (D-33: one speciality, PMDC admin-only, Unlink = Not the same, same city only): patients search doctors by **speciality** (fixed list, nearest clinic first, `clinics.location` required) (D-31); the same doctor at two clinics is shown as one card once the **Super Admin links** the records, from system suggestions (D-32). |
| D-21..D-24 | Confirmed 2026-11-14, full text in PRD.md §9: old tokens auto-closed at 3:00 AM (D-21), full-phone lookup to link walk-ins to app accounts (D-22), push on clinic cancel (D-23), Next in strict token order (D-24). |
| D-15 | **Super admin panel lives inside the clinic web app**; access is decided by role after login. |
| D-16 | **Check-in:** receptionist types the **token code** (e.g. A-11); the **same token slip the patient generated** appears on screen so the receptionist can match it with the slip the patient shows. |
| D-12 | Token code = doctor letter + number (A-11). |
| D-13 | Patient's digital slip is a reference; the system record is the truth. |
| D-09 | Clinic form is printed on **arrival**. |
| D-04 | Patient notifications (3, 2, 1 ahead, Your turn) are sent by the backend, not by the clinic app. |
| D-10 | Anything unclear is confirmed with Sarbuland before building. |
| D-17 | **Monorepo in the same `Asani_app` repo** (see §2.1). Patient app moves once into `apps/patient_app`; clinic web is `apps/clinic_web`; shared code in `packages/asani_core`. |

### 2.1 Repository structure (D-17, confirmed 2026-11-12)

```
Asani_app/
├── pubspec.yaml              ← Dart pub workspace root
├── apps/
│   ├── patient_app/          ← Flutter, Android + iOS (moved here from repo root)
│   └── clinic_web/           ← Flutter Web: clinic dashboard + super admin
├── packages/
│   ├── asani_core/           ← pure Dart: models, enums, PKT dates, phone utils, token code, formatting, logger
│   └── asani_ui/             ← Flutter: theme (colors, fonts, spacing, ThemeData) + shared widgets
├── functions/                ← Cloud Functions (shared backend)
├── firebase.json
├── firestore.rules
└── firestore.indexes.json
```

Rules:
1. **One-time move first:** before creating `clinic_web`, move the current patient app (lib, android, ios, pubspec.yaml…) from the repo root into `apps/patient_app`. Commit everything before the move so it can be undone.
2. **Never nest** `clinic_web` inside the patient app folder.
3. **Dart pub workspace:** root `pubspec.yaml` lists the workspace members; each member uses `resolution: workspace`. One `flutter pub get` at the root resolves all; both apps use `asani_core` locally.
4. **Shared packages (updated 2026-11-14, Sarbuland):** `asani_core` is **pure Dart** (no Flutter): models (Clinic, Doctor, Token, Patient, QueueDay…), enums, shared logic (token code, PKT dates, phone utils), formatting (`Fmt`) and `AppLogger`. `asani_ui` is a **Flutter** package with the theme tokens, both ThemeData (`buildAppTheme` for the phone, `buildDesktopAppTheme` for the web) and the common widgets, so both apps look the same. **Auth and the Cloud Functions callables stay inside each app** (patient app = phone OTP, clinic web = email + password); `ErrorState` stays per app because each app has its own error messages.
5. **CI path filters:** each app builds and deploys on its own:
   - changes in `apps/patient_app/**` → patient app build only
   - changes in `apps/clinic_web/**` → clinic web build + deploy to Firebase Hosting only
   - changes in `packages/asani_core/**` or `packages/asani_ui/**` → both apps build and test
   - changes in `functions/**` or `firestore.rules` → backend tests (+ deploy when approved)
6. Both apps use the **same Firebase project** per environment (dev = `asani-b2b17`, prod = `asani-prod`).

---

## 3. Goals and non-goals

### Goals
- G1: A receptionist can check in an app-booked patient in **under 10 seconds** (type code → match slip → Arrived & Print).
- G2: A walk-in token can be created in **under 15 seconds**.
- G3: The queue on screen and on patients' phones updates within **2–3 seconds** of any action.
- G4: Asani **reduces** reception work compared to a register; it never adds double entry.
- G5: Sarbuland can see every clinic's status, doctor changes and payments in one place.

### Non-goals (this phase)
- Patient-facing features (they are in the patient app)
- Medical records, prescriptions, diagnosis (Stage 3)
- Online payment gateway (manual payment recording only)
- SMS/WhatsApp tokens (later)
- Mobile layout for the clinic web (desktop/laptop screens only)
- Native Windows .exe

---

## 4. Users, roles and permissions (D-18)

### 4.1 One login per clinic

Each clinic has **exactly one clinic login**: the **clinic's email** + password. It belongs to the clinic's **manager or senior doctor**, who sets the password. The **receptionist uses the same login** on the reception PC to run the queue. There are **no separate receptionist or doctor accounts**.

Doctors are **records** in the system (name, letter A/B/C, schedule), not users who log in.

| Role | Who logs in | Main job |
|---|---|---|
| **Clinic** (`clinic` role) | Clinic manager / senior doctor; used day-to-day by the receptionist at reception | Runs the queue, check-in, walk-ins, printing, follow-ups, daily summary, **adds and manages its doctors**, clinic settings |
| **Super Admin** | Sarbuland | Registers clinics and their login; **sees** all doctors and new-doctor alerts; subscriptions, payments, defaulters, activity logs |

### 4.2 Permission matrix

| Action | Clinic login | Super Admin |
|---|:-:|:-:|
| View today's queue (all doctors of the clinic) | ✅ | ✅ (any clinic, read-only) |
| Check in (Arrived & Print) | ✅ | ❌ |
| Next / Skip / Hold / No-show / Cancel token | ✅ | ❌ |
| Start / Pause / End session | ✅ | ❌ |
| Walk-in token | ✅ | ❌ |
| Search patient by phone, see clinic visit history | ✅ | ❌ |
| Set follow-up, follow-up lists | ✅ | ❌ |
| Daily summary | ✅ | ✅ |
| Doctor timings, leave, max tokens | ✅ | 👁 view |
| Add / edit / deactivate doctors | ✅ | 👁 view (+ new-doctor alert) |
| Clinic settings (print format, phone, address) | ✅ | ✅ |
| Export data (CSV/Excel) | ✅ | ✅ |
| See own clinic's invoices | ✅ *(⚠️ Q-W11)* | ✅ |
| Register clinic, create/disable clinic login | ❌ | ✅ |
| Super admin screens | ❌ | ✅ |

Roles are stored as Firebase Auth **custom claims** (`role: "clinic"` + `clinicId`, or `role: "superAdmin"`), set only by Cloud Functions. Never read from Firestore documents.

> Because the whole clinic shares one login, the activity log records actions as **"<Clinic name> (clinic login)"**; it cannot tell the manager and the receptionist apart.

---

## 5. Login and accounts (D-07, D-18)

### 5.1 How accounts are created
| Account | Created by | When |
|---|---|---|
| Clinic login (clinic's email) | Super Admin, in the "New clinic" wizard (A-04) | Clinic onboarding |
| Super Admin | One-time admin script | Once |

Doctors are added by the **clinic itself** after login (C-11). Doctors never get logins.

### 5.2 Set-password flow
1. Super Admin enters the clinic's **email** while registering the clinic.
2. The system creates the clinic login and emails **"Set your Asani password"** with a secure link to that address.
3. The manager / senior doctor opens the link, sets a password (min 8 characters), and logs in. They can then log in on the reception PC for the receptionist.
4. If the link expires, the Super Admin presses **"Resend invite"** on the clinic's page.
5. If the manager wants to change the password (e.g. a receptionist leaves), they use **Change password** in clinic settings or **Forgot password** on the login page. Changing the password signs the clinic out on all other computers.

### 5.3 Login page (W-01)
- Fields: **Email**, **Password**, **Log in** button, **"Forgot password?"** link.
- Forgot password → reset link sent to the clinic's email ("If this email is registered, you'll get a link").
- After login the app reads the role and opens:
  - Super Admin → **Admin Dashboard**
  - Clinic login → **Queue Board**
  - Any other account (e.g. a patient account) → "This account doesn't have clinic access." + Log out
- Wrong password → "Email or password is incorrect."
- After repeated failed attempts Firebase rate-limits; show "Too many attempts. Try again later or reset your password."

### 5.4 Session rules
- Session stays logged in on that browser until **Log out**, so the receptionist doesn't need the password every day.
- Top bar shows the **clinic name** and a **Log out** button.
- The clinic can be logged in on more than one computer at the same time (e.g. reception PC + manager's laptop).
- Super Admin can **disable** a clinic login (signs it out everywhere within minutes).
- Suspended clinic: the clinic can still log in but sees read-only mode (BW-8).

---

## 6. Clinic features

Priority: **P0** = must have for pilot · **P1** = should have · **P2** = later.

### C-01 Queue Board (P0): the main screen
- Tabs or columns per **doctor** (A, B, C…). Each shows:
  - Doctor name + letter, session status (*Not started / Running / Paused / Ended*), timing
  - **Now serving: A-7** (large)
  - **Waiting list**: token code, patient name, age/sex, source (App / Walk-in), status (Booked / Arrived / On hold / Skipped), booked time
  - Counters: waiting, arrived, completed today, average wait
- Big **Next** button per doctor.
- Updates live (Firestore streams). New app bookings appear automatically with a small "New" highlight.
- Filter: *All / Arrived only / App bookings / Walk-ins*.

### C-02 Session controls (P0)
- **Start session** → patients see "Running".
- **Pause** (e.g. doctor on a break) → patients see "Queue is paused".
- **End session** → remaining *Booked* tokens become **No-show**; confirmation required ("5 tokens will be marked No-show").

### C-03 Next (P0)
On **Next** for a doctor:
1. The current *Called* token becomes **Completed** (visit saved with wait time).
2. The next token in order becomes **Called** and **Now serving** updates.
3. The backend sends notifications (3, 2, 1 ahead and "Your turn now") automatically.

Order of "next" (D-24, closes Q-W03): the **lowest token number** among *Booked* and *Arrived*. If that token is not Arrived, the receptionist is asked: "A-7 has not arrived. **Skip** / **Call anyway**". A *Skipped* patient who checks in later is called **right after the patient now with the doctor**. The 3-2-1 alerts count by token number.

Undo: **"Undo last Next"** available for 30 seconds (in case of a wrong click).

### C-04 Token actions (P0)
From a token row or its detail panel:
| Action | Result |
|---|---|
| **Arrived & Print** | Status Arrived + prints the clinic form (C-07) |
| **Call now** | Call this token out of order (emergency) |
| **Skip** | Patient not present when called; can be **Recall**ed later |
| **Hold** | Temporarily aside (e.g. sent for tests); can be called later |
| **Cancel** | Cancel token (reason: patient request / duplicate / other) |
| **Mark No-show** | Patient never came |
| **Reprint** | Print the form again |

Every action is logged (who, when) in the token's history.

### C-05 Check-in by token code (P0) (D-16)
1. Receptionist focuses the **"Enter token code"** box (top of Queue Board; keyboard shortcut `/`).
2. Types the code the patient says or shows, e.g. `A11` or `A-11` (dash optional, case-insensitive). Single-doctor clinics: just `11`.
3. The app shows the **same token slip** the patient generated (same layout: clinic, A-11, doctor, patient name, age/sex, date, timing, booked time) so the receptionist can **match it** with the slip on the patient's phone/WhatsApp.
4. Below the slip: status and warnings:
   - ✅ *Booked: today, valid*
   - ⚠️ *This token is for another date (Mon 10 Nov)*
   - ❌ *This token was cancelled* / *already completed*
   - ❌ *No token A-11 today*
5. Buttons: **Arrived & Print** (primary), **Cancel**, **Close**.

The search only looks at **today's tokens of this clinic**, so a code is always unique.

### C-06 Walk-in token (P0)
1. Button **"+ Walk-in"** (shortcut `W`).
2. Enter **phone number** → system shows profiles linked to that phone **at this clinic** (name, relation, age/sex, visits here).
3. Pick a profile **or** "+ New patient" (name, age, gender; relation optional).
4. Pick **doctor** (default: the one selected on the board).
5. **Create & Print** → token created with the next number (same sequence as app bookings, e.g. A-12), form printed, status Arrived.
- Duplicate warning if a similar name already exists on that phone.
- If the person later installs the patient app with this phone number, these visits appear in their account automatically.

### C-07 Clinic form printing (P0)
- Printed on **Arrived & Print**, **Create & Print** (walk-in) and **Reprint**.
- Formats (clinic setting): **Thermal 80 mm**, **A5 form**, **None**.
- Content: clinic name/address, **token code**, date, doctor, patient name, age/sex, phone, **visit number at this clinic** ("4th visit"), last visit date, empty **Rx** area, QR of the token.
- Uses the browser print. To avoid the print dialog every time, the clinic PC uses a Chrome shortcut with kiosk printing (setup guide in the app's Help page).

### C-08 Patient search & history (P0)
- Search by **phone number** (or name, within this clinic's patients).
- Result: profiles on that phone that have visited **this clinic**: name, relation, age/sex, visit count, last visit.
- Profile view: visit history **at this clinic only** (date, doctor, token, wait time, status), upcoming follow-ups.
- Actions: **Book token** (walk-in for today), **Edit details** (name/age/gender typo fixes, logged).
- Privacy: a clinic never sees the patient's visits at other clinics.

### C-09 Follow-ups (P1)
- When completing a visit (from the Called token or history): **Set follow-up** → 3 days / 1 week / 2 weeks / 1 month / pick date, optional short note (non-medical, e.g. "Review").
- **Follow-ups screen**: *Today*, *Upcoming*, *Missed* tabs; patient name, phone (tap to copy), doctor, due date, status (Pending / Booked / Done / Missed).
- Missed list helps the clinic call patients back.
- Patient app reminders are sent automatically by the backend.

### C-10 Daily summary (P1)
- Per day and per doctor: tokens issued, app vs walk-in, completed, cancelled, no-show, **average wait time**, busiest hour.
- Date picker (last 30 days).

### C-17 Upcoming bookings (P1, clinic login) (D-42)
- Pick a day: tomorrow up to the longest booking window of the clinic's doctors (default 7 days).
- Per doctor: "N of max booked", then each token (letter-number, patient name, App / Walk-in, booked at, CANCELLED + reason).
- View only. Check-in by code stays limited to today (BW-5); tokens move to the Queue Board on their day.

### C-11 Doctors management (P0, clinic login) (D-19)
- List of doctors with letter (A, B, C…), speciality, active/inactive.
- **Speciality** is a **picker** (**one** per doctor, D-33) with the fixed list from PRD F-13 (patient label shown, e.g. "Heart (Cardiologist)"); no free text (D-31).
- **PMDC number** (optional, D-32): loose format check only (digits, optional `-` + letter, e.g. `12345-P`); "Not a valid PMDC number" otherwise. It is stored **admin-only** (D-33): after saving, the clinic sees "PMDC number on file · Change", never the number itself. Helper text: "Helps patients find this doctor at all their clinics."
- A doctor the migration set to **Other** (`specialityFlagged`) shows an amber "Please pick a speciality" chip in the list and the form until the clinic saves one (D-33).
- The doctor is **active and bookable immediately** after saving; a possible match with another clinic never blocks or delays anything and is **not shown to the clinic** (it goes to the Super Admin, A-09).
- Add / edit doctor: name, qualification, speciality, **weekly schedule** (per day start–end or off), **average consultation minutes**, **max tokens per day**, **booking window days**.
- **Leave dates**: add/remove (patients see "On leave"; existing tokens on that date get a warning and can be cancelled in bulk with a reason).
- Letter is assigned automatically and never reused within the clinic.
- Deactivate doctor (no new bookings; history kept).
- The **clinic adds, edits and deactivates its own doctors**. Every add/change is logged, and a **new doctor** shows up for the Super Admin (A-01 alert, A-03, A-07).
- Doctors never log in; they are records only.
- First-time setup: right after the first login, if the clinic has no doctors, the Queue Board shows **"Add your first doctor"**.

### C-12 Change password (P0, clinic login)
- There is **no staff management**: the clinic has one login (D-18).
- **Change password**: current password + new password. Signs the clinic out on all other computers (useful when a receptionist leaves).
- Shows the clinic email (read-only; changed only by Super Admin).

### C-13 Clinic settings (P0, clinic login)
- Clinic name (read-only; changed by Super Admin), address, area, phone, map location.
- **Map location is required** (D-31): pick on a map or paste a Google Maps link / "lat, lng"; Save is disabled without it. Used for Directions and for "nearest first" in the patient app's Doctors tab.
- Print format (Thermal 80 / A5 / None).
- **Clinic QR standee**: download/print a poster with the clinic QR ("Scan to book your token with Asani").

### C-14 Data export (P1, clinic login)
- Export a date range of visits to **CSV / Excel**: date, token, doctor, patient name, age/sex, phone, status, wait time.
- **Copy patient details** button on any token (for clinics that also use their own software).

### C-15 Billing banner & invoices (P1, clinic login)
- If the clinic is in **Grace**: yellow banner "Payment pending, please pay by <date> to avoid interruption."
- **Billing page**: current plan, paid until, invoices list (month, amount, status), payment instructions (bank / JazzCash / Easypaisa details), "Send payment proof" (upload screenshot) (P2).

### C-16 Help (P2)
- Short guides: kiosk printing setup, install as desktop app, keyboard shortcuts, contact Asani support.

---

## 7. Super Admin features (inside the same web app)

Visible only with the `superAdmin` role. Left navigation: **Dashboard · Clinics · Doctors · Payments · Activity · Settings** (Doctors = A-09, D-32).

### A-01 Admin Dashboard (P0)
- Clinics by status: **Pilot / Active / Grace / Suspended / Cancelled**
- This month: expected revenue, collected, pending
- **Defaulters** count (red card, click → list)
- Tokens booked this month (all clinics), app vs walk-in
- **New doctors** card: doctors added by clinics in the last 7 days (clinic, doctor, speciality, when), with an unseen badge
- Latest activity feed (e.g. "Al-Shifa added Dr. Ayesha Malik · 2h ago")

### A-02 Clinics list (P0)
- Table: name, city/area, plan, status, doctors, tokens this month, **paid until**, clinic login status (Invited / Active / Disabled), last activity.
- Filters: status, city, plan. Search by name/phone/email.

### A-03 Clinic detail (P0)
Tabs:
- **Info**: details, owner name/phone, **clinic email (login)** with status + **Resend invite** / **Disable login**, pilot end date, plan, monthly fee
- **Doctors** (view): list with letter, speciality, timings, active status, **when added/changed** (by the clinic). New ones marked **New**. PMDC number, and a **Linked** chip with the other clinic(s) for linked doctors, with **Unlink** (D-32).
- **Payments**: invoices and payment history
- **Activity**: this clinic's activity log
- **Usage**: tokens per day, app vs walk-in, average wait
- **Actions**: Suspend, Reactivate, Change plan/fee, Extend pilot, Resend clinic admin invite, View queue (read-only)

### A-04 New clinic wizard (P0)
1. Clinic: name, area, city, address, phone, **location (required, D-31)**, print format
2. Clinic login: manager/senior doctor name + phone, **clinic email** → "Set your Asani password" email sent
3. Plan: pilot length (default 30 days), plan after pilot, monthly fee, billing day
4. Review → **Create**

Doctors are **not** added here; the clinic adds its own doctors after its first login (D-19).

### A-05 Payments & invoices (P0)
- Invoices are created automatically each billing day (not during pilot).
- List with filters: Unpaid / Overdue / Paid / Waived, month, clinic.
- **Record payment**: amount, method (Bank / JazzCash / Easypaisa / Cash), reference/transaction ID, date, proof screenshot.
- Recording a payment → invoice Paid, clinic **paid until** +1 month, clinic **Active**.
- **Waive** an invoice (with reason).

### A-06 Defaulters (P0)
Automatic timeline (daily job):

| When | Effect |
|---|---|
| Billing day | Invoice created (Unpaid) |
| Due date passed | Invoice **Overdue**, clinic **Grace**, banner on clinic web |
| +7 days | Reminder email to clinic |
| +15 days | Clinic **Suspended** |
| Payment recorded | Clinic **Active** immediately |

Defaulters screen: clinic, amount due, days overdue, contact phone (tap to copy), **Record payment**, **Suspend now**, **Give extension** (new due date).
**⚠️ Confirm (Q-W05):** are 7 and 15 days right?

### A-07 Activity log (P0)
- Recorded automatically by the backend (cannot be edited or skipped by clinics).
- Events: clinic created/updated/suspended/reactivated, doctor added/updated/deactivated, **doctors linked / marked not the same / unlinked (D-32)**, leave added, clinic login invited/disabled/password changed, settings changed, payment recorded, invoice waived, export done.
- Each row: time, clinic, who (**Super Admin** or **<Clinic> (clinic login)**), action, target.
- Filters: clinic, action type, date range, person.

### A-09 Possible same doctor (P0) (D-32)
- Left navigation gets **Doctors** with a count badge of open suggestions; the Dashboard (A-01) shows a "Possible same doctor: N" card.
- The system **never links on its own**. Suggestions are made when a clinic adds a doctor or changes its name, speciality or PMDC number:
  - Only doctors in the **same city** (D-33).
  - **Strong**: same PMDC number at different clinics.
  - **Weak**: same normalised name (no "Dr.", case, punctuation) + same speciality at different clinics.
- List, strong first, newest first. Each row shows the **two records side by side**: name, speciality, clinic (+ area, city), PMDC number, weekly timings, added on; plus a Strong / Weak chip and the reason ("Same PMDC 12345-P" / "Same name and speciality").
- Buttons: **Link** and **Not the same** (both with a short confirm).
  - **Link**: the two records share one group; the patient app shows one card with "Also sits at". If one record is already linked, the other joins that group.
  - **Not the same**: remembered; that pair is **never suggested again**.
  - **Unlink** counts as Not the same: that pair is never suggested again (D-33).
- **Unlink**: from A-03 Doctors or a "Linked doctors" tab on this screen; removes one record from its group.
- Each Link / Not the same / Unlink writes an activity log entry (A-07).
- Each clinic still keeps its own record, queue, timings and letter; linking changes nothing at the clinic.

### A-08 Settings (P1)
- Plans and default prices (Pilot, Basic, Premium), default pilot days, billing day default, payment instructions text shown to clinics, grace and suspension days.

---

## 8. Business rules

| # | Rule |
|---|---|
| BW-1 | All queue changes (Next, Arrived, Skip, Hold, Cancel, No-show, sessions, walk-ins) go through backend functions so token numbers and statuses stay correct and are logged. |
| BW-2 | Walk-in and app tokens share **one sequence** per doctor per day. |
| BW-3 | Only one token per doctor can be **Called** at a time. |
| BW-4 | A **Completed** token cannot be changed (except Super Admin correction, logged). |
| BW-5 | Check-in search is limited to **today + this clinic**. |
| BW-6 | A clinic sees patients only through visits/bookings at **its own clinic**. |
| BW-7 | Doctor letters are unique per clinic and never reused. |
| BW-8 | A suspended clinic is **read-only**: no new tokens (app or walk-in), no Next; the clinic can still view and export. Patients see "Online booking isn't available right now." |
| BW-9 | Billing data is only visible to the clinic login (own clinic) and Super Admin. |
| BW-10 | Every clinic/admin action that changes data creates an activity log entry (actor = Super Admin or the clinic login). |
| BW-11 | Doctor records are linked **only** by the Super Admin (D-32). Linking or a pending suggestion never blocks adding, editing or booking a doctor. Clinics never see suggestions or other clinics' doctors. |
| BW-12 | A clinic cannot be created or its settings saved without a **map location** (D-31). |

---

## 9. Screens list

### Shared
| ID | Screen |
|---|---|
| W-01 | Login (email, password, forgot password) |
| W-02 | No access / disabled account |
| W-03 | Top bar: clinic name, user name + role, Log out |

### Clinic
| ID | Screen |
|---|---|
| W-10 | Queue Board (doctor tabs/columns, waiting list, Next, session controls) |
| W-11 | Token detail panel (slip view, history, actions) |
| W-12 | Check-in dialog (token code → patient's slip → Arrived & Print) |
| W-13 | Walk-in dialog (phone → profiles → doctor → Create & Print) |
| W-14 | Patients (search) + Patient profile (clinic history, follow-ups) |
| W-15 | Follow-ups (Today / Upcoming / Missed) |
| W-16 | Daily summary |
| W-17 | Doctors list + Add/Edit doctor (schedule, leave, deactivate) |
| W-18 | Change password (clinic login) |
| W-19 | Clinic settings + QR standee |
| W-20 | Billing (plan, invoices, payment instructions) |
| W-21 | Help |
| W-22 | Print templates (Thermal 80, A5) |

### Super Admin
| ID | Screen |
|---|---|
| A-10 | Admin Dashboard |
| A-11 | Clinics list |
| A-12 | Clinic detail (tabs) |
| A-13 | New clinic wizard |
| A-14 | Payments & invoices + Record payment dialog |
| A-15 | Defaulters |
| A-16 | Activity log |
| A-17 | Admin settings |
| A-18 | Possible same doctor (suggestions + linked doctors) (A-09) |

Design: same brand as the patient app (teal `#0F766E`, navy `#1E3A8A`, mint `#CCFBF1`, Inter), adapted for desktop: left sidebar navigation, wide tables, large "Now serving" and "Next" for quick use at a busy desk. Minimum screen width **1280 px**.

---

## 10. Non-functional requirements

| Area | Requirement |
|---|---|
| Browser | Latest **Chrome** (primary) and Edge on Windows. Desktop/laptop only. |
| Real-time | Queue changes visible on the clinic screen and patient phones within 2–3 s. |
| Speed | Queue Board loads in < 3 s on a normal clinic internet connection. Next responds in < 1 s (optimistic UI). |
| Keyboard | Shortcuts: `/` token code, `W` walk-in, `N` next (selected doctor), `Esc` close dialogs. |
| Reliability | If the internet drops: red banner "Offline: actions disabled", queue shows last data; actions resume when back online. |
| Printing | Thermal 80 mm and A5 templates print correctly from Chrome; kiosk printing guide provided. |
| Security | Email/password auth, custom-claim roles, Firestore rules for clinic isolation, all queue actions validated by backend, activity logs write-only by backend. |
| Privacy | A clinic sees only its own patients/visits; no medical data stored. |
| Install | Can be installed from Chrome as a desktop app (own window and icon). |
| Hosting | Firebase Hosting (works on the free plan). Separate URLs for dev and prod. |
| Cost | Email/password login is free. Cloud Functions and scheduled jobs need the Blaze plan when going live. |

---

## 11. Data additions (summary; details go into DATABASE.md when building)

| Collection / field | Purpose |
|---|---|
| `clinicAccounts/{uid}` | clinic login: email, clinicId, status (invited/active/disabled), invitedAt, lastLoginAt |
| `doctors.tokenPrefix` | Letter A, B, C… (already planned) |
| `tokens.history[]` or `tokens/{id}/events` | Who did what and when (arrived, called, skipped…) |
| `patients.clinicIds[]` | Clinics this patient has visited/booked: lets a clinic search only its own patients |
| `followUps` | Already planned; created from the clinic web |
| `clinics/{id}/private/billing` | plan, monthlyFee, billingDay, paidUntil, pilotEndsAt, owner contact |
| `invoices/{id}` | month, amount, dueDate, status, payment details, proof, recordedBy |
| `activityLogs/{id}` | clinicId, actor (uid, name, role), action, target, time; written only by backend |
| `clinics/{id}/stats/{yyyy-MM}` | Monthly counters for dashboards |
| `settings/billing` | Plans, prices, grace/suspension days, payment instructions |
| `doctors.speciality` (one fixed key), `city`, `nameKey`, `doctorGroupId`, `specialityFlagged` | Doctor search + linking (D-31..D-33) |
| `doctors/{id}/private/admin.pmdcNumber` | PMDC number, Super Admin read only (D-33) |
| `clinics.location` (required) | Nearest first + Directions (D-31) |
| `doctorLinkSuggestions/{pairId}` | Possible same doctor list; `notSame` remembered (D-32) |

Backend functions needed (names indicative): `queueAction`, `clinicCreateWalkIn`, `clinicSearchPatients`, `setFollowUp`, `updateDoctorSchedule`, `inviteClinicLogin`, `disableClinicLogin`, `adminCreateClinic`, `adminUpdateClinic`, `recordPayment`, `waiveInvoice`, `adminLinkDoctors`, `adminMarkNotSame`, `adminUnlinkDoctor` (D-32; `saveDoctor` also builds the suggestions), `generateInvoices` (scheduled), `defaulterCheck` (scheduled), activity-log triggers.

---

## 12. Release phases

| Phase | Scope |
|---|---|
| **2a: Clinic MVP (pilot)** | W-01..W-13, W-17, W-18, W-19, W-22 · C-01..C-08, C-11..C-13 · A-04 (to onboard pilot clinics) |
| **2b: Clinic complete** | C-09 follow-ups, C-10 summary, C-14 export, C-15 billing banner, C-16 help |
| **3: Super Admin complete** | A-01..A-03, A-05..A-08 (automatic invoices, defaulters, activity log, dashboard) |

Pilot runs on 2a with 2–3 clinics, free month.

---

## 13. Success metrics (pilot)

- Average check-in time (code typed → Arrived)
- Walk-in creation time
- % of tokens booked through the app vs walk-in
- Average patient wait time per clinic
- Clinic feedback: fewer phone calls and disputes
- Clinics logging in daily

---

## 14. Open questions (confirm before building the related part)

| # | Question | Affects |
|---|---|---|
| ~~Q-W01~~ | ~~Repo location~~: **Closed**: same `Asani_app` repo as a monorepo (D-17, §2.1). | Setup |
| ~~Q-W02~~ | ~~Staff emails~~: **Closed**: one clinic login (clinic email), shared with the receptionist (D-18). | §4, §5 |
| ~~Q-W03~~ | ~~Next order~~: **Closed**: strict token number order with a "not arrived: Skip / Call anyway" prompt (D-24). | C-03 |
| ~~Q-W04~~ | ~~Doctor logins~~: **Closed**: doctors don't log in (D-18). | §4 |
| Q-W05 | Grace and suspension days: **7 and 15** OK? | A-06 |
| Q-W06 | Subscription prices per plan | A-08 |
| ~~Q-W07~~ | ~~Clinic edits patient details?~~ **Closed**: walk-ins only; app profiles are read-only at the clinic (D-40). | C-08 |
| ~~Q-W08~~ | ~~Notify on clinic cancel / No-show~~: **Closed**: push on clinic cancel with the reason, none on No-show (D-23). | C-04 |
| Q-W09 | Domain/URLs for the clinic web (e.g. `clinic.asani.app`) | Hosting |
| ~~Q-W10~~ | ~~Doctor changes~~: **Closed**: the clinic adds and manages its own doctors; Super Admin sees them (D-19). | C-11 |
| ~~Q-W11~~ | **Closed (D-41):** 4-digit manager PIN, server-checked and hashed, for Billing, Export, Add / Deactivate doctor and Change password (not leave or timings); 5 wrong → 15 min lock; Super Admin resets. Was: **Shared login & sensitive pages:** since the receptionist uses the manager's login, should **Billing, Export, Doctors and Change password** be protected by a short **manager PIN**? | C-11..C-15 |

---

## 15. Changes needed in other documents (when confirmed)

- **PRD.md**: Decisions log: update D-06 (Flutter Web), D-07 (clinic email + password), add D-15, D-16, D-17, D-18, D-19; close Q-01, Q-02, Q-10.
- **README.md**: repo structure (`apps/patient_app`, `apps/clinic_web`, `packages/asani_core`, workspace root) and commands.
- **docs/02-setup.md**: workspace setup, `flutter pub get` at root, running each app.
- **PROJECT_DOCUMENTATION.md**: §4, §5, §11, §14, §15, §21, §22 change log.
- **CONTEXT_FOR_CLAUDE.md**: §3 decisions, §4 (web instead of .exe), §5 (admin inside web).
- **AGENTS.md**: scope table: clinic web allowed when Phase 2 starts; super admin inside it.
- **ARCHITECTURE.md / DATABASE.md**: §11 additions above.
