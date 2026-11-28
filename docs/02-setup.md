# 02 — Setup

Developer machine and project setup for the monorepo: patient app, clinic web, shared packages and the Supabase
backend. Primary dev machine: **Windows + Android Studio**.

Since D-52 the backend is **Supabase**; Firebase is used only for push notifications (§3, §4).

---

## 1. Install tools

| Tool | Version | Check |
|---|---|---|
| Flutter SDK | stable, with Dart ≥ 3.9 (CI uses Flutter 3.44.6) | `flutter --version` |
| Android Studio | latest stable + Flutter & Dart plugins | |
| Android SDK | API 35+, build-tools, platform-tools | `flutter doctor` |
| Java (bundled JDK 17 with Android Studio) | 17 | |
| Node.js | 22 (database test tools, queue simulator, Supabase CLI through `npx`) | `node -v` |
| Chrome | latest (clinic web) | |
| Git + GitHub Desktop | | |
| Firebase CLI + FlutterFire CLI | only to create the push config again (§4) | |

Docker and the Firebase emulators are **not** needed.

Run `flutter doctor` and fix everything except iOS items (iOS needs a Mac, see §7).

---

## 2. Clone and install

```bash
git clone https://github.com/sarbuland-dev/Asani_App.git
cd Asani_App

flutter pub get                 # Dart pub workspace: patient_app, clinic_web, asani_core, asani_ui
cd tools/db-test && npm install && cd ../..
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
| `supabase/` | Migrations, seed, database tests, Edge Functions |
| `tools/db-test`, `tools/queue-sim` | Database test tools and the queue simulator |

---

## 2b. Supabase (D-52, the backend)

We use the **cloud project only** (no Docker, docs/10 §7 S-1). Firebase stays for push (FCM) only.

**One-time, owner (Sarbuland):**
1. Sign up at supabase.com (free plan) → **New project**: name `asani-dev`, region **South Asia (Mumbai)**, a strong
   database password (keep it in your password manager, never in the repo).
2. Project → **Connect** → copy the **Session pooler** URI (`postgresql://postgres.<ref>:[YOUR-PASSWORD]@aws-…pooler.supabase.com:5432/postgres`),
   put the password in it and save it as one line in **`supabase/.db-url.local`** (git-ignored).
3. Project → **Settings → API**: send the agent the **Project URL** and the **anon / publishable key** (both public).
   The **service_role / secret key** stays private (only for Edge Function secrets and admin tools later).

Dev project: `asani-dev`, URL `https://lgnbxxcmogbbzmuqyrgu.supabase.co`, region Tokyo (`ap-northeast-1`).
In the DB URL, write special characters in the password URL-encoded (`@` → `%40`) and no `[ ]` around it.
The CLI needs `?sslmode=require` at the end of the URL (the test runner does not).

**Supabase CLI** (no global install needed; `npx` downloads it the first time, about 30 MB):
```powershell
npx supabase@latest --version
npx supabase@latest login                         # opens the browser once
npx supabase@latest link --project-ref <ref>      # <ref> = the id in the project URL; asks for the DB password
```

**Apply the tables, security and seed** (from the repo root):
```powershell
$u = (Get-Content supabase\.db-url.local -Raw).Trim() + '?sslmode=require'
npx supabase@latest db push --db-url $u --include-seed
```
`db push` applies only new files in `supabase/migrations`, in name order. Never edit a migration that was already pushed;
add a new one.

**Run the database tests** (RLS, booking and queue, push jobs, login, clinic and admin). Each test file runs in a transaction that is rolled
back, so nothing stays in the dev database:
```powershell
cd tools/db-test; npm install; node run.js
```

| Folder | What |
|---|---|
| `supabase/migrations/` | Tables, RLS, Postgres functions (in order) |
| `supabase/seed.sql` | Dev clinics and doctors (same as the demo backend) |
| `supabase/tests/database/` | pgTAP tests |
| `supabase/functions/` | Edge Functions (`send-push`, `admin-clinic-login`) |
| `tools/db-test/` | Test runner and smoke tests for the cloud database |

**Patient email login (D-52, phase 4): Supabase dashboard settings** (owner, once per project):
1. **Authentication → Sign In / Providers → Email**: Email provider on; **Email OTP Expiration = 600** seconds;
   **Email OTP Length = 6**.
2. **Authentication → Emails → Templates**: in **Magic Link** *and* **Confirm signup**, set
   - Subject: `Your Asani login code`
   - Body (no link, only the code):
     ```html
     <h2>Your Asani login code</h2>
     <p>Enter this code in the Asani app:</p>
     <p style="font-size:28px;font-weight:700;letter-spacing:6px">{{ .Token }}</p>
     <p>It expires in 10 minutes. If you did not ask for it, you can ignore this email.</p>
     ```
3. **Custom SMTP with Brevo** (Supabase's built-in email only reaches your own team's addresses, about 2 per hour,
   for testing):
   - brevo.com → sign up (free, 300 emails/day) → **Senders, Domains & Dedicated IPs → Senders → Add a sender**
     (e.g. `no-reply@…` or your Gmail) and confirm it from the email Brevo sends.
   - **SMTP & API → SMTP → Generate a new SMTP key**. Note the server `smtp-relay.brevo.com`, port `587`, your
     **SMTP login** (looks like `xxxx@smtp-brevo.com`) and the key. Never commit the key.
   - Supabase **Authentication → Emails → SMTP Settings → Enable custom SMTP**: sender email = the Brevo sender,
     sender name `Asani`, host `smtp-relay.brevo.com`, port `587`, username = SMTP login, password = SMTP key.
   - **Authentication → Rate Limits**: raise "emails sent" to about 100 per hour once SMTP works.
   - Until we have our own domain (Q-06) codes may land in spam; tell testers to check spam.
4. Run the app: `flutter run --flavor dev --dart-define=BACKEND=supabase`.

**Clinic web on Supabase (D-52, phase 7): dashboard settings** (owner, once):
1. **Authentication → URL Configuration**: Site URL `http://localhost:8092`; Redirect URLs add `http://localhost:8092/**`
   (later the real web address too).
2. **Authentication → Emails → Templates → Invite user**: subject `Set your Asani password`; keep the
   `{{ .ConfirmationURL }}` link (clinics click a link; patients get a code). **Reset password**: subject
   `Reset your Asani password`, same link.
3. Dev logins without email: `node tools/db-test/create-login.js --role superAdmin --email … --name …` and
   `--role clinic --clinic c_alshifa --email … --name …` (passwords go to the git-ignored
   `tools/admin-scripts/dev-test-logins.local.txt`).
4. Run: `cd apps/clinic_web; flutter run -d chrome --web-port 8092 --dart-define=BACKEND=supabase`.

**Edge Functions** (deploy and secrets): §8.

---

## 3. Firebase for push only (one-time, owner only)

Since D-52 Firebase does **one job: push notifications (FCM)**, on the free Spark plan. Login, data and functions are
on Supabase (§2b). No Blaze plan, Firestore, Firebase Authentication or App Check is needed.

| Firebase project | Use |
|---|---|
| **`asani-b2b17`** (the dev project, called `asani-dev` in some documents) | Development and testing |
| `asani-prod` (not created yet) | Real clinics |

For each project:
1. **Cloud Messaging** is on by default. For iPhone, upload an **APNs Auth Key** (.p8) from the Apple Developer
   account (Project settings → Cloud Messaging).
2. The `send-push` Edge Function needs a service account of the same project in its `FCM_SERVICE_ACCOUNT` secret
   (§2b; never commit it).

---

## 4. Connect the Flutter app to Firebase

Needed only when the app config must be created again: the dev **Android** config is already in the repo. iOS is not
configured yet.

Application IDs (Android) and bundle IDs (iOS): `pk.asani.patient.dev` (dev), `pk.asani.patient` (prod).

Tools, once: `npm install -g firebase-tools`, `dart pub global activate flutterfire_cli`, then `firebase login`.

```bash
cd apps/patient_app

flutterfire configure --project=asani-b2b17   --out=lib/firebase_options_dev.dart   --android-package-name=pk.asani.patient.dev   --ios-bundle-id=pk.asani.patient.dev   --android-out=android/app/src/dev/google-services.json   --platforms=android,ios
```

For prod, first add `lib/firebase_options_prod.dart` and the prod `google-services.json` to `.gitignore` (§9), then:

```bash
flutterfire configure --project=asani-prod   --out=lib/firebase_options_prod.dart   --android-package-name=pk.asani.patient   --ios-bundle-id=pk.asani.patient   --android-out=android/app/src/prod/google-services.json   --platforms=android,ios
```

If it asks to add the Google Services Gradle plugin, answer **yes**.

### Flavors
`android/app/build.gradle.kts` defines product flavors `dev` and `prod` with matching `applicationId`, and
`google-services.json` goes in `android/app/src/dev/` and `android/app/src/prod/`.
`lib/core/config/firebase_setup.dart` picks the dev or prod options.

---

## 5. Run the patient app

All commands from `apps/patient_app`.

| Mode | Command | Data and login |
|---|---|---|
| Demo (default) | `flutter run --flavor dev` | on the phone; any email, code **123456** |
| Supabase | `flutter run --flavor dev --dart-define=BACKEND=supabase` | `asani-dev`; real 6-digit email code (§2b) |

`SUPABASE_URL` and `SUPABASE_ANON_KEY` default to `asani-dev` (`lib/core/config/env.dart`). `ENV` is `dev` by default.
In demo mode, phone **300 1234567** in profile setup shows a sample family.

---

## 5b. Clinic web

All commands from `apps/clinic_web`.

```bash
flutter run -d chrome                                                   # demo data, one-click logins
flutter run -d chrome --web-port 8092 --dart-define=BACKEND=supabase    # asani-dev (dev logins: §2b)
flutter build web --release --dart-define=BACKEND=supabase              # output in build/web
```

Use port **8092** with Supabase: the invite and password-reset links are set up for it (§2b).

---

## 5c. Patient app on a real Android phone

1. On the phone, turn on **Developer options → USB debugging**, connect the cable and accept the prompt
   (Xiaomi / Redmi also needs **Install via USB**).
2. From `apps/patient_app`:
   ```bash
   flutter devices
   flutter run -d <phone id> --flavor dev --dart-define=BACKEND=supabase
   ```
3. Allow notifications. Test push on a real phone, also with the app swiped away. On Xiaomi / Redmi turn on
   **Autostart** (Account → Show me how).

To give testers an APK without a cable, build
`flutter build apk --release --flavor dev --dart-define=BACKEND=supabase`. The file is
`build/app/outputs/flutter-apk/app-dev-release.apk`; the testers' install steps are in `TESTER_INSTALL.md`.

---

## 6. Queue simulator

Acts as a clinic's receptionist on **`asani-dev` only**, through the same Postgres functions as the clinic web, so the
queue rules and patient notifications are real. It needs `supabase/.db-url.local` (§2b).

```bash
cd tools/queue-sim
node queue-sim.js status  --doctor d_ayesha
node queue-sim.js start   --doctor d_ayesha
node queue-sim.js next    --doctor d_ayesha            # add --anyway to call a patient who has not arrived
node queue-sim.js arrive  --doctor d_ayesha --number 3
node queue-sim.js end     --doctor d_ayesha
```

All commands are in `tools/queue-sim/README.md`. Apart from `status`, they change the dev data and can send real
pushes.

---

## 7. iOS

iOS builds need **macOS + Xcode**. Options:
1. **Codemagic** (or similar cloud macOS CI): build, sign and upload to TestFlight from Windows.
2. A borrowed/shared Mac for first-time signing setup.

One-time iOS steps (on a Mac or via CI):
- Apple Developer account, App ID `pk.asani.patient` with **Push Notifications** capability.
- In Xcode: enable *Push Notifications* and *Background Modes → Remote notifications*.
- APNs key uploaded to Firebase (§3).
- `cd ios && pod install`.

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
- Losing the upload key is recoverable with Play App Signing (Google can reset it), but keep a backup anyway.

---

## 8. Edge Functions and database tools

| Function | Does |
|---|---|
| `send-push` | Sends queued notifications through FCM (called by the database) |
| `admin-clinic-login` | Super Admin: create, resend, disable and enable a clinic login |

**Deploy only when Sarbuland asks, and only to `asani-dev`.** It needs a personal access token:
supabase.com/dashboard/account/tokens → Generate new token, preset Read-only plus **Edge Functions** and **Secrets**
read & write. Save it as one line in `supabase/.access-token.local` (git-ignored). Then, from the repo root:

```powershell
$env:SUPABASE_ACCESS_TOKEN = (Get-Content supabase\.access-token.local -Raw).Trim()
npx supabase@latest functions deploy send-push --remote=lgnbxxcmogbbzmuqyrgu --no-verify-jwt --use-api
npx supabase@latest functions deploy admin-clinic-login --remote=lgnbxxcmogbbzmuqyrgu --use-api
```

Secrets are set with `supabase secrets set` (docs/10 §6b): `PUSH_SECRET` and `FCM_SERVICE_ACCOUNT` (base64) for
`send-push`; `CLINIC_WEB_URL` for `admin-clinic-login`. Never commit them.

### Database test tools
From `tools/db-test`. They use `asani-dev`; the last three create their own temporary rows and delete them.

```bash
node run.js                  # pgTAP tests, rolled back
node client-smoke.js         # what the patient app does, from outside
node concurrency.js          # many bookings at once: no duplicate token numbers
node admin-login-smoke.js    # admin-clinic-login, without sending a real email
```

---

## 8b. CI (GitHub Actions)

`.github/workflows/` has one workflow per part; each runs only when its paths change:

| Workflow | Runs on changes in | Does |
|---|---|---|
| `patient_app.yml` | `apps/patient_app/**`, `packages/**`, root pubspec | analyze and test (shared packages too), dev debug APK (demo data) |
| `clinic_web.yml` | `apps/clinic_web/**`, `packages/**`, root pubspec | analyze, tests if any, web build for Supabase; Hosting deploy **disabled** |
| `supabase.yml` | `supabase/**`, `tools/db-test/**` | SQL syntax check; pgTAP tests on `asani-dev` **only if** the GitHub secret `SUPABASE_DB_URL` is set |

CI never pushes migrations or deploys.

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
**/*.local.json
supabase/.db-url.local
supabase/.access-token.local
supabase/functions/.env*
tools/admin-scripts/*.local.txt
apps/patient_app/android/app/src/prod/google-services.json
apps/patient_app/ios/Runner/prod/GoogleService-Info.plist
```
The dev `google-services.json` may be committed (it is not a secret, but keeping prod out is a good habit).
