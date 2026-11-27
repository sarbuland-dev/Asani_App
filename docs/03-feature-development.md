# 03 — Feature Development Workflow

The step-by-step way every feature is built in Asani, by a human or an AI agent (Supabase backend, D-52).

---

## 1. The workflow

```
1. Understand  →  2. Confirm  →  3. Branch  →  4. Build bottom-up  →  5. Test  →  6. Document  →  7. Merge
```

### Step 1: Understand
- Find the feature in **PRD.md §5** (or PRD-CLINIC-WEB.md) and its screens in **DESIGN.md** / the screens board.
- Check the tables in **DATABASE.md**, the flow in **ARCHITECTURE.md §3**, and existing functions in
  **docs/10 §6b**.

### Step 2: Confirm (mandatory when anything is unclear)
Write a short note for Sarbuland **before coding**:
```
Feature: F-04 Booking, date step
Unclear: Can a patient book for today after the session has started?
Options:
  A) Yes, until session end time (current PRD)
  B) Only until session start
Recommendation: A, because patients often book while on the way.
```
Wait for the answer. Record it in PRD.md §9 Decisions log.

Needs confirmation: anything a patient or clinic notices (rules, limits, copy, notifications, statuses, new visible
fields, security rules, paid services). Does not: internal names, refactors that keep behaviour, test structure.

### Step 3: Branch
```bash
git switch main
git switch -c feature/F-04-booking-date-step
```

### Step 4: Build bottom-up
Always in this order. Each layer is tested before the next.

| # | Layer | Location | Notes |
|---|---|---|---|
| a | Model / pure logic | `packages/asani_core/lib/src/` | `fromMap` / `toMap`, rules like availability or "patients ahead"; unit tests |
| b | Schema | new file in `supabase/migrations/` | Tables, columns, checks, indexes. **Never edit a pushed migration** |
| c | Security | same migration | RLS policy + grants; direct client writes only when really needed |
| d | Backend logic | Postgres function (`security definer`, `set search_path = ''`) | Check the caller (`private.is_patient()`, `private.clinic_actor()`, `private.admin_actor()`) and every input; `raise exception '<code>' using hint = '<text>'`; lock the queue day before changing token statuses |
| e | Notifications | `private.notify_user(...)` in the same transaction | Never call FCM from SQL; `send-push` delivers |
| f | Tests | `supabase/tests/database/NN_*.test.sql` (pgTAP) | Allow + deny cases; pin the clock with `asani.test_now` |
| g | Repository | `apps/<app>/lib/data/supabase/…` (+ the demo version) | Only place that calls Supabase; maps rows with `Rows` / `_plain`; maps error codes to `AppException` |
| h | Providers | `lib/data/providers.dart` or the feature folder | Riverpod; expose `AsyncValue` |
| i | UI | `lib/features/<x>/` | Theme tokens, loading / empty / error / offline states (DESIGN §6) |

### Step 5: Test
- `dart test` (asani_core), `flutter analyze` + `flutter test` (apps).
- `node tools/db-test/run.js` after pushing the migration to **asani-dev** (only when Sarbuland asked for the push);
  `client-smoke.js` for app-facing changes.
- Manual on a real phone (Redmi / Vivo) for push, login and permissions; in Chrome for the clinic web.
- No `flutter build` unless Sarbuland says "build".

### Step 6: Document
In the same branch: DATABASE.md (schema), docs/10 §6b (new function or error code), PRD.md §9 (confirmed behaviour),
DESIGN.md (copy / screens), REMAINING_WORK.md (what is still open), TESTING_CHECKLIST.md (new manual check).

### Step 7: Merge
Commit only your own files, merge into `main`, delete the branch. Push to GitHub only when Sarbuland asks.

---

## 2. Code conventions

### Dart / Flutter
- `flutter analyze` with zero warnings. Files `snake_case.dart`, classes `PascalCase`, providers end with `Provider`.
- No business logic in widgets; widgets read providers and call repository / notifier methods.
- Errors: repositories throw `AppException(code, message)`; the database's error code is the exception message.
- Dates: Asia/Karachi helpers from `asani_core` (`dayKey`, `pktNow`), never the device time zone.
- Realtime streams: filter on `clinic_id`, `doctor_id`, `date`, `city`, `month` or `active`; filters on uuid / `id`
  columns never fire (stream unfiltered and let RLS limit the rows).

### Repository example
```dart
class SupabaseTokenRepository implements TokenRepository {
  @override
  Stream<Token?> watchToken(String tokenId) => Supabase.instance.client
      .from('tokens')
      .stream(primaryKey: ['id'])                       // RLS: only my tokens
      .map((rows) => Rows.parseAll(rows.where((r) => r['id'] == tokenId), Rows.token, 'token').firstOrNull);

  @override
  Future<Token> bookToken({required String clinicId, required String doctorId, required String patientId, required String date}) async {
    final res = await Supabase.instance.client.rpc('book_token', params: {
      'p_clinic_id': clinicId, 'p_doctor_id': doctorId, 'p_patient_id': patientId, 'p_date': date,
    });
    // …read the token back; PostgrestException.message = 'tokens-full', 'duplicate-token', …
  }
}
```

### SQL
- One concern per migration file, named `YYYYMMDDHHMMSS_what.sql`; comments say which PRD item / decision it serves.
- Functions: `language plpgsql security definer set search_path = ''`, every table name schema-qualified
  (`public.tokens`), grants: `revoke … from public, anon; grant … to authenticated` (or `service_role`).
- Never log or return full phone numbers to a clinic that should not see them.

---

## 3. Feature checklist template

```
## Feature: F-xx <name>

### Confirmed decisions
- ...

### Changes
- asani_core:
- supabase (migration / function / RLS / test):
- app / web:

### How to test
1. node tools/db-test/run.js
2. flutter run --flavor dev --dart-define=BACKEND=supabase   (or the web with --web-port 8092)
3. ...

### Checklist
- [ ] PRD / DESIGN followed; unclear items confirmed
- [ ] loading / empty / error / offline states
- [ ] flutter analyze clean, tests pass
- [ ] pgTAP tests (allow + deny), DATABASE.md + docs/10 updated
- [ ] tested on a real phone (push / login) or in Chrome (web)
```

---

## 4. Working with an AI agent (Codex / Claude Code)

```
Implement F-07 Family profiles (PRD.md §5, DESIGN.md S-13..S-15, DATABASE.md §3).
Follow AGENTS.md. Before coding, list anything unclear and ask me.
Build bottom-up per docs/03 §1 Step 4. Stop after the migration + tests and show me
the SQL before building the app side.
```
- One feature (or one layer) per session; ask the agent to stop at checkpoints.
- The agent asks before changing behaviour, schema or security (AGENTS.md §3), and before pushing / deploying.
