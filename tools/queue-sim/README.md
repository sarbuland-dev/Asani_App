# queue-sim (dev only)

Acts as a clinic's receptionist on the **Supabase dev database** (`asani-dev`, D-52). Every command calls the same
Postgres functions as the clinic web (`queue_action`, `clinic_create_walk_in`), signed in as the doctor's clinic, so the
rules, token history and patient notifications (3/2/1, Your turn, skip notice) are exactly the real ones.
It refuses any database other than asani-dev (AGENTS.md §7).

Database URL: `supabase/.db-url.local` (git-ignored, docs/02 §2b) or env `SUPABASE_DB_URL`.

## Setup (once)

```bash
cd tools/queue-sim
npm install
```

## Commands (date = today in Asia/Karachi unless `--date yyyy-MM-dd`)

```bash
node queue-sim.js status  --doctor d_ayesha
node queue-sim.js start   --doctor d_ayesha               # session running
node queue-sim.js next    --doctor d_ayesha               # D-24 order; stops at a Booked (not arrived) patient
node queue-sim.js next    --doctor d_ayesha --anyway      # … and calls them anyway
node queue-sim.js undo    --doctor d_ayesha               # within 30 s of Next (D-38)
node queue-sim.js arrive  --doctor d_ayesha --number 3    # also: skip, hold, back, cancel, noshow, callnow
node queue-sim.js walkin  --doctor d_ayesha --name "Ali Raza" --phone 03001234567 --age 40 --gender male
node queue-sim.js pause   --doctor d_ayesha
node queue-sim.js end     --doctor d_ayesha               # remaining Booked → No-show
node queue-sim.js auto    --doctor d_ayesha --every 30    # start, then Next every 30 s
```

`queue-sim-firebase.js` is the old Firestore version (kept until the Firebase code is removed, docs/10 phase 8).
