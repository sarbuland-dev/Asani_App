#!/usr/bin/env node
/**
 * One-time: creates the Super Admin login for the clinic web (PRD-CLINIC-WEB §5.1).
 * Sets the `role: superAdmin` custom claim and prints a link to set the password.
 *
 *   node create-super-admin.js --email you@example.com --name "Sarbuland"               # emulator
 *   node create-super-admin.js --email you@example.com --name "Sarbuland" --project dev  # asani-b2b17
 *
 * Safe to run again (updates the claim, prints a fresh link). No prod option.
 */
const { admin, parseArgs, init } = require('./lib/target');

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (!opts.email || opts.email === true) {
    console.log('Usage: node create-super-admin.js --email <email> --name "<name>" [--project dev]');
    process.exit(1);
  }
  const where = init(opts.project);
  const email = String(opts.email).trim().toLowerCase();
  const name = opts.name && opts.name !== true ? String(opts.name) : 'Super Admin';
  const auth = admin.auth();

  let user;
  try {
    user = await auth.getUserByEmail(email);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    user = await auth.createUser({ email, displayName: name, password: require('crypto').randomBytes(24).toString('base64url') });
  }
  const claims = user.customClaims ?? {};
  if (claims.role === 'clinic') throw new Error(`${email} is a clinic login. Use another email.`);
  await auth.setCustomUserClaims(user.uid, { role: 'superAdmin' });
  await admin.firestore().collection('adminUsers').doc(user.uid).set(
    { email, name, role: 'superAdmin', createdAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true },
  );
  const link = await auth.generatePasswordResetLink(email);
  console.log(`Super Admin ready on ${where}: ${email} (uid ${user.uid})`);
  console.log(`Set the password here (one-time link):\n${link}`);
}

main().then(() => process.exit(0), (e) => {
  console.error(e.message ?? e);
  process.exit(1);
});
