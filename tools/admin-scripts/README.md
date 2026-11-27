# admin-scripts (local files only)

The Firebase admin scripts were removed with the Firebase backend (D-52, 2026-11-26; they are in git history).
Dev logins on Supabase are made with `node tools/db-test/create-login.js` (docs/02 §2b).

This folder still holds two **git-ignored** local files:
- `dev-test-logins.local.txt`: dev test logins and their passwords (written by `create-login.js`). Never commit, never
  paste passwords in chat.
- `serviceAccount.dev.json`: the Firebase service account of `asani-b2b17`, needed only to (re)set the FCM secret of the
  `send-push` Edge Function (docs/10 phase 3). Never commit.
