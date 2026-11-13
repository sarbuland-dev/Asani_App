# CLAUDE.md

All agent instructions for this repository live in **AGENTS.md**. Read it fully before doing any work.

Quick map (monorepo, Dart pub workspace; details in AGENTS.md §2 and PRD-CLINIC-WEB.md §2.1):
- `apps/patient_app` (Android + iOS) · `apps/clinic_web` (Flutter Web: clinic + super admin)
- `packages/asani_core` (pure Dart shared logic) · `packages/asani_ui` (shared theme + widgets)
- `functions/`, `firestore.rules`, `firestore.indexes.json`, `firebase.json` and docs at the root
- Run `flutter pub get` once at the repo root; CI lives in `.github/workflows/`.

@AGENTS.md
