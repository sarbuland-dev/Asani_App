# Asani patient app

Flutter app for patients (Android + iOS). Screens follow the UI design and DESIGN.md.

## Run it

```bash
cd apps/patient_app
flutter pub get
flutter run --flavor dev
```

Two modes:

| Mode | Command | Login |
|---|---|---|
| Demo (default) | `flutter run --flavor dev` | code **123456**, all data on the phone |
| Firebase | `flutter run --flavor dev --dart-define=BACKEND=firebase` | real SMS / test numbers, account in Firestore |

Firebase mode needs a one-time setup: see **[FIREBASE_SETUP.md](FIREBASE_SETUP.md)**.
In both modes clinics, queues, tokens and family use demo data for now (D-11).

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

## Next on Firebase

1. Done: login (`lib/data/firebase/firebase_auth_repository.dart`), rules and indexes (repo root).
2. Next: clinics, doctors and queue days from Firestore; `bookToken` / `cancelToken` Cloud Functions.
3. Then: family profiles and follow-ups in Firestore.
4. Then: FCM + `flutter_local_notifications` for real queue alerts (channels `queue_alerts`, `follow_ups`).
