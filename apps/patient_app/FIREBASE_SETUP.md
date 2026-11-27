# Connect the app to Firebase (dev project: asani-b2b17)

> **D-52 (2026-11-26): Firebase is now used ONLY for push (FCM).** Login, data and functions are on Supabase
> (docs/02-setup.md §2b). From this guide only the parts that create the Firebase app config still matter:
> `flutterfire configure` → `lib/firebase_options_dev.dart` / `google-services.json`, and the Android SHA keys.
> Ignore everything about Phone Auth, Firestore, rules, indexes, functions and the Blaze plan.

The code is ready. These steps need **your** Google account, so only you can do them.
Takes about 20 minutes. Do them in order. Full background: `docs/02-setup.md`.

What works after this: **real SMS login** (Firebase Auth), your account and "Self" profile saved
in **Firestore**. Clinics, queues, tokens and family still use demo data until they move to Firebase next.

---

## 1. Install the tools (once)

1. **Node.js LTS**: download from https://nodejs.org and install (tick "Add to PATH").
2. Open a **new** terminal and run:

```bash
npm install -g firebase-tools
```

```bash
dart pub global activate flutterfire_cli
```

3. Sign in with your Google account (opens the browser):

```bash
firebase login
```

## 2. Create the project in the Firebase console

Go to https://console.firebase.google.com:

1. **Add project** → name **asani-dev** (the project ID must be `asani-dev`; if taken, note the real ID and tell me).
   Google Analytics: optional.
2. **Upgrade to Blaze** (needed for real SMS), then set a **budget alert**, e.g. $10/month.
   You can skip Blaze for now and only use test numbers (step 4).
3. **Build → Firestore Database → Create database** → Native mode → location **asia-south1 (Mumbai)**.
   ⚠️ The location can't be changed later.
4. **Build → Authentication → Get started → Sign-in method → Phone → Enable.**
   - Add a test number: **+92 300 0000001** with code **123456** (no SMS is sent, free).
   - Settings → **SMS region policy** → Allow only **Pakistan**.

## 3. Connect the app

From the repo root:

```bash
cd apps/patient_app
```

```bash
flutterfire configure --project=asani-b2b17 --out=lib/firebase_options_dev.dart --platforms=android,ios,web --android-package-name=pk.asani.patient.dev --ios-bundle-id=pk.asani.patient.dev --android-out=android/app/src/dev/google-services.json
```

This replaces the placeholder `lib/firebase_options_dev.dart` and registers the Android, iOS and web apps.
If it asks to add the Google Services Gradle plugin, answer **yes**.

## 4. Add the Android SHA keys (needed for phone login on Android)

```bash
cd android
```

```bash
./gradlew signingReport
```

Copy **SHA-1** and **SHA-256** of the `debug` variant into Firebase console → Project settings →
Your apps → Android (`pk.asani.patient.dev`) → **Add fingerprint**.

## 5. Upload the security rules and indexes

From the repo root (this is a deploy to asani-dev only; never run it against prod):

```bash
firebase deploy --only firestore:rules,firestore:indexes --project asani-b2b17
```

## 6. Run with Firebase

Android phone or emulator:

```bash
flutter run --flavor dev --dart-define=BACKEND=firebase
```

Browser (Chrome):

```bash
flutter run -d chrome --dart-define=BACKEND=firebase
```

Log in with the test number **300 0000001** and code **123456**, or your real number (Blaze only).

**No reCAPTCHA while testing:** add `--dart-define=AUTH_TEST_MODE=true`. Then only the test numbers
from the Firebase console work, with no picture puzzle. Real users on Android phones normally don't see
reCAPTCHA either: Firebase checks the app silently with Play Integrity (enable the
**Play Integrity API** for the project in Google Cloud console). The browser always uses reCAPTCHA.

In **Android Studio**: Run → Edit Configurations → set **Build flavor** to `dev` and
**Additional run args** to `--dart-define=BACKEND=firebase`.

---

## Optional: run fully offline with the emulators

Needs Java (Android Studio's is fine). From the repo root:

```bash
firebase emulators:start --import=./emulator-data --export-on-exit
```

Then:

```bash
flutter run --flavor dev --dart-define=BACKEND=firebase --dart-define=USE_EMULATOR=true
```

The OTP appears in the emulator terminal and at http://localhost:4000 → Authentication.
Note: the Firestore emulator uses port **8080**, so run the web preview on another port
(`flutter run -d web-server --web-port 8090 ...`).

## Without Firebase (demo mode, as before)

```bash
flutter run --flavor dev
```

Login code is **123456**; nothing leaves the phone.

---

## If something goes wrong

| Problem | Fix |
|---|---|
| "Firebase is not configured for asani-dev yet" | Step 3 wasn't run, or ran with a different `--out` path |
| Android: `app-not-authorized` / `missing-client-identifier` | SHA keys missing (step 4) |
| `permission-denied` when finishing sign-up | Rules not deployed (step 5) |
| No SMS arrives | Use the test number, or check Blaze + SMS region policy |
| "SMS unable to be sent until this region enabled" | Authentication → Settings → SMS region policy → Allow → Pakistan |
| `billing-not-enabled` with a real number | Real SMS needs the **Blaze** plan; test numbers work on Spark |
| Build error about `google-services.json` | It must be in `android/app/src/dev/` (step 3 `--android-out`) |
