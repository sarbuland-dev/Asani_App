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
