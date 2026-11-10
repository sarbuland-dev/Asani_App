# 06 — Integration

How the patient app connects to each service, and the contracts between parts of the system.

---

## 1. Packages (patient app)

```yaml
dependencies:
  flutter_riverpod: ^2.6.0          # check latest when scaffolding
  go_router: ^14.0.0
  firebase_core: any                # use versions from `flutterfire` BoM at scaffold time
  firebase_auth: any
  cloud_firestore: any
  cloud_functions: any
  firebase_messaging: any
  firebase_app_check: any
  firebase_crashlytics: any
  firebase_analytics: any
  flutter_local_notifications: ^18.0.0
  qr_flutter: ^4.1.0
  intl: ^0.19.0
  timezone: ^0.10.0
  url_launcher: ^6.3.0
  google_fonts: ^6.2.0
  uuid: ^4.5.0
  device_info_plus: ^11.0.0         # Xiaomi/MIUI help card
  connectivity_plus: ^6.1.0         # offline banner
  shared_preferences: ^2.3.0
  asani_core:
    path: ../../packages/asani_core
```
Pin exact versions when scaffolding (`flutter pub add <pkg>` then commit `pubspec.lock`). Version numbers above are indicative; the agent must check pub.dev for current stable versions.

---

## 2. Firebase initialisation (`main.dart`)

Order matters:
```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: Env.firebaseOptions);

  await FirebaseAppCheck.instance.activate(
    androidProvider: Env.isProd ? AndroidProvider.playIntegrity : AndroidProvider.debug,
    appleProvider: Env.isProd ? AppleProvider.appAttestWithDeviceCheckFallback : AppleProvider.debug,
  );

  if (Env.useEmulator) {
    final host = Env.emulatorHost;            // 10.0.2.2 on Android emulator
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    FirebaseFunctions.instanceFor(region: 'asia-south1').useFunctionsEmulator(host, 5001);
  }

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (e, s) {
    FirebaseCrashlytics.instance.recordError(e, s, fatal: true);
    return true;
  };

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(const ProviderScope(child: AsaniApp()));
}
```
Always use `FirebaseFunctions.instanceFor(region: 'asia-south1')`; the default region (`us-central1`) will fail with `not-found`.

---

## 3. Callable functions contract

Typed wrappers live in `lib/data/services/functions_service.dart`.

### `bookToken`
```jsonc
// request
{ "clinicId": "cl_alshifa", "doctorId": "doc_ayesha", "patientId": "pt_shazia",
  "date": "2026-11-07", "followUpId": null }
// response
{ "tokenId": "tk_8f2a", "number": 11 }
// errors: HttpsError with details.code in
// clinic-unavailable | doctor-unavailable | session-ended | tokens-full |
// duplicate-token (details.existingNumber) | too-many-active | rate-limited
```

### `cancelToken`
```jsonc
{ "tokenId": "tk_8f2a" }  →  { "ok": true }
// errors: not-found | permission-denied | not-cancellable
```

### `linkPatientProfiles`
```jsonc
{}  →  { "linked": 2 }
```

### `deleteAccount`
```jsonc
{ "confirm": "DELETE" }  →  { "ok": true }
```

Error mapping in the app (`core/errors/`): `FirebaseFunctionsException.details['code']` → DESIGN.md §7 messages. Network errors (`unavailable`, `deadline-exceeded`) → "No internet connection…".

---

## 4. Push notifications (FCM + local notifications)

### Message format (sent by functions)
```jsonc
{
  "token": "<fcm token>",
  "notification": { "title": "2 patients ahead of you", "body": "Token #11 · Dr. Ayesha Malik" },
  "data": { "type": "queue", "step": "ahead2", "tokenId": "tk_8f2a" },
  "android": { "priority": "high",
               "notification": { "channelId": "queue_alerts", "tag": "tk_8f2a" } },
  "apns": { "headers": { "apns-priority": "10" },
            "payload": { "aps": { "sound": "default", "thread-id": "tk_8f2a" } } }
}
```
- `tag` / `thread-id` = tokenId so newer steps **replace** older ones in the tray instead of stacking.
- Follow-ups: `data.type = "followUp"`, `followUpId`, channel `follow_ups`.

### App side (`push_service.dart`)
1. Create Android channels at startup: `queue_alerts` (Importance.high), `follow_ups` (default).
2. Ask permission via the primer (DESIGN S-17): `FirebaseMessaging.requestPermission()` (iOS + Android 13+).
3. Get token → write `users/{uid}/devices/{deviceId}`; listen to `onTokenRefresh`.
4. **Foreground:** FCM doesn't show a system notification on its own → show it with `flutter_local_notifications` (unless the user is already on that token's screen, in which case show an in-app banner).
5. **Tap handling:** `getInitialMessage()` (terminated), `onMessageOpenedApp` (background), local notification `onDidReceiveNotificationResponse` (foreground) → `router.go('/token/$tokenId')` or the pre-filled booking for follow-ups.

### Server side (`functions/src/lib/fcm.ts`)
- Send to every device of the user with `sendEach`.
- On `messaging/registration-token-not-registered` or `invalid-argument`, delete that device doc.

### Xiaomi / MIUI (Redmi) specifics
MIUI may block notifications for apps not allowed to auto-start.
- Send `priority: high` (already above).
- In Account → Notifications, show a "Xiaomi/Redmi phones" help card: enable **Autostart**, set **Battery saver → No restrictions**, allow **Notifications** for "Queue alerts".
- Detect manufacturer via `device_info_plus` to show the card only on Xiaomi/Redmi/POCO.

---

## 5. Deep links (F-11, P1)

- Clinic QR URL: `https://asani.app/c/{clinicId}` (domain pending Q-06).
- Android: App Links (`assetlinks.json` hosted on the domain, intent filter with `autoVerify`).
- iOS: Universal Links (`apple-app-site-association`, Associated Domains entitlement).
- go_router route `/c/:clinicId` → redirects to `/clinic/:clinicId` (after login if needed; keep the intended route).
- If the app is not installed, the web page shows store links (Firebase Hosting static page).

---

## 6. External apps

| Action | How |
|---|---|
| Call clinic | `url_launcher` `tel:+92...` |
| Directions | `https://www.google.com/maps/search/?api=1&query=<lat>,<lng>` (works on both platforms; opens Google Maps or the browser) |
| Privacy/Terms | In-app browser via `url_launcher` `LaunchMode.inAppBrowserView` |

---

## 7. Admin scripts and queue-sim (integration with data)

`tools/admin-scripts` (Node + Admin SDK):
- `seed-dev.js`: demo clinics, doctors, schedules (emulator or dev)
- `onboard-clinic.js clinic.json`: real clinic onboarding: clinic doc (+ `searchKeywords`), doctors, `doctorCount`
- `create-followup.js --token <id> --days 7`: test follow-ups

`tools/queue-sim` implements the **desktop contract** in ARCHITECTURE.md §10. It changes token statuses and `currentToken`/`sessionStatus` only; the `onTokenWrite` trigger keeps `activeNumbers` and notifications consistent.

Both read the target from flags: default **emulator**; `--project dev` uses `serviceAccount.dev.json`. There is deliberately **no** `--project prod` in queue-sim.

---

## 8. Future integrations (not Phase 1)

| Integration | Phase | Note |
|---|---|---|
| Clinic desktop app | 2 | Must follow ARCHITECTURE.md §10 contract |
| Thermal/A5 slip printing | 2 | Desktop app |
| SMS/WhatsApp tokens and reminders | 4 | For patients without the app |
| Payment gateway for clinic subscriptions | 3+ | Super admin |
| Cloudinary (images) | if needed | Doctor photos; not needed in Phase 1 |
