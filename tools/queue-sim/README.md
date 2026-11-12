# queue-sim (dev only)

Acts as the clinic receptionist until the desktop app exists. It follows the desktop
contract in ARCHITECTURE.md §10 and nothing more. Default target is the **emulator**;
`--project dev` targets `asani-b2b17`. There is no prod option (AGENTS.md §7).

`--project dev` uses `serviceAccount.dev.json` from this folder or from `tools/admin-scripts/`
(git-ignored, never commit it).

## Setup (once)

```bash
cd tools/queue-sim
npm install
```

## Commands (date = today in Asia/Karachi unless `--date yyyy-MM-dd`)

```bash
node queue-sim.js status --doctor d_ayesha --project dev
node queue-sim.js start  --doctor d_ayesha --project dev    # session running
node queue-sim.js next   --doctor d_ayesha --project dev    # called → completed, next → called
node queue-sim.js arrive --doctor d_ayesha --number 3 --project dev
node queue-sim.js skip   --doctor d_ayesha --number 3 --project dev
node queue-sim.js hold   --doctor d_ayesha --number 3 --project dev
node queue-sim.js pause  --doctor d_ayesha --project dev
node queue-sim.js end    --doctor d_ayesha --project dev    # remaining booked → noShow
node queue-sim.js auto   --doctor d_ayesha --every 30 --project dev   # "next" every 30 s
```

Until Firestore triggers run (Blaze, PRD D-17) it also keeps `day.activeNumbers` and
`waitingCount` correct, the same way the `onTokenWrite` trigger will.
