# 03 — Feature Development Workflow

> **D-52 (2026-11-27): the backend is Supabase; the Firebase backend (Firestore, Cloud Functions, rules, emulators) was
> removed.** Parts of this file still describe the Firebase way and are kept as background only. Current sources:
> docs/10-supabase-migration.md, DATABASE.md, ARCHITECTURE.md, docs/02 §2b (setup), TESTING_CHECKLIST.md.

The step-by-step way every feature is built in Asani, by a human or an AI agent.

---

## 1. The workflow

```
1. Understand  →  2. Confirm  →  3. Branch  →  4. Build bottom-up  →  5. Test  →  6. Document  →  7. PR
```

### Step 1: Understand
- Find the feature ID in **PRD.md §5** (e.g. F-04) and its screens in **DESIGN.md §5**.
- Check data in **DATABASE.md** and the flow in **ARCHITECTURE.md §3**.

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

What needs confirmation: anything a patient or clinic would notice (rules, limits, copy, notifications, statuses, new fields shown, security rules, paid services).
What does not: internal naming, refactors that don't change behaviour, test structure.

### Step 3: Branch
```bash
git checkout main && git pull
git checkout -b feature/F-04-booking-date-step
```

### Step 4: Build bottom-up
Always in this order. Each layer is tested before the next.

| # | Layer | Location | Notes |
|---|---|---|---|
| a | Model / enum | `packages/asani_core/lib/src/models/` | `fromMap`, `toMap`, `copyWith`, equality |
| b | Pure logic | `packages/asani_core/lib/src/logic/` | e.g. `doctorAvailability()`, `patientsAhead()`; unit tests |
| c | Backend | `functions/src/` | Callable/trigger + validation + tests on emulator |
| d | Rules + indexes | `firestore.rules`, `firestore.indexes.json` | Rules test |
| e | Repository | `apps/patient_app/lib/data/repositories/` | Only place that touches Firebase |
| f | Providers | `features/<x>/application/` | Riverpod; expose `AsyncValue` |
| g | UI | `features/<x>/presentation/` | Theme tokens, all 4 states (DESIGN §6) |

### Step 5: Test
- Unit: `asani_core` logic, function helpers
- Widget: main screen states (loading/empty/error/data)
- Emulator: function + rules tests
- Manual on **real Redmi** (and iOS when the feature touches push, phone auth or permissions)

### Step 6: Document
Update in the same branch:
- DATABASE.md if any field/collection/index changed
- PRD.md Decisions log for any confirmed behaviour
- DESIGN.md if copy or a screen changed

### Step 7: Pull request
Title: `F-04: booking date step`. Body: what, why, how to test, screenshots, checklist (AGENTS.md §9).

---

## 2. Code conventions

### Dart / Flutter
- `flutter analyze` with `flutter_lints` + project `analysis_options.yaml`; zero warnings.
- Files `snake_case.dart`, classes `PascalCase`, providers end with `Provider`.
- One public widget per file for screens; small private widgets can stay in the same file.
- No business logic in widgets. Widgets read providers and call notifier methods.
- Use `const` constructors wherever possible.
- Errors: repositories throw `AppException(code, message)`. UI maps codes to DESIGN §7 copy.
- Dates: always via `DateUtilsPk` (Asia/Karachi).

### Repository pattern example
```dart
class TokenRepository {
  TokenRepository(this._db, this._functions);
  final FirebaseFirestore _db;
  final FunctionsService _functions;

  Stream<Token> watchToken(String tokenId) => _db
      .collection('tokens')
      .doc(tokenId)
      .snapshots()
      .map((s) => Token.fromMap(s.id, s.data()!));

  Future<BookResult> book(BookRequest req) => _functions.bookToken(req);
}

final tokenRepositoryProvider = Provider((ref) => TokenRepository(
      FirebaseFirestore.instance,
      ref.watch(functionsServiceProvider),
    ));
```

### TypeScript / Functions
- ESLint + Prettier. Strict TS.
- One file per function in `src/callable/`, `src/triggers/`, `src/scheduled/`; shared code in `src/lib/` and `src/queue/`.
- Validate inputs at the top; throw `HttpsError('invalid-argument' | 'failed-precondition' | 'permission-denied' | 'not-found', message, {code})`. The `details.code` matches DESIGN §7 (e.g. `tokens-full`).
- Use `logger` from `firebase-functions`; never log full phone numbers (mask: `+92300****567`).

---

## 3. Feature checklist template

Copy into the PR description:

```
## Feature: F-xx <name>

### Confirmed decisions
- ...

### Changes
- asani_core:
- functions:
- rules/indexes:
- app:

### How to test
1. firebase emulators:start ...
2. node seed-dev.js
3. ...

### Checklist
- [ ] PRD/DESIGN followed; unclear items confirmed
- [ ] loading / empty / error / offline states
- [ ] flutter analyze clean, tests pass
- [ ] functions lint/build/test pass
- [ ] indexes + DATABASE.md updated
- [ ] rules tests
- [ ] tested on Redmi (and iOS if push/auth)
```

---

## 4. Working with an AI agent (Codex / Claude Code)

Good prompt shape:
```
Implement F-07 Family profiles (PRD.md §5, DESIGN.md S-13..S-15, DATABASE.md §3).
Follow AGENTS.md. Before coding, list anything unclear and ask me.
Build bottom-up per docs/03 §1 Step 4. Stop after the repository + providers
and show me the files before building the UI.
```
- Give one feature (or one layer) per session.
- Ask the agent to stop at checkpoints so you can review.
- The agent must ask before changing rules, schema or behaviour (AGENTS.md §3).
