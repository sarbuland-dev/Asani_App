// Security rules tests for the clinic web (PRD-CLINIC-WEB §4, D-18, BW-6, BW-9).
// Run: npm run test:rules (needs Java for the Firestore emulator).
const { test, before, after, beforeEach } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, updateDoc, collection, query, where, getDocs } = require('firebase/firestore');

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-asani-rules',
    firestore: { rules: fs.readFileSync(path.join(__dirname, '../../../firestore.rules'), 'utf8') },
  });
});

after(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'clinics/c1'), { name: 'Clinic One', status: 'active' });
    await setDoc(doc(db, 'clinics/c1/private/billing'), { plan: 'basic', monthlyFee: 3000 });
    await setDoc(doc(db, 'clinics/c2/private/billing'), { plan: 'basic', monthlyFee: 3000 });
    await setDoc(doc(db, 'tokens/t1'), { clinicId: 'c1', doctorId: 'd1', date: '2026-11-13', bookedByUserId: 'patientUid', status: 'booked' });
    await setDoc(doc(db, 'tokens/t2'), { clinicId: 'c2', doctorId: 'd2', date: '2026-11-13', bookedByUserId: 'patientUid', status: 'booked' });
    await setDoc(doc(db, 'patients/p1'), { ownerUid: 'patientUid', phone: '+923000000001', clinicIds: ['c1'] });
    await setDoc(doc(db, 'patients/p2'), { ownerUid: 'patientUid', phone: '+923000000001', clinicIds: ['c2'] });
    await setDoc(doc(db, 'invoices/i1'), { clinicId: 'c1', status: 'unpaid' });
    await setDoc(doc(db, 'invoices/i2'), { clinicId: 'c2', status: 'unpaid' });
    await setDoc(doc(db, 'clinicAccounts/clinic1'), { clinicId: 'c1', email: 'a@c1.pk', status: 'active' });
    await setDoc(doc(db, 'activityLogs/l1'), { clinicId: 'c1', action: 'added doctor' });
    await setDoc(doc(db, 'activityLogs/l2'), { clinicId: 'c2', action: 'added doctor' });
  });
});

const clinic1 = () => env.authenticatedContext('clinic1', { role: 'clinic', clinicId: 'c1' }).firestore();
const admin = () => env.authenticatedContext('admin1', { role: 'superAdmin' }).firestore();
const patient = () => env.authenticatedContext('patientUid', { phone_number: '+923000000001' }).firestore();

test('clinic login reads its own tokens, not another clinic\'s', async () => {
  await assertSucceeds(getDoc(doc(clinic1(), 'tokens/t1')));
  await assertFails(getDoc(doc(clinic1(), 'tokens/t2')));
  await assertSucceeds(getDocs(query(collection(clinic1(), 'tokens'), where('clinicId', '==', 'c1'))));
  await assertFails(getDocs(query(collection(clinic1(), 'tokens'), where('clinicId', '==', 'c2'))));
});

test('clinic login cannot write tokens or days directly (BW-1)', async () => {
  await assertFails(updateDoc(doc(clinic1(), 'tokens/t1'), { status: 'arrived' }));
  await assertFails(setDoc(doc(clinic1(), 'doctors/d1/days/2026-11-13'), { sessionStatus: 'running' }));
});

test('clinic sees only patients who visited it (BW-6)', async () => {
  await assertSucceeds(getDoc(doc(clinic1(), 'patients/p1')));
  await assertFails(getDoc(doc(clinic1(), 'patients/p2')));
  await assertSucceeds(getDocs(query(collection(clinic1(), 'patients'), where('clinicIds', 'array-contains', 'c1'))));
});

test('billing is visible to the own clinic and the super admin only (BW-9)', async () => {
  await assertSucceeds(getDoc(doc(clinic1(), 'clinics/c1/private/billing')));
  await assertFails(getDoc(doc(clinic1(), 'clinics/c2/private/billing')));
  await assertFails(getDoc(doc(patient(), 'clinics/c1/private/billing')));
  await assertSucceeds(getDoc(doc(admin(), 'clinics/c2/private/billing')));
  await assertSucceeds(getDoc(doc(clinic1(), 'invoices/i1')));
  await assertFails(getDoc(doc(clinic1(), 'invoices/i2')));
});

test('super admin reads all tokens and logs; nobody writes logs', async () => {
  await assertSucceeds(getDoc(doc(admin(), 'tokens/t2')));
  await assertSucceeds(getDoc(doc(admin(), 'activityLogs/l2')));
  await assertFails(getDoc(doc(clinic1(), 'activityLogs/l2')));
  await assertFails(setDoc(doc(admin(), 'activityLogs/x'), { clinicId: 'c1' }));
});

test('clinic account doc: own login and super admin only', async () => {
  await assertSucceeds(getDoc(doc(clinic1(), 'clinicAccounts/clinic1')));
  await assertFails(getDoc(doc(patient(), 'clinicAccounts/clinic1')));
  await assertSucceeds(getDoc(doc(admin(), 'clinicAccounts/clinic1')));
});

test('a patient still reads only their own tokens', async () => {
  await assertSucceeds(getDoc(doc(patient(), 'tokens/t1')));
  await assertFails(getDoc(doc(env.authenticatedContext('someoneElse').firestore(), 'tokens/t1')));
});

// ---- D-32 / D-33: PMDC number and same-doctor suggestions ----
test('PMDC number: Super Admin reads it; clinic login and patients never do; nobody writes', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'doctors/d1'), { clinicId: 'c1', name: 'Dr. One', speciality: 'heart', hasPmdc: true });
    await setDoc(doc(db, 'doctors/d1/private/admin'), { pmdcNumber: '12345-P', clinicId: 'c1' });
  });
  await assertSucceeds(getDoc(doc(admin(), 'doctors/d1/private/admin')));
  await assertFails(getDoc(doc(clinic1(), 'doctors/d1/private/admin'))); // even its own doctor
  await assertFails(getDoc(doc(patient(), 'doctors/d1/private/admin')));
  await assertFails(setDoc(doc(clinic1(), 'doctors/d1/private/admin'), { pmdcNumber: '1' }));
  await assertSucceeds(getDoc(doc(patient(), 'doctors/d1'))); // public doctor doc has no number
  await assertFails(updateDoc(doc(clinic1(), 'doctors/d1'), { doctorGroupId: 'g1' }));
});

test('doctorLinkSuggestions: Super Admin only, no client writes', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'doctorLinkSuggestions/d1_d2'), { doctorIds: ['d1', 'd2'], clinicIds: ['c1', 'c2'], status: 'open', strength: 'strong' });
  });
  await assertSucceeds(getDoc(doc(admin(), 'doctorLinkSuggestions/d1_d2')));
  await assertSucceeds(getDocs(query(collection(admin(), 'doctorLinkSuggestions'), where('status', '==', 'open'))));
  await assertFails(getDoc(doc(clinic1(), 'doctorLinkSuggestions/d1_d2')));
  await assertFails(getDoc(doc(patient(), 'doctorLinkSuggestions/d1_d2')));
  await assertFails(updateDoc(doc(admin(), 'doctorLinkSuggestions/d1_d2'), { status: 'linked' }));
});
