# 06 — Integration

How the apps connect to each service, and the contracts between the parts (Supabase backend, D-52).

---

## 1. Packages

Patient app (`apps/patient_app/pubspec.yaml`, versions pinned in the root `pubspec.lock`):
- `supabase_flutter`: login, database reads, `rpc`, Realtime.
- `firebase_core` + `firebase_messaging`: **push only** (FCM). No Firebase Auth / Firestore / Functions / App Check.
- `flutter_local_notifications`: channels and foreground alerts; `connectivity_plus`: offline banner;
  `geolocator_*` platform parts: nearest doctors (D-31, D-33); `flutter_riverpod`, `go_router`, `shared_preferences`,
  `url_launcher`, `share_plus`, `flutter_svg`, `google_fonts` (Inter bundled), `asani_core`, `asani_ui`.

Clinic web: `supabase_flutter`, `flutter_riverpod`, `go_router`, `connectivity_plus`, `web`, `qr`, `asani_core`,
`asani_ui`. No Firebase at all.

---

## 2. Start-up

Patient app (`lib/main.dart`, `--dart-define=BACKEND=supabase`):
1. `Supabase.initialize(url, publishableKey)` (values in `Env`, defaults = asani-dev).
2. `FirebaseSetup.initForPushOnly()` → `PushService(SupabasePushAccount())` (if it fails, the app runs without push).
3. Repositories: `SupabaseAuthRepository`, `SupabaseTokenRepository`, `SupabaseClinicRepository`, queue, patients,
   follow-ups, notifications. The phone saves its FCM token in `devices` after sign-in.
Without `BACKEND=supabase` the app runs on the in-memory demo backend.

Clinic web (`lib/main.dart`): reads `type=invite|recovery` from the URL fragment, then
`Supabase.initialize(…, authFlowType: implicit)` and `SupabaseClinicRepository.create(linkType)`.

---

## 3. Backend contract

- **Reads:** `supabase.from(table).select()` or `.stream(primaryKey: …)`; RLS decides the rows (DATABASE.md §1).
  Realtime filters on uuid columns and on `id` never fire: filter on `clinic_id`, `doctor_id`, `date`, `city`, `month`,
  `active`, or stream unfiltered.
- **Writes:** `supabase.rpc('<function>', params: {'p_…': …})`. The full list with inputs, outputs and error codes is
  in **docs/10 §6b**. Examples:

```jsonc
// book_token
{ "p_clinic_id": "c_alshifa", "p_doctor_id": "d_ayesha", "p_patient_id": "…", "p_date": "2026-11-27" }
→ { "tokenId": "…", "number": 11 }

// cancel_token
{ "p_token_id": "…" } → { "ok": true }

// create_profile (first login)
{ "p_name": "Ali Khan", "p_age": 30, "p_gender": "male", "p_phone": "+923001234567" } → { "selfPatientId": "…", "created": true }
```

- **Errors:** `PostgrestException.message` = the code (`tokens-full`, `duplicate-token`, `phone-taken`, `not-arrived`,
  `pin-required`, …), `hint` = text to show, `details` = JSON extras (`duplicate-token`: `{name, label}`;
  `not-arrived`: `{tokenId, label, name}`). Network errors → the app's offline / "No internet" message.
- **PIN functions** return `{ok: false, code, message}` instead of raising (so a wrong try is saved).
- **Edge Function** `admin-clinic-login` (Super Admin): `{action: "create", clinic}` / `{action: "resend" |
  "disable" | "enable", clinicId}` → `{clinicId, email}` or `{error, message}`.

---

## 4. Push notifications (FCM)

### How a push is made
The database writes the inbox row + a `push_outbox` row in the same transaction as the queue change → `pg_net` calls the
`send-push` Edge Function → FCM HTTP v1 to every device of the account → done / retry / dead token deleted
(ARCHITECTURE.md §3.4).

### Message sent by `send-push`
```jsonc
{
  "message": {
    "token": "<fcm token>",
    "notification": { "title": "2 patients ahead of you", "body": "Token A-11 · Dr. Ayesha Malik" },
    "data": { "type": "queue", "step": "ahead2", "tokenId": "…", "route": "/token/…" },
    "android": { "priority": "HIGH", "notification": { "channel_id": "queue_alerts", "tag": "<tokenId>" } },
    "apns": { "payload": { "aps": { "sound": "default" } } }
  }
}
```
- `tag` = token id, so a newer step replaces the older one in the tray.
- Follow-ups: `data.type = "followUp"`, `followUpId`, channel `follow_ups`. Cancel / skip: `type` `cancel` / `skip`.

### App side (`lib/core/push/push_service.dart`)
1. Android channels at start: `queue_alerts` (high), `follow_ups` (default).
2. Permission through the primer (S-17) → the system popup; "Open settings" when denied.
3. FCM token → `devices` (`SupabasePushAccount`), again on token refresh and on every sign-in.
4. Foreground pushes → in-app alert; taps (`getInitialMessage`, `onMessageOpenedApp`) → `/token/{id}` or the
   pre-filled booking route. Only routes starting with `/token/` or `/book/` are opened.

### Xiaomi / Redmi / POCO (MIUI)
High priority (above) + the Account "Autostart" guide, shown only on those phones (`device_info`).

---

## 5. Deep links (F-11, later)

Clinic QR URL `https://asani.app/c/{clinicId}` (domain pending Q-06): Android App Links, iOS Universal Links, go_router
`/c/:clinicId` → clinic page. Not built yet.

## 6. External apps

| Action | How |
|---|---|
| Call clinic | `url_launcher` `tel:` |
| Directions | `https://www.google.com/maps/search/?api=1&query=<lat>,<lng>` |
| Privacy / Terms | in-app browser view |
| Share slip | `share_plus` |

## 7. Dev tools

| Tool | What |
|---|---|
| `tools/queue-sim` | Acts as a clinic on asani-dev through `queue_action` / `clinic_create_walk_in` |
| `tools/db-test/run.js` | pgTAP tests (rolled back) |
| `tools/db-test/concurrency.js` | 20 bookings at the same moment |
| `tools/db-test/client-smoke.js` | the patient app's calls through the public API |
| `tools/db-test/admin-login-smoke.js` | `admin-clinic-login` checks without real email |
| `tools/db-test/create-login.js` | dev Super Admin / clinic logins without email |

All refuse or never touch anything but asani-dev; database URL from `supabase/.db-url.local`.

## 8. Future integrations

| Integration | Note |
|---|---|
| SMS / WhatsApp reminders | for patients without the app |
| Payment proof upload | Supabase Storage (free tier) |
| Defaulter reminder email | Brevo / an Edge Function |
| Analytics / crash reporting | to choose (Crashlytics would need Firebase back for that part) |
