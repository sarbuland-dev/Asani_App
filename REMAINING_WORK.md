# Remaining work

Last updated: 2026-11-13. Status of the patient app: all 12 demo→Firebase steps are coded
(see `apps/patient_app/DEMO_TO_FIREBASE.txt`). This file lists what is still open.

## 1. Step 10 – push notifications (paused)
- [ ] Android APK build with the new packages (first Gradle build hung / very slow):
      `flutter build apk --debug --flavor dev --dart-define=BACKEND=firebase`
- [ ] Real phone test on the Redmi: primer "Allow" popup, push arrives with the app closed,
      tapping it opens the token; follow-up reminder tap opens pre-filled booking.
- [ ] `getToken` / `onTokenRefresh` are deprecated in firebase_messaging 17; move to
      `register()` / `onRegistered` when the server can send to Installation IDs.

## 2. Blaze plan on the dev project (asani-b2b17)
- [ ] Upgrade to Blaze + budget alert → real SMS login works for real numbers.
- [ ] `firebase deploy --only functions --project asani-b2b17` (bookToken, cancelToken,
      deleteAccount, onTokenWrite, onQueueDayWrite, followUpReminders) so the app works
      without this PC running the emulator.
- [ ] After deploy: stop using `USE_FUNCTIONS_EMULATOR`, the manual `run-followup-reminders.js`
      (scheduled at 09:00 PKT) and `run-auto-close.js` (scheduled `autoCloseTokens` at 03:00 PKT).
- [ ] Check booking speed after deploy (8–18 s on the emulator today).

## 3. Production project (only before launch, after Blaze)
- [ ] Create `asani-prod` (Blaze, Firestore asia-south1, Phone auth, SMS region: Pakistan only).
- [ ] Sarbuland runs `flutterfire configure` for prod → `lib/firebase_options_prod.dart` and
      `android/app/src/prod/google-services.json`. Add both to `.gitignore` first (never commit).
- [ ] Release keystore: signing config is ready (android/key.properties, docs/02-setup.md §7b); Sarbuland creates the keystore and adds its SHA-1/SHA-256 in the prod console.
- [ ] App Check: register Play Integrity (Android) and App Attest (iOS) in the console.
- [ ] Sarbuland deploys rules, indexes and functions to prod himself (AGENTS.md §7).

## 4. Launch preparation
- [ ] Crash reporting + basic analytics (PRD F-12).
- [ ] Privacy Policy and Terms pages, real domain for links (PRD Q-06).
- [ ] Play Store listing, screenshots, data-safety form; App Store later.

## 5. Testing gaps
- [ ] Install Java 21 (`winget install EclipseAdoptium.Temurin.21.JDK`) and run
      `cd functions && npm run test:rules` (written, never run).
- [ ] Integration tests for the Firestore repositories, PushService and the callables on emulators.
- [ ] Real ESLint for functions (`npm run lint` is only `tsc` today).

## 6. Smaller issues from the 2026-11-12 review (🟡 / ⚪)
- [ ] Remove the demo backend from Firebase mode (attachAccount, useDoctors, usePatients bridges).
- [ ] After Blaze: onTokenWrite + onQueueDayWrite both run evaluateQueue (correct but double cost).
- [ ] Search only looks in the selected city; offer other cities when nothing is found.
- [ ] "Open today" stays on after all sessions ended for the day.
- [ ] My Tokens shows the last 100 only, and only tokens the user booked (not staff walk-ins via `patientOwnerUid`).
- [ ] deleteAccount sets `patientSnapshot.phone` to null; the model expects a string (staff app could crash).
- [ ] Recent clinics re-fetch on every token change.
- [ ] Account says "Notifications On" on web, where pushes never arrive; label says "Notifications" but it is queue alerts.
- [ ] Names shown as typed ("ali"); "Book a token for Test" uses the first word of the name.
- [ ] Functions: engines Node 22 vs local Node 26 warning; update firebase-functions.

## 7. Clinic web (`apps/clinic_web`, PRD-CLINIC-WEB.md v0.4)
Done (2026-11-13): all clinic screens W-01..W-22 and super admin A-10..A-17; one clinic login,
the clinic manages its own doctors. Two backends: demo and Firebase (`--dart-define=BACKEND=firebase`).
Code done, **not tested end-to-end yet**: clinic/admin Cloud Functions (`functions/src/clinic`,
`functions/src/admin`), Firestore rules + indexes for clinic/admin roles, rules test
`functions/test/rules/clinic.test.js`, admin scripts `create-super-admin.js`, `create-clinic-login.js`,
`backfill-clinic-ids.js`, `bookToken` now sets `patients.clinicIds` and monthly stats.
Still open:
- [ ] Install Java 21 (emulators): `winget install EclipseAdoptium.Temurin.21.JDK`, then
      `npm run test:rules` and an emulator run of clinic web + patient app together.
- [ ] Console: enable Email/Password sign-in on asani-b2b17 (still disabled on 2026-11-14:
      `PASSWORD_LOGIN_DISABLED`); "Set your Asani password" email template.
- [x] 2026-11-14: rules + indexes deployed to dev; test logins `admin@asani.test` (Super Admin) and
      `alshifa@asani.test` (Al-Shifa) created; passwords in `tools/admin-scripts/dev-test-logins.local.txt`
      (git-ignored); `backfill-clinic-ids.js` run on dev.
- [x] 2026-11-14 backend E2E on dev (functions emulator): 3 walk-ins + 1 app booking (A-4) on d_ayesha,
      4 × Next → notified `ahead3, ahead2, ahead1, yourTurn` (max 4); clinic reads own tokens/patients/billing,
      cannot read other clinics' billing or `users/`; patient cannot read walk-ins or billing.
- [x] 2026-11-14 UI test, both apps on Firebase in the browser: Email/Password enabled; clinic login →
      Queue Board shows live data; app booked B-1 (Dr. Kamran) → appeared on the board as "App / Booked";
      Start + Next on the web → app showed "Your turn now", "Now serving B-1". Each queueAction takes
      ~8–10 s on the emulator (re-check after the functions are deployed).
- [ ] App: My Tokens → Active still lists a past day's token that stayed "booked" (C-3 from 13 Nov).
      Needs a rule: hide/mark past-day booked tokens, or end-of-day job sets them to noShow (confirm).
- [ ] Dev test data left on 14 Nov: Dr. Ayesha A-1..A-4 (3 walk-ins + Test User) and Dr. Kamran B-1.
- [ ] Blaze: deploy functions (incl. `billingJobs` schedule); until then functions run on the emulator.
- [ ] Reminder email for defaulters needs a mail service (only recorded today).
- [ ] Payment proof upload (Storage), "Send payment proof" for clinics (P2).
- [ ] Real print test on a thermal 80 mm printer and A5 with `--kiosk-printing`.
- [ ] Open questions Q-W03, Q-W05..Q-W09, Q-W11 (manager PIN). Q-W08 (notify on clinic cancel / no-show) not built.
- [ ] Optional: Dart pub workspace (PRD §2.1) and CI path filters.
- [ ] Firebase Hosting site for dev/prod (needs a domain, Q-W09).

## 8. App ↔ web review (2026-11-14)
Checked live on dev: booking → board, Next → "Your turn now", 4-step notifications, rules
(clinic sees only its own data, patient cannot read walk-ins/billing), patient search by name and phone,
Daily summary, Doctors, Billing, Super Admin dashboard + Clinics list.

🔴 Must fix. **All 4 decided on 2026-11-14 (PRD.md D-21..D-24) and built the same day (not committed yet):**
1. ✅ D-21 built 2026-11-14: `autoCloseTokens` (03:00 PKT, `functions/src/queue/autoClose.ts`) + tests.
   Until Blaze run it by hand: `node tools/admin-scripts/run-auto-close.js --project dev`. Ran on dev:
   C-3 (13 Nov) → No-show, shows under Past; Test User's active count is free again.
2. ✅ D-22 built 2026-11-14: `clinicLookupPhone` (only id/name/relation/gender/age, 30 lookups / 10 min per
   clinic); walk-in dialog shows "On the Asani app, new to this clinic"; picked profile gets this `clinicId`;
   app lists walk-ins (`patientOwnerUid` + `source: walkIn`), alerts go to `patientOwnerUid`, no Cancel button
   on walk-ins. Tested on dev: Zara Test (C-5) walk-in shows in the app; no duplicate profile.
   Still open: the Patients page search stays this-clinic-only (by design); a walk-in's token screen still says
   "Show this screen at reception".
3. ✅ D-23 built 2026-11-14: `notifyClinicCancel` (claim `cancelNotifiedAt`, then one push; tap → book same
   clinic/doctor) from `queueAction` cancel and `cancelDoctorTokens` (which now also re-runs `evaluateQueue`).
   App: "Cancelled by clinic · reason", "Book another day", CANCELLED stamp on the slip. Web cancel dialogs say
   the patient is notified. Tested on dev (C-5); real push on a phone not tested yet (step 10).
   Not done: when the app is open, the cancel push shows no in-app banner (the token screen updates live).
4. ✅ D-24 built 2026-11-14: `clinic/nextOrder.ts` (+ tests); Next = re-checked-in Skipped (`priorityAt`) first,
   else lowest Booked/Arrived; Booked pick → "C-8 has not arrived · Back / Skip / Call anyway" on the board;
   check-in by code and "Arrived · call next" work for Skipped tokens; demo backend follows the same rules.
   Tested on dev (Dr. Sana C-4 … C-8). Not done: the board's Waiting list is still sorted by number, so a
   re-checked-in Skipped patient isn't shown at the top even though Next calls them first.

Original findings:
- [ ] **Old tokens never close.** End session closes only Booked/Called; Arrived/On hold stay open, and a
      day that was never ended keeps all tokens open. They stay "active" forever: count toward the
      5-active-token limit (Test User is blocked now: `too-many-active`), show under My Tokens → Active with
      "The live queue shows here on that day". Fix: nightly job closes past-day tokens + limit/Active ignore
      past dates. **Decide:** past-day Booked/Arrived/On hold → No-show?
- [ ] **Walk-in of an app user is not linked to the app.** Clinic search only finds patients who visited
      this clinic, so a new walk-in creates a new profile. With an existing account phone it gets that
      `ownerUid` → shows as an extra (duplicate) family member in the app. The token has
      `bookedByUserId: null` → no queue notifications, and My Tokens (query on `bookedByUserId`) never
      shows it (PRD C-06 says it should). **Decide:** match by phone + name to the existing profile, notify
      `patientOwnerUid`, list tokens by `patientOwnerUid` too.
- [ ] **Clinic cancel / no-show / leave bulk-cancel is silent.** No notification (Q-W08), and the app
      shows only "Cancelled on …" without "by clinic" or the reason. **Decide** the notification text.
- [ ] **Next order vs "patients ahead".** Next calls the lowest *Arrived* first (Q-W03), but "ahead" and the
      3-2-1 alerts count by token number. A booked A-3 can get "You're next" while A-7 (arrived) is called,
      and be passed over again and again. **Decide** Q-W03 (strict number order, or count ahead the same way).

🟡 Should fix
- [ ] App: On hold shows the normal queue (no "You're on hold" message); Skipped shows "Book again" even
      though the clinic can recall it.
- [x] `cancelDoctorTokens` now runs `evaluateQueue` (D-23 change).
- [ ] Each clinic action takes 8–10 s on the emulator; re-measure after deploy.
- [ ] Super Admin dashboard / Clinics list show partial numbers (e.g. Active 1, Tokens 0) for a few seconds
      while loading, with no loading state.
- [ ] A new clinic from the wizard is visible in the patient app at once with 0 doctors.
- [ ] Billing "How to pay" shows placeholder bank/IBAN details.
- [ ] Undo last Next: the patient already got "Your turn now"; after undo the app goes back to waiting.
