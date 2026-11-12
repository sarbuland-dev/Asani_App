# Remaining work

Last updated: 2026-11-12. Status of the patient app: all 12 demo→Firebase steps are coded
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
- [ ] After deploy: stop using `USE_FUNCTIONS_EMULATOR`, and the manual
      `run-followup-reminders.js` (the scheduled function does it at 09:00 PKT).
- [ ] Check booking speed after deploy (8–18 s on the emulator today).

## 3. Production project (only before launch, after Blaze)
- [ ] Create `asani-prod` (Blaze, Firestore asia-south1, Phone auth, SMS region: Pakistan only).
- [ ] Sarbuland runs `flutterfire configure` for prod → `lib/firebase_options_prod.dart` and
      `android/app/src/prod/google-services.json`. Add both to `.gitignore` first (never commit).
- [ ] Release keystore; add its SHA-1/SHA-256 in the prod console.
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

## 7. Clinic app (Flutter for web) – waiting for Sarbuland's confirmation
Proposed: build it in this repo as `apps/clinic_web`, sharing `asani_core`, rules and functions.
Before any code:
- [ ] Confirm, then update AGENTS.md (§2 says clinic app "not started"), PRD and ARCHITECTURE.
- [ ] Staff login: phone/username + password; accounts created by an admin script.
- [ ] Roles: receptionist only in v1, or also a doctor view?
- [ ] V1 features: today's queue, start/pause/end session, next patient, arrived/skip/hold,
      walk-in tokens (ARCHITECTURE §10 contract — what queue-sim does today).
- [ ] Staff custom claims (`role`, `clinicId`) + Firestore rules + rules tests.
- [ ] Needs Blaze to give it to a real clinic.
