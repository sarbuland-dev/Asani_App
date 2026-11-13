/**
 * Shared target selection for admin scripts: Firestore emulator by default,
 * `--project dev` = asani-b2b17 with serviceAccount.dev.json. No prod option.
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const DEV_PROJECT_ID = 'asani-b2b17';

function parseArgs(argv) {
  const opts = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) opts[argv[i].slice(2)] = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : true;
  }
  return opts;
}

function init(project) {
  if (!project || project === 'emulator') {
    process.env.FIRESTORE_EMULATOR_HOST ||= '127.0.0.1:8080';
    process.env.FIREBASE_AUTH_EMULATOR_HOST ||= '127.0.0.1:9099'; // clinic/admin logins
    admin.initializeApp({ projectId: DEV_PROJECT_ID });
    return `emulator (${process.env.FIRESTORE_EMULATOR_HOST})`;
  }
  if (project !== 'dev') {
    console.error(`Unknown --project "${project}". Use no flag (emulator) or --project dev. There is no prod option.`);
    process.exit(1);
  }
  const keyPath = path.join(__dirname, '..', 'serviceAccount.dev.json');
  if (!fs.existsSync(keyPath)) {
    console.error(`Missing ${keyPath}. Never commit this file.`);
    process.exit(1);
  }
  const key = JSON.parse(fs.readFileSync(keyPath, 'utf8'));
  if (key.project_id !== DEV_PROJECT_ID) {
    console.error(`Key is for "${key.project_id}", expected "${DEV_PROJECT_ID}". Stopping.`);
    process.exit(1);
  }
  admin.initializeApp({ credential: admin.credential.cert(key), projectId: DEV_PROJECT_ID });
  return `dev project ${DEV_PROJECT_ID}`;
}

/** Shared code from the Cloud Functions build (run `npm run build` in functions/). */
function functionsLib(rel) {
  const file = path.join(__dirname, '../../../functions/lib', rel);
  if (!fs.existsSync(file)) {
    console.error(`Missing ${file}. Run "npm run build" in functions/ first.`);
    process.exit(1);
  }
  return require(file);
}

module.exports = { admin, parseArgs, init, functionsLib };
