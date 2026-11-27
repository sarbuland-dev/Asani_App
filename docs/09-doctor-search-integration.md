# 09 — Doctor search + same-doctor linking: integration status

PRD D-31, D-32, D-33 (2026-11-19). Specs: PRD.md F-13, F-14 · DESIGN.md S-06b, S-18 · DATABASE.md §4 ·
PRD-CLINIC-WEB.md C-11, C-13, A-04, A-09, BW-11, BW-12 · tests in docs/07.
First built on Firebase (2026-11-21/22); moved to Supabase with D-52 (2026-11-26). Everything below is **done** unless
marked open.

---

## 1. Backend (Supabase)

| Piece | Where |
|---|---|
| Fixed speciality list (17 keys), check on `doctors.speciality` | `supabase/migrations/20261124000100_schema.sql` |
| `save_doctor`: speciality key only; optional PMDC (normalised, `^\d{3,7}(-[A-Z]{1,2})?$`), stored only in `doctor_private`; `has_pmdc` on the doctor; copies `city`, sets `name_key`, clears `speciality_flagged`; then builds suggestions | `20261126000200_clinic_doctors_pin.sql` |
| Suggestion builder: strong = same PMDC, weak = same name key + speciality; other clinic, same city; pair id = sorted ids joined by `_`; creates `open` or upgrades weak → strong; never touches decided pairs; never links; never fails the save | same file (`private.build_suggestions`) |
| `admin_link_doctors(pair)`: one `doctor_group_id` (joins / merges groups), pair → `linked` | `20261126000300_admin_accounts.sql` |
| `admin_mark_not_same(pair)` → `notSame`; `admin_unlink_doctor(doctor)` → group cleared (a group of one too), its linked pairs → `unlinked` (never suggested again) | same file |
| Activity log for link / not the same / unlink | same file |
| Clinic location required (Pakistan box) in `update_clinic_settings` and new clinics | `…000200_clinic_doctors_pin.sql`, `…000300_admin_accounts.sql` |
| RLS: `doctor_private` and `doctor_link_suggestions` Super Admin only; clinics can't read PMDC back | `20261124000200_security.sql` |
| Indexes: (city, speciality, active), (group, active), (name key, speciality), PMDC, suggestions (status, created) | schema migration |
| Tests | `01_rls.test.sql`, `05_clinic_admin.test.sql` (speciality, PMDC, weak suggestion, link, unlink) |

The seed (`supabase/seed.sql`) has fixed speciality keys, clinic locations (one clinic without, on purpose) and
Dr. Ayesha linked at Al-Shifa and DHA.

## 2. Patient app

- `asani_core`: `Speciality` enum, `distanceKm`, `buildDoctorCards` (groups by `doctorGroupId`, nearest first,
  no-location clinics last, not-available-today greyed at the end), PMDC helpers, `Doctor.doctorGroupId` /
  `specialityFlagged`; unit tests.
- `doctorCardsProvider`, `specialityCountsProvider`, `alsoSitsAtProvider`; data from `SupabaseClinicRepository`
  (`watchDoctorsByClinic`, `watchClinics`).
- Location: `DeviceLocationService` (geolocator Android / iOS / web parts), primer sheet once per phone, "Turn on" note;
  Android permissions + iOS `NSLocationWhenInUseUsageDescription`.
- Search by doctor screen (D-49), "Also sits at" on the clinic page.

## 3. Clinic web

- Doctor form: speciality dropdown (fixed list), PMDC field ("on file · Change" from `has_pmdc`), flagged hint.
- Clinic settings + New clinic wizard: required map location (paste a Google Maps link or "lat, lng").
- Super Admin "Same doctor" (A-09): suggestions with both doctors, clinics and PMDC numbers; Link / Not the same /
  Unlink (`SupabaseClinicRepository.linkSuggestions`, `linkDoctors`, `markNotSame`, `unlinkDoctor`).

## 4. Open

- [ ] **Material Symbols** icon package (approved) in `packages/asani_ui`, so both apps share the speciality icons
      (today: SVG icons from the screens board in the patient app).
- [ ] Real clinics without a location must add it before their doctors show a distance.
