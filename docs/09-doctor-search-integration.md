# 09 — Doctor search + same-doctor linking: integration tasks

> **2026-11-21:** §1–§4 (functions, rules, indexes, migration) and the Firebase data code are **done** (step 1).
> **2026-11-22:** step 2 done too (§5 location, required clinic location, "Also sits at" on the clinic page).
> Material Symbols icons are still not added. Migration ran on dev on 2026-11-21.

PRD D-31, D-32, D-33 (2026-11-19). **Roles:** UI (patient app screens, clinic web screens, `asani_ui`) is done by
Claude. Everything below is for the **integration side**. Tick items here as they land; the UI is built against
the names in §6, so keep them or tell the UI side.

Specs: PRD.md F-13, F-14 · DESIGN.md S-06b, S-18 · DATABASE.md §5, §8b, §9 · PRD-CLINIC-WEB.md C-11, C-13, A-04,
A-09, BW-11, BW-12 · tests in docs/07 (§2, QA-2b, QA-2c).

---

## 1. Cloud Functions (`functions/src`)

- [x] **`saveDoctor`** (clinic):
  - `speciality` must be **one** key of the fixed list (share the list with `asani_core`, see §6); reject free text.
  - Optional `pmdcNumber`: normalise (trim, upper case, no spaces), loose check `^\d{3,7}(-[A-Z]{1,2})?$`;
    `invalid-argument` "Not a valid PMDC number" otherwise. Field **absent = keep** the saved number (the clinic
    can't read it back, so the form sends it only when typed).
  - Write `pmdcNumber` **only** to `doctors/{id}/private/admin` (`{pmdcNumber, clinicId, updatedAt}`), never to
    the public doctor document. Return `hasPmdc: bool`, never the number.
  - Copy `city` from the clinic; set `nameKey` (lower case, strip `dr`/`dr.`/`doctor`, punctuation, extra spaces);
    clear `specialityFlagged`.
  - **Suggestion builder** after save (never blocks the save, never links):
    - strong: collection-group query on `private` (doc `admin`) with the same `pmdcNumber`, other clinic, same city;
    - weak: `doctors` with the same `nameKey` + `speciality`, other clinic, same city;
    - pair id = sorted doctor IDs joined by `_`; create `open`, or upgrade `weak` → `strong`;
    - skip pairs whose document is `notSame`, `unlinked` or `linked`.
- [x] **`adminLinkDoctors({pairId})`** (super admin, transaction): both records get one `doctorGroupId` (reuse an
  existing group of either record; new ID otherwise); pair → `linked`, `decidedAt`, `decidedBy`; activity log
  `doctorLinked`. Second call on a decided pair = no-op.
- [x] **`adminMarkNotSame({pairId})`** (super admin): pair → `notSame`; activity log `doctorNotSame`.
- [x] **`adminUnlinkDoctor({doctorId})`** (super admin, transaction): clear its `doctorGroupId`; if one record is
  left in the group, clear it too; every pair between it and the group → `unlinked` (never re-suggested, D-33);
  activity log `doctorUnlinked`.
- [x] **Doctor list for the clinic web** (whatever the web reads today) gets `hasPmdc`, and for the super admin the
  real number (read from `private/admin`).
- [x] **`adminCreateClinic`** / **`updateClinicSettings`**: `location` `{lat, lng}` **required** and in range
  (Pakistan bounds are enough); when a clinic's `city` changes, update `city` on its doctors.
- [x] Unit tests: docs/07 §2 "Doctor linking functions".

## 2. Firestore rules (`firestore.rules`) + rules tests

- [x] `doctors/{id}/private/{doc}`: read **only** `superAdmin`; no client writes. Clinic logins can't read it,
  even for their own doctor.
- [x] `doctorLinkSuggestions/{id}`: read only `superAdmin`; no client writes.
- [x] `doctors`: clients still can't write; `doctorGroupId`, `city`, `nameKey`, `specialityFlagged` are
  function-only.
- [x] Rules tests for each (allow + deny), docs/07 §2 "Rules".

## 3. Indexes (`firestore.indexes.json`)

- [x] `doctors`: `city` ASC, `speciality` ASC, `active` ASC (Doctors tab).
- [x] `doctors`: `doctorGroupId` ASC, `active` ASC ("Also sits at").
- [x] `doctors`: `nameKey` ASC, `speciality` ASC (weak match).
- [x] Collection group `private`: field override `pmdcNumber` ASC with **collection-group** scope (strong match).
- [x] `doctorLinkSuggestions`: `status` ASC, `createdAt` DESC (Super Admin list).

## 4. Migration (`tools/admin-scripts`, dev first, `--dry-run` like `run-auto-close.js`)

- [x] `migrate-doctor-search.js`:
  - map free-text `speciality` → key (table in the script; e.g. "General Physician"/"GP"/"Family Physician" →
    `generalPhysician`, "Cardiologist" → `heart`, "Paediatrician"/"Child Specialist" → `child`, …);
    unknown → `other` + `specialityFlagged: true`; print the unknown list;
  - backfill `city` and `nameKey`;
  - list clinics with no `location` (no write; the Super Admin fills them in);
  - run the suggestion builder once over all doctors.
- [x] Never against `asani-prod` without Sarbuland's go-ahead (AGENTS.md §7).

## 5. Native + dependencies (patient app)

- [x] Add **`geolocator`** (its Android/iOS/web parts; see REMAINING_WORK §9) to `apps/patient_app/pubspec.yaml` (approved, D-33).
- [x] Android `AndroidManifest.xml`: `ACCESS_COARSE_LOCATION` + `ACCESS_FINE_LOCATION` (foreground only, no
  background location).
- [x] iOS `Info.plist`: `NSLocationWhenInUseUsageDescription` = **"Asani uses your location to show clinics and
  doctors near you."**
- [ ] Add the **Material Symbols** icon package (approved) — to `packages/asani_ui` so both apps share it.
- [x] Clinic web: a map picker or "paste Google Maps link / lat, lng" parser for the location field (no new paid
  API without asking).

## 6. App data layer the UI needs (patient app + clinic web)

**Done on 2026-11-19 for the demo backend** (asani_core helpers, demo data, patient `doctorCardsProvider`,
`LocationService` with a fixed demo spot, clinic web demo repository + `linkSuggestionsProvider`). Still open for
Firebase: the `TODO(integration)` stubs in `apps/clinic_web/lib/data/firebase_clinic_repository.dart`
(`hasPmdc`, `linkSuggestions`), reading `doctorGroupId` / `specialityFlagged` in the clinic web's Firestore doctor
parser, and a real `LocationService` with geolocator in `apps/patient_app/lib/data/location_service.dart`.

The UI reads these; names are the contract. **Pure helpers** go in `asani_core`, providers/repositories in each app.

`asani_core` (pure Dart, with tests):
- [x] `enum Speciality` with `key`, `label` ("Heart"), `term` ("Cardiologist"), `display`
  ("Heart (Cardiologist)"), `iconName` (Material Symbols name); `Speciality.fromKey(String?)` → `other` for unknown.
- [x] `double distanceKm(GeoPoint a, GeoPoint b)` (haversine).
- [x] `List<DoctorGroupCard> buildDoctorCards({doctors, clinics, availability, userLocation, userArea})`: groups
  by `doctorGroupId` (same city only), picks the nearest clinic as main, sorts bookable-today nearest first →
  no-location clinics → not-available-today; without `userLocation`, same `userArea` first then A–Z by area.
- [x] `normalisePmdc(String)`, `isValidPmdc(String)`, `doctorNameKey(String)`.
- [x] `Doctor` model: `speciality` stays a string key, plus `city`, `doctorGroupId`, `specialityFlagged`.

Patient app (`lib/data/**`, demo backend **and** Firebase):
- [x] `doctorsBySpecialityProvider((city, speciality))` → active doctors at visible clinics in that city.
- [x] `doctorGroupProvider(groupId)` → active doctors in the group (for "Also sits at" on the clinic page).
- [x] `userLocationProvider` → `AsyncValue<GeoPoint?>` + `requestLocationPermission()` returning
  `granted / denied / deniedForever`; `openLocationSettings()`; `locationPrimerShown` stored on the device
  (like `primerShown`).
- [x] Demo backend: give demo clinics a `location`, demo doctors fixed speciality keys, one demo doctor linked at
  two Lahore clinics, so the UI can be previewed without Firebase.

Clinic web (`lib/data/**`):
- [x] `saveDoctor` input gets `speciality` (key) and `pmdcNumber?`; doctor rows get `hasPmdc`,
  `specialityFlagged`, `doctorGroupId`.
- [x] Super Admin: `linkSuggestionsProvider(status)`, `linkedGroupsProvider`, and `link` / `notSame` / `unlink`
  actions (callables above); suggestion rows include both doctors, clinics, timings and PMDC numbers.
- [x] Clinic settings / wizard: `location` in the save calls.
