# Asani Clinic Web

Flutter Web app for clinic staff (Queue Board, check-in, walk-ins, printing,
follow-ups, doctors, staff, settings, billing) **and** the Super Admin panel.
Spec: [`PRD-CLINIC-WEB.md`](../../PRD-CLINIC-WEB.md). Same brand and widgets as
the patient app (teal `#0F766E`, Inter), laid out for desktop (≥ 1280 px).

## Status

Two backends behind one `ClinicRepository` interface (`lib/data/`):

- **Demo** (default): in-memory data seeded around "now" in Pakistan time. A reload starts fresh.
- **Firebase** (`--dart-define=BACKEND=firebase`): the real backend, same project as the patient app.
  Firebase Auth email + password, roles from custom claims, Firestore listeners for reads, and every
  write through the clinic/admin Cloud Functions (`functions/src/clinic`, `functions/src/admin`).
  An app booking shows on the Queue Board within seconds; Next / Arrived / Skip move the patient's
  queue and send the 3-2-1 / Your-turn notifications.

## Run

```bash
cd apps/clinic_web
flutter pub get
flutter run -d chrome                                                    # demo
flutter run -d chrome --dart-define=BACKEND=firebase --dart-define=USE_FUNCTIONS_EMULATOR=true
flutter run -d chrome --dart-define=BACKEND=firebase --dart-define=USE_EMULATOR=true   # all emulators
```

Release build: `flutter build web --release [--dart-define=BACKEND=firebase]` → `build/web`.

## Firebase setup (once)

1. **Console → Authentication → Sign-in method → Email/Password: Enable** (asani-b2b17).
   Optional: Templates → Password reset → subject "Set your Asani password".
2. Functions: `cd functions && npm run build`, then run them on the emulator
   (`npm run serve:dev`) until the project is on Blaze.
3. Rules + indexes must include the clinic-web parts (`firestore.rules`, `firestore.indexes.json`):
   on the dev project Sarbuland deploys them (`firebase deploy --only firestore --project dev`).
4. Logins (tools/admin-scripts, add `--project dev` for the dev project):
   ```bash
   node create-super-admin.js --email <your email> --name "Sarbuland"
   node create-clinic-login.js --clinic c_alshifa --email <clinic email> --owner "Dr. Tariq"
   node backfill-clinic-ids.js            # patients who booked before the clinic web existed
   ```
   Each prints a one-time link to set the password. New clinics come from the New clinic wizard.

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
- Q-W07: the clinic can fix name/age/gender typos (logged).
- Q-W11 (manager PIN for sensitive pages) is not built; still open.
- "New doctors" seen-state is kept per browser session in demo mode.
- Q-W09: QR/link domain is a placeholder in `lib/core/config/links.dart`.
- `asani_core` is a path dependency (like `patient_app`), not yet a pub workspace (PRD §2.1).
