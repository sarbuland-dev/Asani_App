// Security rules tests for users/{uid} (docs/07). Run: npm run test:rules
// Uses a "demo-" project ID, so nothing can reach a real Firebase project.
const { test, before, after, beforeEach } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, updateDoc, serverTimestamp } = require('firebase/firestore');

const PHONE = '+923000000001';
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
    await setDoc(doc(ctx.firestore(), 'users/u1'), {
      phone: PHONE,
      name: 'Test User',
      role: 'patient',
      city: 'Lahore',
      selfPatientId: 'p1',
      queueAlertsEnabled: true,
    });
  });
});

const me = () => env.authenticatedContext('u1', { phone_number: PHONE }).firestore();
const other = () => env.authenticatedContext('u2', { phone_number: '+923000000002' }).firestore();

test('owner can turn queue alerts off and on (D-18)', async () => {
  await assertSucceeds(updateDoc(doc(me(), 'users/u1'), { queueAlertsEnabled: false, updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(me(), 'users/u1'), { queueAlertsEnabled: true }));
});

test('queueAlertsEnabled must be a bool', async () => {
  await assertFails(updateDoc(doc(me(), 'users/u1'), { queueAlertsEnabled: 'no' }));
});

test('another user cannot change my queue alerts', async () => {
  await assertFails(updateDoc(doc(other(), 'users/u1'), { queueAlertsEnabled: false }));
});

test('role and selfPatientId still cannot be changed', async () => {
  await assertFails(updateDoc(doc(me(), 'users/u1'), { role: 'admin' }));
  await assertFails(updateDoc(doc(me(), 'users/u1'), { selfPatientId: 'p2' }));
});

test('existing fields still work: name and city', async () => {
  await assertSucceeds(updateDoc(doc(me(), 'users/u1'), { name: 'New Name', city: 'Karachi' }));
  await assertFails(updateDoc(doc(me(), 'users/u1'), { name: 'X' }));
});

// ---- D-43: in-app notifications list ----
test('notifications: owner reads own list, nobody writes; seen time is a timestamp', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users/u1/notifications/n1'), { title: "You're next", route: '/token/t1' });
  });
  await assertSucceeds(getDoc(doc(me(), 'users/u1/notifications/n1')));
  await assertFails(getDoc(doc(other(), 'users/u1/notifications/n1')));
  await assertFails(setDoc(doc(me(), 'users/u1/notifications/n2'), { title: 'fake' }));
  await assertSucceeds(updateDoc(doc(me(), 'users/u1'), { notificationsSeenAt: new Date() }));
  await assertFails(updateDoc(doc(me(), 'users/u1'), { notificationsSeenAt: 'yesterday' }));
});
