# Testing checklist (Supabase, D-52)

Run these before merging a backend change, and the manual part before a pilot release. Dev only (`asani-dev`).
Details: docs/07-testing-and-qa.md, docs/10-supabase-migration.md.

## 1. Automatic (PC)

| Check | Command | Expect |
|---|---|---|
| Database (RLS, booking, queue, push, auth, clinic, admin) | `node tools/db-test/run.js` | 5 files PASS (37 · 59 · 27 · 20 · 76) |
| Two bookings at the same moment | `node tools/db-test/concurrency.js` | numbers 1…20, 0 duplicates, PASS |
| Patient app calls through the public API | `node tools/db-test/client-smoke.js` | all `ok`, PASS |
| Clinic-login Edge Function (no real email) | `node tools/db-test/admin-login-smoke.js` | 5 `ok`, PASS |
| Shared packages | `cd packages/asani_core; dart test` | all pass |
| Patient app | `cd apps/patient_app; flutter analyze; flutter test` | 0 issues (except an old untracked `widget_test.dart`), all pass |
| Clinic web | `cd apps/clinic_web; flutter analyze` | 0 issues |

All of them clean up after themselves (pgTAP files roll back; the smoke scripts delete only their own rows).

## 2. One-time setup (Sarbuland, Supabase dashboard)

- [ ] Auth → Email: OTP expiration 600 s, OTP length 6.
- [ ] Auth → Email templates: Magic Link + Confirm signup show only `{{ .Token }}`; Invite + Reset have the Asani subjects.
- [ ] Auth → SMTP: Brevo (sender verified); Rate limits ~100 emails/hour.
- [ ] Auth → URL Configuration: Site URL + Redirect URLs for the clinic web.
- [ ] Dev logins: `node tools/db-test/create-login.js --role superAdmin …` / `--role clinic --clinic c_alshifa …`.

## 3. Manual, patient app on a phone (`flutter run --flavor dev --dart-define=BACKEND=supabase`)

- [ ] Email → code arrives (check spam) → wrong code shows "That code isn't right" → right code → profile setup.
- [ ] Profile with a number another account uses → "This number is already used by another Asani account".
- [ ] Home lists the Lahore clinics; Search by doctor works; Al-Shifa → Dr. Ayesha → book → token A-n.
- [ ] Book the same person again with the same doctor today → duplicate message.
- [ ] Add a family member; book for them.
- [ ] Allow notifications; in Supabase `devices` the phone's row appears.
- [ ] PC: `node tools/queue-sim/queue-sim.js start|next --doctor d_ayesha` → the token screen moves live; pushes
      "3 / 2 patients ahead", "You're next", "Your turn now" arrive (Redmi / Vivo), each once.
- [ ] Notifications list (bell) shows every push; opening it clears the unread count.
- [ ] Cancel a booked token → the number leaves the queue.
- [ ] Account → Mobile number change works; Delete account signs out and the data is anonymised.

## 4. Manual, clinic web (`flutter run -d chrome --web-port 8092 --dart-define=BACKEND=supabase`)

- [ ] Login as the clinic → Queue Board shows the clinic's doctors; a patient login is refused.
- [ ] Start → doctor "Running"; an app booking appears live as "App / Booked".
- [ ] Next on a Booked patient → "has not arrived · Skip / Call anyway".
- [ ] Walk-in (new patient) → number continues the sequence; a number already on the app shows
      "App account (number not verified)".
- [ ] Skip → the patient gets "You missed your turn"; check in again → called next (D-24).
- [ ] Undo last Next within 30 s → no push; one more "Your turn now" later (D-38).
- [ ] Cancel with a reason → patient push "cancelled by …".
- [ ] Walk-in patient page → **Link to app account** → find the number → pick the family member → confirm → the visit
      shows in the patient's app.
- [ ] Doctors: add (asks the manager PIN once set), leave day, bulk cancel; Settings needs a map location.
- [ ] Super Admin: Same doctor link / unlink; New clinic → invite email → "Set your Asani password" → login;
      Disable login → cannot log in; Payments record once; Run billing jobs.

## 5. Before the pilot

- [ ] Decide the pause risk (Pro plan or keep-alive) and backups (S-7, docs/10 §6).
- [ ] Own email domain for codes / invites (Q-06), prod project in Mumbai, prod Firebase for FCM.
