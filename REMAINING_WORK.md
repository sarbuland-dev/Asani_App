# Remaining work

Last updated: 2026-11-28. Only open items are listed here; finished work is in git history and PRD.md §9.
The backend is Supabase (D-52, `docs/10-supabase-migration.md`). Firebase is used only for FCM push.

The old Firebase items are **replaced by D-52** and were removed from this list: §2 Blaze plan, §3 Firebase
production project, §5 emulator rules tests and functions lint, §11 Firestore rules / TTL, and the Firebase
items of the old §6 (demo bridges, double triggers, functions engines), §7 (Cloud Functions, emulator runs,
Firebase console and Hosting) and §8 (emulator speed, findings already decided as D-21…D-24 and rebuilt in
Postgres). Section numbers are kept so older notes still point to the right place.

## 1. Push notifications (phone tests)
- [ ] Push on Supabase on a real phone: login → book → live queue → push, also with the app fully killed.
      Since 2026-11-28 the app registers with `register()` / `onRegistered` (Firebase Installation ID, D-61) and
      `send-push` (deployed to asani-dev the same day) sends to `fid`. **No real push to an ID has been seen yet.**
      This needs a new Android build.
- [ ] Follow-up reminder tap opens a pre-filled booking.
- [ ] Skip and clinic-cancel pushes on a real phone (D-23, D-34; QA-4b in docs/07).
- [ ] The Vivo's saved device token (22 Nov) is dead; it is replaced when the new build saves its ID.
- [ ] iPhone: not tested at all.
- [ ] With the app open, a cancel or skip push shows no in-app banner (the screens update live). Decide if it should.

## 3. Left from the 28 November QA run (`qa-bug-hunt/`, local only)
- [ ] Clinic QR / deep link (F-11): left out on purpose; waits for a real domain (Q-06).
- [ ] Support number for the clinic Help page (the call / WhatsApp line is hidden until then, D-68).
- [ ] A suspended clinic can only bulk-cancel on days already marked as leave, and has no cancel button for other
      future days (Upcoming has no actions, as for any clinic).
- [ ] Decide: Account says "Queue alerts"; board P10 says "Notifications".
- [ ] No offline copy of data on Supabase: opening the app offline probably shows no data (not reproduced).
- [ ] Not tested: a real phone (including Save to gallery and swipe back), iPhone, real TalkBack.

## 4. Launch preparation
- [ ] Crash reporting + basic analytics (PRD F-12).
- [ ] Privacy Policy and Terms pages, real domain for links (PRD Q-06).
- [ ] Play Store listing, screenshots, data-safety form; App Store later.
- [ ] Prod Supabase project in **Mumbai** (`ap-south-1`); dev landed in Tokyo, which is fine for dev only.
- [ ] Prod Firebase project for FCM; add `lib/firebase_options_prod.dart` and the prod
      `google-services.json` to `.gitignore` first (never commit).
- [ ] Release keystore (signing config is ready, docs/02-setup.md §7b; Sarbuland creates the keystore).
- [ ] Before the pilot: the free-plan pause risk (Pro plan or keep-alive) and backups.

## 5. Testing gaps
- [ ] Visit counts on the Family tab (cards and the D-65 summary) come from the latest 150 tokens the app loads on
      Supabase, so an account with more would show too few. Counting all visits needs a query or database function.
- [ ] No automated tests for the patient app's Supabase repositories or `PushService`
      (`tools/db-test/client-smoke.js` covers the main calls from outside; its first Realtime check can fail on a
      slow connection and pass on a rerun).
- [ ] `apps/clinic_web` has no tests.

## 7. Clinic web
- [ ] Real print test on a thermal 80 mm printer and A5 with `--kiosk-printing`.
- [ ] Web domain / hosting (Q-W09).

## 8. App ↔ web
- [ ] Open question (from 2026-11-14): is anything else wanted for walk-ins in the app? Reception links them with
      **Link to app account** (D-52).

## 10. Payments (ON HOLD, 2026-11-22; ask before building)
- [ ] **Payment proof:** a reference form (method, amount, date, transaction ID, note), or a screenshot upload to
      Supabase Storage.
- [ ] **Defaulter reminder:** WhatsApp / Gmail buttons with the text ready, or an automatic email through Brevo
      (today the reminder is only recorded).
- [ ] **Bank details:** "How to pay" still has placeholder bank / IBAN / JazzCash numbers.
- [ ] Q-W05 grace / suspension days (7 and 15?), Q-W06 prices.

## 12. Clinic web and Super Admin UI
- [ ] Open question: does **Arrived & Print** still print the Asani clinic form (C-07), or nothing at all?
- [ ] Not checked yet on Supabase in Chrome: grace and suspended banners, Set password, Link to app account,
      Add doctor dialog, set follow-up dialog, "PIN locked" view. (2026-11-28: the clinic web's 30 database calls
      match the functions on asani-dev; the screens themselves need a signed-in browser.)
- [ ] Not checked yet (Super Admin): saving actions and dialogs, new clinic steps 2-4, Usage tab, 1180 px width,
      loading state on a slow connection, Supabase.
- [ ] Left out until they work (D-53): Send payment proof, Contact support button, Booked from reminder %,
      Excel export.
- [ ] Left out until they work (D-58): invoice numbers, payment proof screenshot, extension reason, reminder email
      preview, admin password / sign out everywhere, map picker.

## 13. Supabase setup (Sarbuland; steps in docs/02 §2b)
- [ ] Auth settings: OTP 600 s and 6 digits, code-only email templates, Brevo SMTP; then log in on the phone with
      `BACKEND=supabase`.
- [ ] Auth URL Configuration (Site URL + redirect) and Invite / Reset email subjects; then a real "New clinic"
      with an invite email (needs Brevo).
- [ ] GitHub secret `SUPABASE_DB_URL` so CI runs the database tests.
- [ ] Android debug build of the patient app (only when Sarbuland asks).
- [ ] Optional: on the Supabase dev data only Shifa Family has no map location (the seed leaves one clinic without
      on purpose, to test "no distance"). Noor and Care Plus were old Firebase test data.
- [ ] Other open product questions: Q-03 booking window, Q-04 booking after the session starts, Q-05 max 5
      active tokens.
