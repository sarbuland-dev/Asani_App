# Asani Clinic Web

Flutter Web app for clinic staff (Queue Board, check-in, walk-ins, printing,
follow-ups, doctors, staff, settings, billing) **and** the Super Admin panel.
Spec: [`PRD-CLINIC-WEB.md`](../../PRD-CLINIC-WEB.md). Same brand and widgets as
the patient app (teal `#0F766E`, Inter), laid out for desktop (≥ 1280 px).

## Status

- **Demo backend only.** All data lives in memory (`lib/data/demo_clinic_repository.dart`),
  seeded around "now" in Pakistan time. A page reload starts fresh. Every ~50 s a
  new app booking arrives for a running doctor, so the queue feels live.
- Firebase (email/password auth, custom-claim roles, `queueAction` & co. callables,
  rules) is **not connected yet**. It plugs in by overriding `repositoryProvider`
  in `lib/main.dart` with a Firebase implementation of `ClinicRepository`.

## Run

```bash
cd apps/clinic_web
flutter pub get
flutter run -d chrome
```

Release build: `flutter build web --release` → `build/web`.

## Demo accounts

Password for all: `asani123` (demo only). The login page has one-click buttons.

| Role | Email |
|---|---|
| Super Admin | admin@asani.app |
| Clinic Admin (Al-Shifa) | clinic@alshifa.pk |
| Receptionist (Al-Shifa) | reception@alshifa.pk |
| Doctor (Dr. Ayesha, letter A) | ayesha@alshifa.pk |

`evening@alshifa.pk` is *invited* (cannot log in yet) and `kiran@alshifa.pk` is *disabled*.

## Structure

```
lib/
  core/        theme (copied from patient app), widgets, router, print/download/QR helpers
  data/        models.dart, clinic_repository.dart (interface), demo_clinic_repository.dart, providers.dart
  features/
    auth/      W-01 login
    shell/     sidebar + top bar (W-03), grace/suspended/offline banners
    queue/     W-10 Queue Board, W-11 token panel, W-12 check-in, W-13 walk-in, actions, slip
    patients/  W-14 search + profile
    followups/ W-15 · summary/ W-16 + export · doctors/ W-17 · staff/ W-18
    settings/  W-19 + QR standee · billing/ W-20 · help/ W-21 · print/ W-22 templates
    admin/     A-10..A-17 (dashboard, clinics, detail, wizard, payments, defaulters, activity, settings)
```

## Keyboard (Queue Board)

`/` check in by code · `W` walk-in · `N` next (selected doctor) · `Esc` close dialog.

## Printing

Clinic form uses the browser print (Thermal 80 mm or A5, set in Clinic settings).
To skip the print dialog, start Chrome with `--kiosk-printing` (guide on the Help page).

## Decisions taken from the PRD drafts (still open there)

- Q-W03: Next calls the lowest **Arrived** token first, then the lowest **Booked**.
- Q-W05: reminder at +7 days, suspension at +15 days (editable in Admin settings).
- Q-W07: staff can fix name/age/gender typos (logged).
- Q-W09: QR/link domain is a placeholder in `lib/core/config/links.dart`.
- `asani_core` is a path dependency (like `patient_app`), not yet a pub workspace (PRD §2.1).
