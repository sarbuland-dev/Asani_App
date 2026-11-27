# 05 — MCP Connection (AI agent tooling)

MCP (Model Context Protocol) servers let AI coding agents (Codex, Claude Code, Cursor, Gemini CLI…) use real tools:
run the Dart analyzer, hot reload the app, look at the **dev** database, read logs.

Asani uses:

| Server | What it gives the agent | Command |
|---|---|---|
| **Dart and Flutter MCP server** (official) | Analyze / fix, format, tests, pub.dev search, add packages, running app's widget tree and errors, hot reload | `dart mcp-server` |
| **Supabase MCP server** (official) | Tables, SQL queries, migrations list, logs, Edge Functions of the dev project | `npx -y @supabase/mcp-server-supabase@latest --project-ref=lgnbxxcmogbbzmuqyrgu --read-only` |

Firebase MCP is no longer needed: Firebase is only used for FCM (D-52). Optional: GitHub's official MCP server.

---

## 1. Requirements

- Dart **3.9+** (`dart --version`).
- Node.js + npm (for `npx`).
- A Supabase **personal access token** for the MCP server, given as the env variable `SUPABASE_ACCESS_TOKEN`
  (supabase.com/dashboard/account/tokens; read-only is enough). Keep it out of the repo; never paste it in a chat.

---

## 2. Claude Code

```bash
claude mcp add --transport stdio dart -- dart mcp-server
claude mcp add supabase --env SUPABASE_ACCESS_TOKEN=<token> -- npx -y @supabase/mcp-server-supabase@latest --project-ref=lgnbxxcmogbbzmuqyrgu --read-only
claude mcp list        # both should show as Connected
```
Claude Code reads **CLAUDE.md**, which imports AGENTS.md.

## 3. Codex

```toml
# ~/.codex/config.toml
[mcp_servers.dart]
command = "dart"
args = ["mcp-server", "--force-roots-fallback"]

[mcp_servers.supabase]
command = "npx"
args = ["-y", "@supabase/mcp-server-supabase@latest", "--project-ref=lgnbxxcmogbbzmuqyrgu", "--read-only"]
env = { SUPABASE_ACCESS_TOKEN = "<token>" }
```
> **Windows:** if `npx` is not found when the client starts the server, use `command = "npx.cmd"`.

Codex reads **AGENTS.md** at the repo root automatically.

## 4. Other clients (same JSON shape)

```json
{
  "mcpServers": {
    "dart": { "command": "dart", "args": ["mcp-server"] },
    "supabase": {
      "command": "npx",
      "args": ["-y", "@supabase/mcp-server-supabase@latest", "--project-ref=lgnbxxcmogbbzmuqyrgu", "--read-only"],
      "env": { "SUPABASE_ACCESS_TOKEN": "<token>" }
    }
  }
}
```
Keep client configs (they contain the token) in your user folder, never in the repo.

---

## 5. 🔴 Safety rules for MCP

1. **Dev only.** The Supabase MCP server points at `asani-dev` (`--project-ref`). Never point it at a prod project.
2. **`--read-only`** stays on. Schema changes go through migrations in git (`supabase/migrations/`), not through MCP.
3. Any write, delete, deploy or settings change needs Sarbuland's explicit approval in that session (AGENTS.md §7).
4. Never paste the access token, the database URL or the service role key into an agent chat.
5. Read the agent's tool calls before approving them.

---

## 6. What to ask the agent

| Task | Example prompt |
|---|---|
| Fix analyzer errors | "Use the Dart MCP server to analyze `apps/patient_app` and fix all errors and warnings." |
| Runtime bug | "The app is running on my phone. Get the runtime errors and the widget tree for the token screen." |
| Check data | "Using the Supabase MCP (dev), show today's `queue_days` row for `d_ayesha` and its tokens." |
| Why access fails | "Read the RLS policies on `tokens` and explain why the clinic login can't see this walk-in." |
| Logs | "Show the last Edge Function logs of `send-push`." |

---

## 7. Troubleshooting

| Problem | Fix |
|---|---|
| `dart: Could not find a command named "mcp-server"` | Dart < 3.9: `flutter upgrade` |
| Supabase MCP: unauthorized | `SUPABASE_ACCESS_TOKEN` missing or expired; make a new token |
| Server fails to start on Windows | Use `npx.cmd`; check `node -v` |
| Agent can't hot reload | The app must run in debug mode on the same machine (Dart Tooling Daemon) |
| Listed but not "Connected" | Restart the client; run the command in a terminal to see the error |

Official docs: docs.flutter.dev/ai/mcp-server · supabase.com/docs/guides/getting-started/mcp
