# 05 — MCP Connection (AI agent tooling)

> **D-52 (2026-11-27): the backend is Supabase; the Firebase backend (Firestore, Cloud Functions, rules, emulators) was
> removed.** Parts of this file still describe the Firebase way and are kept as background only. Current sources:
> docs/10-supabase-migration.md, DATABASE.md, ARCHITECTURE.md, docs/02 §2b (setup), TESTING_CHECKLIST.md.

MCP (Model Context Protocol) servers let AI coding agents (Codex, Claude Code, Cursor, Gemini CLI…) use real tools: run the Dart analyzer, hot reload the app, read Firestore in the **dev** project, check Auth users, read Crashlytics, etc.

Asani uses two MCP servers:

| Server | What it gives the agent | Command |
|---|---|---|
| **Dart and Flutter MCP server** (official) | Analyze/fix code, format, run tests, pub.dev search, add packages, inspect running app, widget tree, runtime errors, hot reload | `dart mcp-server` |
| **Firebase MCP server** (official) | Firebase projects, Auth users, Firestore data and rules, Crashlytics, deploy helpers | `npx -y firebase-tools@latest mcp` |

Optional: GitHub's official MCP server for issues/PRs (follow GitHub's `github-mcp-server` instructions).

---

## 1. Requirements

- Dart **3.9+** / a Flutter version that ships it (`dart --version`). The Dart MCP server is still marked experimental.
- Node.js + npm (for the Firebase MCP server via `npx`).
- Firebase CLI logged in: `firebase login`. The Firebase MCP server uses the **same credentials as your Firebase CLI**.
- `firebase use dev` in the repo, so the default project is `asani-dev`.

---

## 2. Codex (main agent for this project)

### CLI commands
```bash
# from the repo root
codex mcp add dart -- dart mcp-server --force-roots-fallback
codex mcp add firebase -- npx -y firebase-tools@latest mcp --dir <ABSOLUTE_PATH_TO_REPO> --only core,auth,firestore,functions,crashlytics
codex mcp list
```

### Or edit `~/.codex/config.toml` directly
```toml
[mcp_servers.dart]
command = "dart"
args = ["mcp-server", "--force-roots-fallback"]

[mcp_servers.firebase]
command = "npx"
args = [
  "-y", "firebase-tools@latest", "mcp",
  "--dir", "C:\\Users\\<you>\\Projects\\asani",
  "--only", "core,auth,firestore,functions,crashlytics"
]
```

> **Windows note:** if `npx` is not found when Codex starts the server, use `command = "npx.cmd"` or `command = "cmd"` with `args = ["/c", "npx", "-y", "firebase-tools@latest", "mcp", ...]`.

Codex also reads **AGENTS.md** at the repo root automatically, so the project rules apply in every session.

---

## 3. Claude Code

```bash
claude mcp add --transport stdio dart -- dart mcp-server
claude mcp add firebase -- npx -y firebase-tools@latest mcp --dir <ABSOLUTE_PATH_TO_REPO>
claude mcp list        # should show both as ✓ Connected
```
Claude Code reads **CLAUDE.md**, which imports AGENTS.md.

---

## 4. Other clients (same JSON shape)

Cursor (`.cursor/mcp.json`), Gemini CLI (`.gemini/settings.json`), Claude Desktop (`claude_desktop_config.json`), Antigravity (`mcp_config.json`):

```json
{
  "mcpServers": {
    "dart": {
      "command": "dart",
      "args": ["mcp-server"]
    },
    "firebase": {
      "command": "npx",
      "args": ["-y", "firebase-tools@latest", "mcp",
               "--dir", "<ABSOLUTE_PATH_TO_REPO>",
               "--only", "core,auth,firestore,functions,crashlytics"]
    }
  }
}
```
Android Studio: use the MCP support of your AI plugin (Gemini in Android Studio supports MCP servers) with the same command/args.

Do **not** commit files containing personal absolute paths; keep client configs in your user folder or add them to `.gitignore`.

---

## 5. 🔴 Safety rules for MCP

1. **Dev only.** The Firebase MCP server must point at `asani-dev`. Before a session run `firebase use` and confirm it says `dev`. Never `firebase use prod` while an agent is running.
2. `--only` limits the tools exposed (core tools always stay available). Do not add `hosting` or `storage` until needed.
3. Agents may **read** dev data freely. Any **write, delete, deploy or rules change** through MCP requires Sarbuland's explicit approval in that session (AGENTS.md §7).
4. Never paste service account keys into an agent chat.
5. The agent's MCP tool calls are shown in the client; read them before approving.

---

## 6. What to ask the agent to do with MCP

| Task | Example prompt |
|---|---|
| Fix analyzer errors | "Use the Dart MCP server to analyze `apps/patient_app` and fix all errors and warnings." |
| Add a package | "Find a maintained QR code package on pub.dev and add it to patient_app." |
| Runtime bug | "The app is running on my Redmi. Get the runtime errors and the widget tree for the token screen and find why the number overflows." |
| Check data | "Using Firebase MCP (dev), show today's queue day doc for doctor doc_ayesha and the tokens for it." |
| Check rules | "Read firestore.rules and explain why the profile history query fails for walk-in visits." |
| Crash triage | "Get the top Crashlytics issues for pk.asani.patient.dev from the last 7 days." |

---

## 7. Troubleshooting

| Problem | Fix |
|---|---|
| `dart: Could not find a command named "mcp-server"` | Dart < 3.9. Upgrade Flutter (`flutter upgrade`). |
| Firebase MCP shows no project | Run `firebase login` and `firebase use dev`; pass `--dir` to the folder containing `firebase.json`. |
| Server fails to start on Windows | Use `npx.cmd` (see §2). Check `node -v`. |
| Agent can't hot reload | The app must be running in debug mode started from the same machine; the Dart MCP server connects to the Dart Tooling Daemon. |
| Server listed but not "Connected" | Restart the client; run the command manually in a terminal to see the error. |

Official docs: Dart and Flutter MCP server (docs.flutter.dev/ai/mcp-server), Firebase MCP server (firebase.google.com/docs/ai-assistance/mcp-server).
