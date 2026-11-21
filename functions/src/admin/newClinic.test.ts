import { test } from 'node:test';
import assert from 'node:assert/strict';

import { readNewClinic } from './adminClinics';

const ok = {
  email: 'Noor@Asani.test',
  name: 'Noor Medical Centre',
  area: 'Gulberg',
  city: 'Lahore',
  address: 'Main Market, Gulberg II',
  phone: '042-35761234',
  location: { lat: 31.5204, lng: 74.3587 },
  printFormat: 'thermal80',
  planAfterPilot: 'basic',
  pilotDays: 30,
  monthlyFee: 3000,
  billingDay: 1,
  ownerName: 'Dr. Hina Qureshi',
  ownerPhone: '+923001112233',
};

test('New clinic: a complete form is read in full (email lower-cased)', () => {
  const c = readNewClinic(ok);
  assert.equal(c.email, 'noor@asani.test');
  assert.equal(c.ownerName, 'Dr. Hina Qureshi');
  assert.equal(c.billingDay, 1);
});

test('New clinic: any missing or bad field fails BEFORE a login is created', () => {
  for (const key of ['ownerName', 'ownerPhone', 'address', 'phone', 'monthlyFee', 'billingDay', 'pilotDays']) {
    const bad = { ...ok } as Record<string, unknown>;
    delete bad[key];
    assert.throws(() => readNewClinic(bad), /required|must be/, `missing ${key} must throw`);
  }
  assert.throws(() => readNewClinic({ ...ok, email: 'not-an-email' }));
  assert.throws(() => readNewClinic({ ...ok, billingDay: 31 }));
  assert.throws(() => readNewClinic({ ...ok, planAfterPilot: 'gold' }));
});
