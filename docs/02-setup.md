# 02 — Setup

Developer machine and Firebase setup for the monorepo: patient app, clinic web, shared packages and functions. Primary dev machine: **Windows + Android Studio**.

---

## 1. Install tools

| Tool | Version | Check |
|---|---|---|
| Flutter SDK | stable, with Dart ≥ 3.9 | `flutter --version` |
| Android Studio | latest stable + Flutter & Dart plugins | |
| Android SDK | API 35+, build-tools, platform-tools | `flutter doctor` |
| Java (bundled JDK 17 with Android Studio) | 17 | |
| Node.js | 22 (functions `engines`) | `node -v` |
| Firebase CLI | latest | `npm i -g firebase-tools` → `firebase --version` |
| FlutterFire CLI | latest | `dart pub global activate flutterfire_cli` |
| Java for emulators | **21** (the Firebase CLI 15 emulators need it; rules tests too) | `java -version` · `winget install EclipseAdoptium.Temurin.21.JDK` |
| Git + GitHub Desktop | | |
| VS Code (optional) | For TypeScript functions | |

Add Dart's pub cache bin to `PATH` (Windows: `%LOCALAPPDATA%\Pub\Cache\bin`) so `flutterfire` works.

Run `flutter doctor` and fix everything except iOS items (iOS needs a Mac, see §7).

---

## 2. Clone and install

```bash
git clone https://github.com/sarbuland-dev/Asani_App.git
cd Asani_App

flutter pub get                 # Dart pub workspace: patient_app, clinic_web, asani_core, asani_ui
cd functions && npm install && cd ..
cd tools/admin-scripts && npm install && cd ../..
cd tools/queue-sim && npm install && cd ../..
```

Run `flutter pub get` **at the repo root**, not inside an app: all members share one `pubspec.lock` at the root.
Layout (PRD-CLINIC-WEB §2.1):

| Folder | What |
|---|---|
| `apps/patient_app` | Patient app, Android + iOS |
| `apps/clinic_web` | Clinic dashboard + super admin, Flutter Web |
| `packages/asani_core` | Pure Dart: models, enums, PKT dates, phone utils, token code, `Fmt`, `AppLogger` |
| `packages/asani_ui` | Flutter: theme (colors, fonts, spacing, ThemeData) + shared widgets |
| `functions/` | Cloud Functions (TypeScript) |

---

## 3. Firebase projects (one-time, owner only)

Create **two** projects in the Firebase console:

| Project ID | Use |
|---|---|
| `asani-dev` (actual ID **`asani-b2b17`**, alias `dev` in `.firebaserc`) | Development, testing, MCP tools |
| `asani-prod` | Real clinics |

For **each** project:
1. Upgrade to **Blaze** plan → set a **budget alert** (e.g. $10/month for dev).
2. **Firestore** → Create database → Native mode → location **`asia-south1`** ⚠️ cannot be changed later.
3. **Authentication** → Sign-in method → enable **Phone**.
   - Settings → **SMS region policy** → *Allow* only **Pakistan (PK)**.
   - Dev only: add test phone numbers (e.g. `+92 300 0000001` → code `123456`) for quick testing without SMS.
4. **App Check** → register Android (Play Integrity) and iOS (App Attest). Use debug tokens in dev.
5. **Cloud Messaging** → iOS: upload an **APNs Auth Key** (.p8) from the Apple Developer account.
6. **Crashlytics** → enable.

Log in from the CLI:
```bash
firebase login
firebase use --add      # select asani-dev, alias "dev"
firebase use --add      # select asani-prod, alias "prod"
firebase use dev        # default to dev ALWAYS
```

---

## 4. Connect the Flutter app

Android application IDs: `pk.asani.patient.dev` (dev), `pk.asani.patient` (prod). iOS bundle IDs: same.

```bash
cd apps/patient_app

flutterfire configure --project=asani-dev \
  --out=lib/firebase_options_dev.dart \
  --android-package-name=pk.asani.patient.dev \
  --ios-bundle-id=pk.asani.patient.dev \
  --platforms=android,ios

flutterfire configure --project=asani-prod \
  --out=lib/firebase_options_prod.dart \
  --android-package-name=pk.asani.patient \
  --ios-bundle-id=pk.asani.patient \
  --platforms=android,ios
```

### Android SHA keys (required for Phone Auth + App Check)
```bash
cd android
./gradlew signingReport        # Windows: gradlew signingReport
```
Copy **SHA-1** and **SHA-256** for debug (and later release/upload keys) into Firebase console → Project settings → Android app. Then re-download `google-services.json` if asked.

> Missing SHA keys is the #1 cause of phone auth failures. See docs/08.

### Flavors
`android/app/build.gradle.kts` defines product flavors `dev` and `prod` with matching `applicationId`, and `google-services.json` placed in `android/app/src/dev/` and `android/app/src/prod/`.

`lib/main.dart` chooses options:
```dart
const env = String.fromEnvironment('ENV', defaultValue: 'dev');
final options = env == 'prod'
    ? prod.DefaultFirebaseOptions.currentPlatform
    : dev.DefaultFirebaseOptions.currentPlatform;
```

---

## 5. Run locally with emulators (default way to develop)

```bash
# repo root
firebase emulators:start --import=./emulator-data --export-on-exit
```
Emulator UI: http://localhost:4000

Seed data (first time or after a wipe):
```bash
cd tools/admin-scripts
set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080        # PowerShell: $env:FIRESTORE_EMULATOR_HOST="127.0.0.1:8080"
set FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
node seed-dev.js
```

Run the app:
```bash
cd apps/patient_app
flutter run --flavor dev --dart-define=ENV=dev --dart-define=USE_EMULATOR=true
```
When `USE_EMULATOR=true`, the app connects Auth, Firestore and Functions to the host machine. On a **physical phone**, also pass `--dart-define=EMULATOR_HOST=<your PC's LAN IP>` and start emulators with `"host": "0.0.0.0"` in `firebase.json`. On the Android emulator the host is `10.0.2.2`.

OTP in the Auth emulator: the code appears in the emulator terminal and the Emulator UI → Authentication.

---

## 5b. Clinic web

```bash
cd apps/clinic_web
flutter run -d chrome                                                         # demo backend, one-click logins
flutter run -d chrome --dart-define=BACKEND=firebase --dart-define=USE_FUNCTIONS_EMULATOR=true
flutter build web --release --dart-define=BACKEND=firebase                    # → build/web
```
Firebase mode needs Email/Password sign-in enabled on the dev project and a clinic or super admin login
(`tools/admin-scripts/create-clinic-login.js`, `create-super-admin.js`). Until Blaze, run the functions with
`cd functions && npm run serve:dev`. More in `apps/clinic_web/README.md`.

---

## 6. Queue simulator

Acts as the receptionist until the desktop app exists.
```bash
cd tools/queue-sim
node queue-sim.js status --doctor doc_ayesha            # today's queue
node queue-sim.js start  --doctor doc_ayesha            # sessionStatus=running
node queue-sim.js next   --doctor doc_ayesha            # complete current, call next
node queue-sim.js arrive --token tk_8f2a
node queue-sim.js skip   --token tk_8f2a
node queue-sim.js end    --doctor doc_ayesha            # remaining booked → noShow
```
Add `--project dev` to run against `asani-dev` instead of emulators (needs `serviceAccount.dev.json`, **never committed**).

---

## 5c. Patient app on a real Android phone + functions emulator

```bash
cd functions && npm run serve:dev                    # terminal 1: functions on this PC
adb reverse tcp:5001 tcp:5001                        # phone's 127.0.0.1:5001 → this PC
cd apps/patient_app
flutter run -d <phone id> --flavor dev --dart-define=BACKEND=firebase --dart-define=USE_FUNCTIONS_EMULATOR=true \
  --dart-define=EMULATOR_HOST=127.0.0.1 --dart-define=AUTH_TEST_MODE=true
```
`EMULATOR_HOST=127.0.0.1` keeps Firebase from rewriting the host to `10.0.2.2` (that only works inside the
Android emulator). Debug builds allow plain HTTP to 127.0.0.1 / localhost / 10.0.2.2
(`android/app/src/debug/res/xml/network_security_config.xml`); release builds stay HTTPS only.

---

## 7b. Android release signing (Play Store)

A prod release build **refuses to build** until this is set up (it is never signed with the debug key).
Sarbuland does this once, on his own machine:

```bash
# 1. Create the upload keystore (keep it OUTSIDE the repo, and back it up + the passwords)
keytool -genkey -v -keystore C:/Users/<you>/keys/asani-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload

# 2. Copy the template and fill in the passwords and the path
cd apps/patient_app/android
copy key.properties.example key.properties

# 3. Build the Play Store bundle
cd .. && flutter build appbundle --flavor prod --release
```

- `key.properties` and `*.jks` are git-ignored; never commit them or paste the passwords anywhere.
- Turn on **Play App Signing** in the Play Console (Google keeps the app signing key; this is only the upload key).
- Add the upload key's (and Play's app signing key's) **SHA-1 and SHA-256** to the prod Firebase Android app
  (`keytool -list -v -keystore … -alias upload`), or phone login fails in the release build.
- Losing the upload key is recoverable with Play App Signing (Google can reset it), but keep a backup anyway.

---

## 7. iOS

iOS builds need **macOS + Xcode**. Options:
1. **Codemagic** (or similar cloud macOS CI): build, sign and upload to TestFlight from Windows.
2. A borrowed/shared Mac for first-time signing setup.

One-time iOS steps (on a Mac or via CI):
- Apple Developer account, App ID `pk.asani.patient` with **Push Notifications** capability.
- In Xcode: enable *Push Notifications* and *Background Modes → Remote notifications*.
- Phone auth: add the **REVERSED_CLIENT_ID** URL scheme from `GoogleService-Info.plist`.
- APNs key uploaded to Firebase (step 3.5).
- `cd ios && pod install`.

---

## 8. Functions

```bash
cd functions
npm run build
npm run lint
npm test                       # uses emulators
firebase deploy --only functions --project dev     # only when asked
```
Set secrets with `firebase functions:secrets:set NAME` (none needed in Phase 1).

Rules tests (Firestore emulator, Java 21): `cd functions && npm run test:rules`.

---

## 8b. CI (GitHub Actions)

`.github/workflows/` has one workflow per part; each runs only when its paths change:

| Workflow | Runs on changes in | Does |
|---|---|---|
| `patient_app.yml` | `apps/patient_app/**`, `packages/**`, root pubspec | analyze, test, dev debug APK |
| `clinic_web.yml` | `apps/clinic_web/**`, `packages/**`, root pubspec | analyze, test, web build; Hosting deploy **disabled** until the `FIREBASE_SERVICE_ACCOUNT_ASANI_DEV` secret and a `hosting` block exist |
| `functions.yml` | `functions/**`, `firestore.rules`, indexes, `firebase.json` | lint, build, unit tests, rules tests on the emulator; never deploys |

---

## 9. Files that must never be committed

Already in `.gitignore`:
```
**/serviceAccount*.json
**/.env*
**/key.properties
**/*.jks
**/*.keystore
**/*.p8
emulator-data/
apps/patient_app/android/app/src/prod/google-services.json
apps/patient_app/ios/Runner/prod/GoogleService-Info.plist
```
The dev `google-services.json` may be committed (it is not a secret, but keeping prod out is a good habit).
