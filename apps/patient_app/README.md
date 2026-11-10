# Asani patient app

Flutter app for patients (Android + iOS). Screens follow the UI design and DESIGN.md.

## Run it

```bash
cd apps/patient_app
flutter pub get
flutter run
```

The app currently runs on a **demo backend** (`lib/data/demo/`, decision D-11). No Firebase setup is needed yet.

- Login: any Pakistani mobile number (`3XX XXXXXXX`). The OTP is **123456**.
- Use **300 1234567** to see a sample family, visit history and a follow-up.
- Today's queues move forward by themselves every 15 seconds, like a receptionist pressing "next".
  Turn this off, or move a queue by hand, under **Account → Demo tools**.
- Queue alerts (3, 2, 1 ahead and "Your turn now") show inside the app. Real push notifications arrive with FCM.
- Data is saved on the phone, so it survives restarts.

## Structure

```
lib/
├── main.dart, app.dart        bootstrap, theme, in-app queue alerts
├── core/                      theme tokens, router, formatters, shared widgets, errors
├── data/
│   ├── repositories/          repository interfaces (UI depends only on these)
│   ├── demo/                  demo backend + seed data (replace with Firebase)
│   └── providers.dart         Riverpod providers
└── features/                  auth, home, search, clinic, booking, token, tokens, family, account, notifications
```

Shared models and rules (token status, availability, "patients ahead", notification steps) live in
`packages/asani_core`, with unit tests.

## Checks

```bash
flutter analyze
flutter test
cd ../../packages/asani_core && dart test
```

## Next: connect Firebase

1. Create `asani-dev` (Blaze, Firestore in `asia-south1`) and run `flutterfire configure`.
2. Implement the repository interfaces in `lib/data/repositories/` with Firestore + Cloud Functions.
3. Swap `DemoBackend` for the Firebase implementation in `main.dart` (`backendProvider`).
4. Add FCM + `flutter_local_notifications` for real queue alerts (channels `queue_alerts`, `follow_ups`).
