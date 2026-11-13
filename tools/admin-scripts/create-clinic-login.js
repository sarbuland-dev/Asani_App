#!/usr/bin/env node
/**
 * Gives an EXISTING clinic (e.g. the seeded c_alshifa) its single clinic login
 * (PRD-CLINIC-WEB D-18), the same as the New clinic wizard does for new ones:
 * Auth user + `role: clinic, clinicId` claims + clinicAccounts doc + a default
 * billing doc if missing. Prints a link to set the password.
 *
 *   node create-clinic-login.js --clinic c_alshifa --email clinic@example.com --owner "Dr. Tariq" [--project dev]
 *
 * Safe to run again. No prod option.
 */
const { admin, parseArgs, init } = require('./lib/target');

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (!opts.clinic || !opts.email || opts.clinic === true || opts.email === true) {
    console.log('Usage: node create-clinic-login.js --clinic <clinicId> --email <email> [--owner "<name>"] [--phone +923001234567] [--project dev]');
    process.exit(1);
  }
  const where = init(opts.project);
  const db = admin.firestore();
  const auth = admin.auth();
  const clinicId = String(opts.clinic);
  const email = String(opts.email).trim().toLowerCase();
  const owner = opts.owner && opts.owner !== true ? String(opts.owner) : 'Clinic manager';

  const clinicRef = db.collection('clinics').doc(clinicId);
  const clinic = (await clinicRef.get()).data();
  if (!clinic) throw new Error(`Clinic ${clinicId} not found. Run seed-dev.js first.`);

  const existing = await db.collection('clinicAccounts').where('clinicId', '==', clinicId).get();
  for (const d of existing.docs) {
    if (d.data().email !== email) throw new Error(`${clinic.name} already has a login (${d.data().email}). One login per clinic.`);
  }

  let user;
  try {
    user = await auth.getUserByEmail(email);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    user = await auth.createUser({ email, displayName: clinic.name, password: require('crypto').randomBytes(24).toString('base64url') });
  }
  if (user.customClaims?.role === 'superAdmin') throw new Error(`${email} is the Super Admin. Use another email.`);
  await auth.setCustomUserClaims(user.uid, { role: 'clinic', clinicId });

  const ts = admin.firestore.FieldValue.serverTimestamp();
  await db.collection('clinicAccounts').doc(user.uid).set(
    { email, clinicId, name: owner, status: 'invited', invitedAt: ts, createdAt: ts },
    { merge: true },
  );
  const billingRef = clinicRef.collection('private').doc('billing');
  if (!(await billingRef.get()).exists) {
    await billingRef.set({
      plan: 'pilot',
      planAfterPilot: 'basic',
      monthlyFee: 3000,
      billingDay: 1,
      pilotEndsAt: new Date(Date.now() + 30 * 86_400_000),
      paidUntil: null,
      ownerName: owner,
      ownerPhone: opts.phone && opts.phone !== true ? String(opts.phone) : clinic.phone ?? '',
      email,
      createdAt: ts,
    });
  }
  // Letters already used by seeded doctors are never handed out again (BW-7).
  const doctors = await db.collection('doctors').where('clinicId', '==', clinicId).get();
  const used = doctors.docs.map((d) => 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.indexOf(d.data().tokenPrefix ?? 'A'));
  await clinicRef.set({ nextDoctorLetter: used.length ? Math.max(...used) + 1 : 0, printFormat: clinic.printFormat ?? 'thermal80' }, { merge: true });

  const link = await auth.generatePasswordResetLink(email);
  console.log(`Clinic login ready on ${where}: ${clinic.name} → ${email} (uid ${user.uid})`);
  console.log(`Set the password here (one-time link):\n${link}`);
}

main().then(() => process.exit(0), (e) => {
  console.error(e.message ?? e);
  process.exit(1);
});
