# 08 — Debugging

Where to look and how to fix the problems most likely to hit Asani (Supabase backend, D-52).

---

## 1. Where to look first

| Symptom in | Look at |
|---|---|
| App UI / Dart exception | `flutter run` console, Flutter DevTools, Dart MCP runtime errors (docs/05) |
| A function call failed | The app log line `PostgrestException: <code> <message>`; the message is the error code, the hint the text |
| Data looks wrong | Supabase dashboard → Table Editor / SQL editor (dev), or the Supabase MCP (read-only) |
| Permission denied | DATABASE.md §1 + the RLS policies in `supabase/migrations/…000200_security.sql`; `01_rls.test.sql` |
| Edge Function | Dashboard → Edge Functions → `send-push` / `admin-clinic-login` → Logs |
| Scheduled job | Dashboard → Integrations → Cron (job runs and errors) |
| Notification not received | §4 checklist |

App logging: `AppLogger` (never full phone numbers).

---

## 2. Login problems

| Symptom | Cause | Fix |
|---|---|---|
| No email code | Built-in email only reaches your team's addresses (~2 / hour); or SMTP not set | Set Brevo SMTP (docs/02 §2b); check spam |
| Email has a link, not a code | Template still the default | Magic Link + Confirm signup templates: only `{{ .Token }}` |
| Code has 8 digits | OTP length setting | Auth → Email → OTP length 6 |
| "That code isn't right" for a fresh code | Wrong email typed, or an older code | Resend; codes are valid 10 minutes |
| `too-many-requests` | Supabase email / OTP rate limit | Wait; raise the email rate limit after SMTP works |
| `phone-taken` | Another app account has that number | Expected (one phone = one account, D-52) |
| Clinic: invite link opens the login page | Redirect URL not allowed | Auth → URL Configuration: Site URL + `http://localhost:8092/**` |
| Clinic: "This account doesn't have clinic access" | No `app_metadata.role` | Create the login with `admin-clinic-login` or `tools/db-test/create-login.js` |
| Clinic login disabled | Banned by the Super Admin | Super Admin → Enable login |

---

## 3. Database problems

| Symptom | Cause | Fix |
|---|---|---|
| `42501 permission denied for table …` | Writing a table / column the client has no grant for | Go through the Postgres function; never add a grant "to make it work" |
| `new row violates row-level security policy` | RLS `with check` failed (wrong owner, staff login) | Check who is signed in and the policy |
| Rows "missing" in a list | RLS hides them (correct), or the query filters wrongly | Run the same query in the SQL editor with `set role authenticated` + claims (see the tests) |
| A function raises a code you don't expect | Business rule (e.g. `session-ended` after the doctor's end time) | Read the function in the migration; codes are listed in docs/10 §6b |
| "Patients ahead" wrong | `active_numbers` stale | `node tools/queue-sim/queue-sim.js status --doctor <id>`; the token status trigger recomputes it |
| Duplicate token numbers | Impossible by design (row lock + unique index) | If seen, report with the token ids |
| Dates off by a day | Device time zone used | Use the PKT helpers (`dayKey`, `pktNow`; `private.pkt_today()` in SQL) |

---

## 4. Live updates (Realtime) not arriving

1. Filters on **uuid** columns or on **`id`** never fire. Use `clinic_id`, `doctor_id`, `date`, `city`, `month`,
   `active`, or no filter (RLS limits the rows).
2. The table must be in the `supabase_realtime` publication (all app tables are; new tables need it in a migration).
3. The user must be signed in (Realtime applies RLS).
4. Browser: the WebSocket may be blocked by a proxy; check the console.

---

## 5. Notifications not received (checklist)

1. **Permission:** phone Settings → Apps → Asani → Notifications on; `queue_alerts` channel on.
2. **Device saved:** `devices` has a row for the account with a fresh `fcm_token` (it is saved after sign-in).
3. **Step decided:** the token's `notified` has the step; `notifications` has the inbox row. Already marked = sent
   before (or skipped by the jump rule), which is correct.
4. **Queued:** `push_outbox` row exists; `sent_at` set = FCM accepted it; `last_error` shows why not; `attempts` ≤ 5.
   No row while the inbox row exists = queue alerts are off for the account (D-18).
5. **Delivered to the function:** `select * from net._http_response order by created desc limit 5` (status 200,
   `{"claimed":…, "sent":…}`); `send-push` logs.
6. **Secrets:** `send-push` needs `PUSH_SECRET` (same as Vault `push_secret`) and `FCM_SERVICE_ACCOUNT` (base64).
   A JSON parse error in `last_error` = the FCM key secret is broken.
7. **Dead token:** FCM "not registered" → the device row is deleted; the app saves a new token on next sign-in.
8. **Xiaomi / Vivo:** Autostart on, battery saver "No restrictions"; test with the screen locked.
9. **iOS:** APNs key in the Firebase project, Push + Background Modes capabilities, a real device.

---

## 6. Command-line problems

| Problem | Fix |
|---|---|
| `supabase db push`: "Connection terminated unexpectedly" | Add `?sslmode=require` to the URL; retry (the pooler sometimes drops one attempt) |
| Password with `@` / `#` breaks the URL | URL-encode it (`@` → `%40`), no `[ ]` around it |
| CLI: "Confirmation required … agent mode" | It wants `--yes`; only after Sarbuland asked for that push / deploy |
| `AccessTokenRequiredError` | `SUPABASE_ACCESS_TOKEN` from `supabase/.access-token.local` |
| Web build: "Couldn't resolve the package …" after removing a plugin | Stale plugin list: `flutter clean`, then `flutter pub get` at the repo root |
| `flutter analyze` complains about `test/widget_test.dart` (`MyApp`) | Old untracked template file; delete it |
| Gradle / `google-services.json` for a flavor | It lives in `android/app/src/dev/` and `src/prod/` (FCM only) |
| Riverpod rebuild loops | `ref.read` in callbacks, `ref.watch` only in build |
| go_router redirect loop | Redirects must return `null` when already on the target |

---

## 7. Reproducing a reported bug

1. Get device, OS, app version, backend (`demo` / `supabase`) and steps (bug template docs/07 §6).
2. Reproduce on asani-dev with `queue-sim` (walk-ins, Next, skip…) or the demo build.
3. Write a **failing test first**: pgTAP for database rules, Dart tests for app logic. Then fix.
4. Note the cause in the commit message.

---

## 8. Useful commands

```bash
flutter clean && flutter pub get          # at the repo root
flutter run -v
flutter logs
adb logcat | findstr /i "flutter fcm firebase"
node tools/db-test/run.js
node tools/queue-sim/queue-sim.js status --doctor d_ayesha
```
