# Context for Claude (and other agents)

A short orientation for a fresh session. **Read AGENTS.md first** (rules), then this, then the files it points to.

## Where things stand (2026-11-26)

- **Backend = Supabase** (PRD D-52, docs/10-supabase-migration.md). Phases 1–7 done; phase 8 (clean-up) in progress.
  Firebase is kept **only for push** (FCM, free Spark plan). Old Firebase code (`functions/`, `firestore.*`,
  `lib/data/firebase/`, `queue-sim-firebase.js`) is still in the repo until Sarbuland OKs its removal.
- **Patient login** = email + 6-digit email code; phone required in profile setup, **not verified**, one phone = one
  app account. **No auto-linking** of walk-ins by phone: reception uses "Link to app account".
- **Clinic web** = email + password per clinic (D-18); Super Admin in the same web app; manager PIN (D-41).
- Builds: `--dart-define=BACKEND=supabase` (both apps). Without it: in-memory demo data.
- Phase: **functionality first** (from 2026-11-21): basic UI is fine; the full UI follows the Artifacts screens board.

## Map

| Need | Look at |
|---|---|
| Rules for agents | AGENTS.md |
| What a feature does / decisions D-01…D-52 | PRD.md (§9), PRD-CLINIC-WEB.md |
| Tables, RLS, functions | DATABASE.md, `supabase/migrations/` |
| Function list + error codes | docs/10-supabase-migration.md §6b |
| How it fits together | ARCHITECTURE.md |
| Setup (Supabase, CLI, secrets, dashboard steps) | docs/02-setup.md §2b |
| Tests | TESTING_CHECKLIST.md, `supabase/tests/database/`, `tools/db-test/` |
| Open work | REMAINING_WORK.md (§13 = the Supabase move) |
| Look of the screens | DESIGN.md + the screens board (Artifacts) |

## Working rules that bite

- Never edit a pushed migration: add a new one, update DATABASE.md, add a pgTAP test.
- Postgres errors: message = code, hint = text, detail = JSON. Apps map the code.
- Realtime filters on uuid columns and `id` never fire: stream on `clinic_id` / `date` / etc. or unfiltered (RLS).
- Pushes: write `notify_user(...)` in the same transaction as the state change; never call FCM from SQL directly.
- Secrets live only in git-ignored files (`supabase/.db-url.local`, `supabase/.access-token.local`,
  `tools/admin-scripts/*.local.txt`, `serviceAccount*.json`), Supabase Vault or Edge Function secrets. Never print them.
- The CLI asks for consent before changing the hosted project; deploy / push only when Sarbuland asked in that session.
- Stage only your own files when committing (other sessions may have uncommitted work in the tree).
- Chat with Sarbuland in English (short Roman Urdu only when asked); code, comments and docs in English.
