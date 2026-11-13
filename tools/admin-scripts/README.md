# Admin scripts (dev only)

Node + Firebase Admin SDK. Default target is the **emulator**; `--project dev` targets `asani-b2b17`.
There is no prod option (AGENTS.md §7).

## Setup (once)

```bash
cd tools/admin-scripts
npm install
```

For `--project dev`: Firebase console → ⚙ Project settings → **Service accounts** → **Generate new private key**.
Save the file here as `serviceAccount.dev.json`. It is git-ignored; **never commit or share it**.

## Seed demo clinics

```bash
node seed-dev.js                 # emulator
node seed-dev.js --project dev   # asani-b2b17
```

Safe to run again. Clinic IDs match the app's demo seed.

## Follow-ups (PRD F-09)

```bash
node create-followup.js --token <tokenId> --days 7 --project dev        # or --date 2026-11-20
node run-followup-reminders.js --project dev                            # the 9 AM reminders, once
node run-auto-close.js --project dev --dry-run                          # D-21: list past-day open tokens
node run-auto-close.js --project dev                                    # D-21: close them (the 3 AM job), once
```

`run-followup-reminders.js` uses the Cloud Functions code (`npm run build` in `functions/` first) and is
safe to run again: each reminder is recorded before it is sent. After Blaze the `followUpReminders`
scheduled function runs it every day at 09:00 PKT.
