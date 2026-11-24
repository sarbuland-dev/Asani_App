# Remaining work

Last updated: 2026-11-13. Status of the patient app: all 12 demo→Firebase steps are coded
(see `apps/patient_app/DEMO_TO_FIREBASE.txt`). This file lists what is still open.

## 1. Step 10 – push notifications
- [x] 2026-11-14: Android APK builds (`flutter build apk --debug --flavor dev`, 4m 50s) after compileSdk 37,
      AGP 9.1.1 and Gradle 9.3.1 (flutter_local_notifications 23 / androidx.core 1.19 need them).
- [x] 2026-11-14 Redmi (25028RN03A) test: login with test number, booking A-6, primer → Android "Allow" popup,
      device token saved, clinic Next → "Your turn now" push with the app in the background, tap opens A-6.
      Needed: debug-only cleartext to the emulator + no 10.0.2.2 remap when EMULATOR_HOST is set (adb reverse).
- [ ] Not tested yet: follow-up reminder tap opens pre-filled booking; push with the app fully killed; iPhone.
- [x] 2026-11-14 notification icon: white "a" mark (res/drawable/ic_notification.xml) + teal header colour; checked on the Redmi.
- [x] 2026-11-22 Decided D-39 ("You're next" at 0 ahead when someone is with the doctor), built. Was: a patient who books when nobody is waiting (0 ahead, someone with the doctor) gets no
      "You're next", only "Your turn now" (steps.ts sends ahead1..3 only for 1..3 ahead).
- [x] 2026-11-14 StatTile values stay on one line and shrink to fit ("Any moment" no longer breaks); checked on the Redmi.
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
- [x] 2026-11-22 Empty search offers other cities with matches ("Found in other cities: Karachi (1)"; tap switches the city).
- [ ] "Open today" stays on after all sessions ended for the day.
- [x] 2026-11-22 My Tokens → Past has "Load older tokens" beyond the live 100 (incl. walk-ins; new index). Was: My Tokens shows the last 100 only, and only tokens the user booked (not staff walk-ins via `patientOwnerUid`).
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
- [x] 2026-11-22 Q-W07 → D-40 (clinic edits walk-ins only) and Q-W11 → D-41 (manager PIN) built.
- [ ] Still open: Q-W05 (grace/suspension days), Q-W06 (prices), Q-W09 (domain) — part of the payments step (§10) / hosting.
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
   Tested on dev (Dr. Sana C-4 … C-8). ✅ 2026-11-21 (D-35): the board's Waiting list now puts re-checked-in
   Skipped patients right after the Called patient, with a "Next up" label.
5. ✅ D-34 + D-35 built 2026-11-21 (skipped patient): `queue/skipNotice.ts` sends one "You missed your turn"
   push on skip (claim `skipNotifiedAt`); a skip after "Your turn now" clears `notified.yourTurn` once
   (`turnRepeatUsed`) so recall sends one more "Your turn now". App: Skipped stays under Active with the amber
   "Your turn passed · Go to reception" card (slip kept, no Book again); `priorityAt` → "You're next · called
   right after the current patient". Unit tests pass. Not tested yet: on dev with a real phone (QA-4b in
   docs/07). `tools/queue-sim skip` does not send the skip push (it only writes the status).

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
- [x] 2026-11-22 D-37 amber "You're on hold" note. Was: App: On hold shows the normal queue (no "You're on hold" message).
- [x] App: Skipped showed "Book again" even though the clinic can recall it (fixed by D-35, 2026-11-21).
- [x] `cancelDoctorTokens` now runs `evaluateQueue` (D-23 change).
- [ ] Each clinic action takes 8–10 s on the emulator; re-measure after deploy.
- [ ] Super Admin dashboard / Clinics list show partial numbers (e.g. Active 1, Tokens 0) for a few seconds
      while loading, with no loading state.
- [ ] A new clinic from the wizard is visible in the patient app at once with 0 doctors.
- [ ] Billing "How to pay" shows placeholder bank/IBAN details.
- [x] 2026-11-22 D-38 no push on undo, one repeat "Your turn now". Was: Undo last Next: the patient already got "Your turn now"; after undo the app goes back to waiting.

## 9. Search by doctor + same doctor at two clinics (D-31..D-33, 2026-11-19)
Docs approved (PRD F-13/F-14, D-31..D-33; DESIGN S-06b/S-18; DATABASE; PRD-CLINIC-WEB C-11/C-13/A-09; docs/07).
- [x] 2026-11-21 Step 1 backend: `saveDoctor` (speciality key, admin-only PMDC, suggestions), Link / Not the same /
      Unlink functions, rules + rules tests (14/14), indexes, `migrate-doctor-search.js`, Firebase code in the web.
- [x] 2026-11-21 `migrate-doctor-search.js --project dev` run: 20 doctors updated, 2 "Dr. Test (24h)" flagged as Other,
      1 suggestion (the two test doctors). Clinics still without a location: Noor, Care Plus, Rehman, Shifa Family (step 2).
- [x] 2026-11-22 Step 2 location: geolocator (Android/iOS/web parts only: the Linux part clashes with
      connectivity_plus over dbus), permission text, real `DeviceLocationService` (demo keeps a fixed Johar Town spot),
      S-18 as a plain card on the Doctors tab + "Turn on" note, clinic location required in `adminCreateClinic` /
      `updateClinicSettings` and both web forms (paste a Google Maps link or "lat, lng"), "Also sits at" on the clinic page.
- [ ] Dev data: Noor, Care Plus, Rehman and Shifa Family have no location; add it in Clinic settings (or the Super Admin)
      before their doctors show distance. Their settings can't be saved without it now.
- [x] 2026-11-19 **Basic placeholder UI on demo data** (plain Material, real design later in its own chat):
      patient app Search tabs (Clinics | Doctors), speciality chips, doctor list with distance and "Also sits at";
      clinic web speciality picker + PMDC field, Super Admin "Same doctor" screen (Link / Not the same / Unlink).
      Pure logic in `asani_core` (speciality list, distance, cards, PMDC) with tests.
- [ ] **UI still open:** location primer (S-18, needs geolocator), required clinic location in the wizard/settings,
      "Also sits at" on the clinic page. Full list was: patient app Search tabs, Doctors tab, doctor card with "Also sits at", location primer (S-18),
      "Also sits at" on the clinic page; clinic web speciality picker, PMDC field ("on file · Change"), required
      location (wizard + settings), "Please pick a speciality" chip, Super Admin A-09 screen + Linked chip in A-03.

## 10. Step 5 – payments (ON HOLD, 2026-11-22)
Sarbuland will confirm a few things first; nothing built yet. Open choices (asked 2026-11-22):
- [ ] **Payment proof:** a screenshot upload needs Firebase Storage (Blaze). Proposal: for now a reference form
      (method, amount, date, transaction ID, note) → Super Admin sees "Payment reported" and confirms with Record
      payment; screenshot upload after Blaze.
- [ ] **Defaulter reminder:** automatic email needs Blaze + a mail service. Proposal: Super Admin Email / WhatsApp
      buttons on a defaulter that open their own Gmail / WhatsApp with the reminder text; automatic email after Blaze.
- [ ] **Bank details:** "How to pay" is editable in Super Admin → Settings but starts with fake IBAN / JazzCash
      numbers. Proposal: empty default ("Payment details will be shared by Asani") until Sarbuland types the real ones.

## 12. Clinic web UI redesign to the board (Deep forest, 2026-11-24)
- [ ] Board approval for every web screen (W-01 login animation still open).
- [ ] D-51: remove the QR standee card from `apps/clinic_web/lib/features/settings/clinic_settings_screen.dart`
      (and `core/widgets/qr_view.dart` if nothing else uses it) and the print templates screen.
- [ ] Open question: does **Arrived & Print** still print the Asani clinic form (C-07), or nothing at all?

## 13. Move to Supabase (D-52, 2026-11-24)
Plan: `docs/10-supabase-migration.md`. Once it lands, §2 (Blaze), §3 (Firebase prod) and §11 (TTL) are replaced by it.
- [x] 2026-11-24 Phase 0: plan approved by Sarbuland; open questions S-1…S-7 answered (plan §7).
- [ ] Phase 1: setup, tables, RLS, seed · 2: booking + queue in Postgres · 3: push + `pg_cron`
- [ ] Phase 4: patient email login · 5: patient app data · 6: clinic/admin backend · 7: clinic web · 8: clean-up + docs
- [ ] Before the pilot: decide the pause risk (Pro plan or keep-alive) and backups.

## 11. Rules / indexes not yet on the dev project (2026-11-23)
- [x] 2026-11-22 Rules and indexes deployed to asani-b2b17 (Sarbuland's go-ahead).
- [ ] After Blaze: add the TTL policy on `notifications.expireAt` (D-45; Firestore refused it with billing disabled).
      Add to `firestore.indexes.json` → fieldOverrides: `{"collectionGroup":"notifications","fieldPath":"expireAt","ttl":true,"indexes":[]}`.

