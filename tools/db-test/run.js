#!/usr/bin/env node
// Runs the pgTAP tests in supabase/tests/database against the Supabase dev database (D-52, S-1: no Docker).
// Every test file starts with `begin;` and ends with `rollback;`, so no test data stays behind.
//
// Database URL (never committed), first found wins:
//   1. env SUPABASE_DB_URL
//   2. file supabase/.db-url.local  (one line: the "Session pooler" URI from Supabase → Connect)
//
// Usage: node tools/db-test/run.js [file-filter]
const fs = require('node:fs');
const path = require('node:path');
const { Client } = require('pg');

const root = path.resolve(__dirname, '..', '..');
const testsDir = path.join(root, 'supabase', 'tests', 'database');

function dbUrl() {
  if (process.env.SUPABASE_DB_URL) return process.env.SUPABASE_DB_URL.trim();
  const file = path.join(root, 'supabase', '.db-url.local');
  if (fs.existsSync(file)) return fs.readFileSync(file, 'utf8').trim();
  console.error('No database URL. Set SUPABASE_DB_URL or create supabase/.db-url.local (see docs/02-setup.md).');
  process.exit(2);
}

async function runFile(client, file) {
  const sql = fs.readFileSync(file, 'utf8');
  const lines = [];
  try {
    const results = await client.query(sql);
    for (const r of [].concat(results)) {
      for (const row of r.rows ?? []) {
        for (const v of Object.values(row)) if (typeof v === 'string') lines.push(...v.split('\n'));
      }
    }
  } catch (e) {
    await client.query('rollback').catch(() => {});
    return { ok: false, lines: [`# ERROR: ${e.message}${e.hint ? ` (${e.hint})` : ''}`] };
  }
  const tap = lines.filter((l) => /^(ok|not ok|#|\s+#|1\.\.)/.test(l));
  const failed = tap.some((l) => l.startsWith('not ok') || /# Looks like/.test(l));
  return { ok: !failed && tap.some((l) => l.startsWith('ok')), lines: tap };
}

(async () => {
  const filter = process.argv[2] ?? '';
  const files = fs.readdirSync(testsDir).filter((f) => f.endsWith('.sql') && f.includes(filter)).sort();
  const client = new Client({ connectionString: dbUrl(), ssl: { rejectUnauthorized: false } });
  await client.connect();
  let allOk = true;
  for (const f of files) {
    const { ok, lines } = await runFile(client, path.join(testsDir, f));
    console.log(`\n=== ${f}: ${ok ? 'PASS' : 'FAIL'}`);
    for (const l of lines) if (!ok || l.startsWith('not ok') || l.startsWith('#')) console.log(l);
    if (ok) console.log(`${lines.filter((l) => l.startsWith('ok')).length} tests passed`);
    allOk &&= ok;
  }
  await client.end();
  process.exit(allOk ? 0 : 1);
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
