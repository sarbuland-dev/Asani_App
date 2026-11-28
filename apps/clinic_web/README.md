# Asani Clinic Web

Flutter Web app for clinic staff (Queue Board, check-in, walk-ins, printing, follow-ups, doctors, settings, billing)
**and** the Super Admin panel. Spec: [`PRD-CLINIC-WEB.md`](../../PRD-CLINIC-WEB.md). It uses the shared theme in
`packages/asani_ui` (the web keeps the "Monochrome green" colours, `WebColors`, D-44) and is laid out for desktop
(1280 px and wider).

## Status

Two backends behind one `ClinicRepository` interface (`lib/data/`):

- **Demo** (default): in-memory data seeded around "now" in Pakistan time. A reload starts fresh.
- **Supabase** (`--dart-define=BACKEND=supabase`, D-52): the `asani-dev` project, same as the patient app. Email +
  password login, roles from `app_metadata`, Realtime for live data, and every write through Postgres functions and
  the `admin-clinic-login` Edge Function. An app booking shows on the Queue Board; Next / Skip move the patient's
  queue and send the notifications.

## Run

```bash
cd apps/clinic_web
flutter run -d chrome                                                   # demo
flutter run -d chrome --web-port 8092 --dart-define=BACKEND=supabase    # asani-dev
```

Release build: `flutter build web --release --dart-define=BACKEND=supabase` (output in `build/web`).

Supabase setup (auth settings, redirect URL on port 8092, dev logins with `tools/db-test/create-login.js`):
[`docs/02-setup.md`](../../docs/02-setup.md) §2b. New clinics are made with the Super Admin's New clinic wizard.

## Demo accounts (demo backend only)

One login per clinic (PRD D-18): the clinic's email, shared by the manager and
the receptionist. No receptionist or doctor accounts. Password for all: `asani123`
(demo only). The login page has one-click buttons.

| Login | Email |
|---|---|
| Super Admin | admin@asani.app |
| Al-Shifa Clinic | clinic@alshifa.pk |
| DHA Family Clinic | clinic@dhafamily.pk |
| Rehman Clinic (suspended, read-only) | clinic@rehmanclinic.pk |

`clinic@cliftoncare.pk` is *invited* (cannot log in yet).

## Roles (PRD v0.4)

- **Clinic login**: queue, check-in, walk-ins, patients, follow-ups, summary + export,
  **adds/edits/deactivates its own doctors** and leave (D-19), clinic settings, billing,
  change password.
- **Super Admin**: registers clinics and their login (wizard has no doctors step),
  disables/enables a clinic login, **views** doctors with a "New doctors" card on the
  dashboard, payments, defaulters, activity, settings.

## Structure

```
lib/
  core/        widgets, router, print/download/QR helpers (the theme is in packages/asani_ui)
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
- Q-W07: the clinic can fix name/age/gender typos (logged).
- Q-W11 (manager PIN for sensitive pages) is not built; still open.
- "New doctors" seen-state is kept per browser session in demo mode.
- Q-W09: QR/link domain is a placeholder in `lib/core/config/links.dart`.
- `asani_core` and `asani_ui` come from the Dart pub workspace at the repo root (PRD §2.1).
