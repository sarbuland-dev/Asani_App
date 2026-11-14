import { test } from 'node:test';
import assert from 'node:assert/strict';

import { canRecordPayment, paymentDate } from './adminClinics';

test('a payment can be recorded only once, on an open invoice', () => {
  assert.equal(canRecordPayment('unpaid'), true);
  assert.equal(canRecordPayment('overdue'), true);
  assert.equal(canRecordPayment('paid'), false); // second click
  assert.equal(canRecordPayment('waived'), false);
  assert.equal(canRecordPayment(''), false);
});

test('payment date: client value is checked', () => {
  const now = new Date('2026-11-14T10:00:00Z');
  assert.equal(paymentDate(undefined, now), now);
  assert.equal(paymentDate('2026-11-10', now), now);
  assert.equal(paymentDate(Number.NaN, now), now);
  assert.equal(paymentDate(now.getTime() + 86_400_000, now), now); // future
  assert.equal(paymentDate(new Date('2019-01-01').getTime(), now), now); // too old
  const ok = new Date('2026-11-10T08:00:00Z');
  assert.equal(paymentDate(ok.getTime(), now).getTime(), ok.getTime());
});
