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
| Demo (default) | `flutter run --flavor dev` | any email, code **123456**, all data on the phone |
| Supabase (D-52) | `flutter run --flavor dev --dart-define=BACKEND=supabase` | real 6-digit email code, data in `asani-dev` |

Supabase setup (email code settings, SMTP): docs/02-setup.md §2b. Push uses Firebase Cloud Messaging only
(`firebase_options_dev.dart`, `google-services.json`); see FIREBASE_SETUP.md for that part.

Demo mode:
- Any email works and the code is **123456**. Use phone **300 1234567** in profile setup to see a sample family, visit
  history and a follow-up.
- Today's queues move forward by themselves every 15 seconds, like a receptionist pressing "next".
  Turn this off, or move a queue by hand, under **Account → Demo tools**.
- Data is saved on the phone, so it survives restarts.

## Structure

```
lib/
├── main.dart, app.dart        bootstrap, theme, in-app queue alerts
├── core/                      theme tokens, router, formatters, shared widgets, errors
├── data/
│   ├── repositories/          repository interfaces (UI depends only on these)
│   ├── demo/                  demo backend + seed data
│   ├── supabase/              Supabase repositories (D-52)
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
