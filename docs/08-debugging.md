# 08 — Debugging

> **D-52 (2026-11-27): the backend is Supabase; the Firebase backend (Firestore, Cloud Functions, rules, emulators) was
> removed.** Parts of this file still describe the Firebase way and are kept as background only. Current sources:
> docs/10-supabase-migration.md, DATABASE.md, ARCHITECTURE.md, docs/02 §2b (setup), TESTING_CHECKLIST.md.

Where to look and how to fix the problems most likely to hit Asani.

---

## 1. Where to look first

| Symptom in | Look at |
|---|---|
| App UI / Dart exception | `flutter run` console, Flutter DevTools, Dart MCP "runtime errors" (docs/05) |
| Crash in the field | Firebase Console → Crashlytics |
| Callable error | App log of `FirebaseFunctionsException` (`code`, `message`, `details`) + Functions logs |
| Function logs | Emulator: terminal / Emulator UI → Logs. Cloud: `firebase functions:log --only bookToken` or Google Cloud Logging |
| Data looks wrong | Emulator UI → Firestore, or Firebase MCP (dev) |
| Permission denied | Rules Playground (console) or the rules tests |
| Notification not received | §4 checklist |

Logging in the app: `AppLogger.d/i/w/e`. In release builds, `w` and `e` go to Crashlytics as breadcrumbs/non-fatals. Never log phone numbers in full.

---

## 2. Authentication problems

| Error / symptom | Likely cause | Fix |
|---|---|---|
| `invalid-app-credential`, `app-not-authorized`, or OTP never arrives on Android | **SHA-1/SHA-256 missing** for the build you're running | `gradlew signingReport`, add both to Firebase → Android app; for Play builds add the **Play App Signing** SHA keys too |
| `missing-client-identifier` / reCAPTCHA page opens on Android | Play Integrity unavailable (emulator without Play services, sideloaded build) | Use a Google Play system image, or a test phone number |
| `quota-exceeded` / `too-many-requests` | SMS rate limit hit while testing | Use **test phone numbers** in dev; wait; check SMS region policy |
| `operation-not-allowed` | Phone provider not enabled / Pakistan blocked by region policy | Enable Phone; allow PK |
| `billing-not-enabled` | Project on Spark plan | Upgrade to Blaze |
| iOS: OTP flow crashes or never returns | Missing `REVERSED_CLIENT_ID` URL scheme or APNs not configured | Add URL scheme; upload APNs key; enable Push capability |
| Emulator: no SMS | Expected | Code is printed in the emulator terminal / Emulator UI |
| `linkPatientProfiles` links nothing | Phone format mismatch | Everything must be E.164 `+923XXXXXXXXX`, no spaces |

---

## 3. Firestore problems

| Error / symptom | Cause | Fix |
|---|---|---|
| `[cloud_firestore/failed-precondition] The query requires an index` | Missing composite index | Open the link in the error **or** add it to `firestore.indexes.json` and `firebase deploy --only firestore:indexes --project dev`. Always commit the index file |
| `[cloud_firestore/permission-denied]` on a query | Query doesn't include the field the rule checks | Add `where('bookedByUserId', isEqualTo: uid)` / `patientOwnerUid` / `ownerUid`. Rules are not filters |
| `permission-denied` on create/update | Payload has a field not allowed by `changedOnly`/`hasOnly`, or a validation fails (`nameLower` mismatch, birthYear range, missing `patientPhone: null`) | Compare payload with DATABASE.md; check the rules test for that case. **Never** loosen rules to fix it |
| Live screen not updating | Listening to the wrong day doc (wrong date/time zone) | Day ID must be PKT `yyyy-MM-dd` from `DateUtilsPk`, not device local time |
| "Patients ahead" wrong | `activeNumbers` stale | Check `onTokenWrite` logs; run `queue-sim status`; the trigger recomputes from tokens |
| Duplicate token numbers | Number assigned outside the transaction | Only `bookToken` may assign; check no other code writes `number`/`lastTokenNumber` |
| Data from previous test confusing results | Emulator import | Start emulators without `--import`, or delete `emulator-data/` |

---

## 4. Notifications not received (checklist)

Work top to bottom:

1. **Permission:** Settings → Apps → Asani → Notifications ON; `queue_alerts` channel ON (Android).
2. **Device registered:** `users/{uid}/devices` has a doc with a fresh `fcmToken` (Firebase MCP or Emulator UI).
3. **Trigger ran:** function logs for `onQueueDayWrite` / `onTokenWrite` show the token and step.
4. **`notified` map:** if the step already has a timestamp, it was sent before (or skipped by the jump rule). This is expected behaviour, not a bug.
5. **FCM response:** logs show `successCount`. `registration-token-not-registered` → the app must refresh and re-save the token.
6. **Foreground:** FCM shows nothing by itself → confirm `flutter_local_notifications` displays it.
7. **Xiaomi/Redmi:** Autostart ON, Battery saver "No restrictions", app not "cleaned" from recents with the lock removed. Test again with the screen locked.
8. **iOS:** APNs key uploaded to Firebase for the **right** project; Push + Background Modes capabilities; testing on a real device (simulators need extra setup); `getAPNSToken()` returns non-null before `getToken()`.
9. **Emulators:** the Functions emulator cannot deliver real pushes unless functions use real credentials. Test push end-to-end against `asani-dev`.

Send a manual test push: Firebase Console → Messaging → "Send test message" with the device's FCM token.

---

## 5. Cloud Functions problems

| Symptom | Fix |
|---|---|
| App gets `not-found` calling a function | App uses default region. Use `FirebaseFunctions.instanceFor(region: 'asia-south1')` |
| `internal` error with no detail | Function threw a non-`HttpsError`. Wrap logic and rethrow as `HttpsError`; check logs |
| `unauthenticated` though logged in | App Check token rejected (prod) → debug token not registered / Play Integrity failing |
| Trigger runs twice | Normal (at-least-once delivery). Logic must be idempotent (`notified` guard, recompute counters) |
| Transaction contention errors under load | Expected retries; if they fail, check nothing else writes the day doc in the same moment |
| Slow first booking in the morning | Cold start → set `minInstances: 1` for `bookToken` during clinic hours |
| Deploy fails on TS errors | `npm run build` locally first |

---

## 6. Flutter / build problems (Windows + Android Studio)

| Problem | Fix |
|---|---|
| Gradle / Kotlin DSL errors after adding Firebase | Check `com.google.gms.google-services` plugin in `settings.gradle.kts` and `app/build.gradle.kts`; matching versions from FlutterFire docs |
| `google-services.json` not found for flavor | Place it in `android/app/src/dev/` and `src/prod/` |
| Android emulator crashes / low RAM | Use the physical Redmi (more reliable); close other apps; lower emulator RAM |
| NDK version mismatch | Set `ndkVersion` in `app/build.gradle.kts` to the version Gradle asks for |
| `minSdk` errors from Firebase plugins | Project uses `minSdk = 26` (Android 8.0, PRD §6). Don't lower it |
| iOS pod errors (on Mac/CI) | `cd ios && pod repo update && pod install`; set iOS platform to 15.0 in `Podfile` |
| Riverpod provider rebuild loops | A provider watching something it also modifies; use `ref.read` in callbacks, `ref.watch` only in build |
| go_router redirect loop | Redirect returns a route that also triggers the redirect; make redirects return `null` when already on the target |

---

## 7. Reproducing a reported bug

1. Get device, OS, app version, build flavor and steps (bug template docs/07 §6).
2. Reproduce on the emulator stack with `seed-dev.js` + queue-sim.
3. If data-dependent, copy the relevant docs (masked) from dev via Firebase MCP into the emulator.
4. Write a **failing test first** (unit/rules/function), then fix.
5. Note the cause in the PR.

---

## 8. Useful commands

```bash
flutter clean && flutter pub get
flutter run -v                                      # verbose
flutter logs                                        # device logs
adb logcat | findstr /i "firebase fcm flutter"      # Windows
firebase emulators:start --inspect-functions        # attach debugger to functions
firebase functions:log --only bookToken --project dev
node tools/queue-sim/queue-sim.js status --doctor <id>
```
