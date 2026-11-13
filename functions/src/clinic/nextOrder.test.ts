import { test } from 'node:test';
import assert from 'node:assert/strict';

import { needsArrivalConfirm, pickNext } from './nextOrder';

const t = (id: string, number: number, status: string, priorityAt?: number) => ({ id, number, status, priorityAt });

test('D-24: lowest number among Booked and Arrived, not Arrived-first', () => {
  const list = [t('a7', 7, 'arrived'), t('a3', 3, 'booked'), t('a5', 5, 'arrived')];
  assert.equal(pickNext(list)?.id, 'a3');
});

test('D-24: On hold, Skipped, done tokens are never picked', () => {
  const list = [t('h1', 1, 'onHold'), t('s2', 2, 'skipped'), t('c3', 3, 'completed'), t('x4', 4, 'cancelled'), t('a6', 6, 'arrived')];
  assert.equal(pickNext(list)?.id, 'a6');
  assert.equal(pickNext([t('h1', 1, 'onHold')]), null);
});

test('D-24: a Skipped patient who checked in again goes first (oldest check-in first)', () => {
  const list = [t('b2', 2, 'booked'), t('r9', 9, 'arrived', 2000), t('r8', 8, 'arrived', 1000)];
  assert.equal(pickNext(list)?.id, 'r8');
});

test('D-24: ask "not arrived" only for a Booked pick that was not confirmed', () => {
  assert.equal(needsArrivalConfirm(t('a3', 3, 'booked'), null), true);
  assert.equal(needsArrivalConfirm(t('a3', 3, 'booked'), 'a3'), false);
  assert.equal(needsArrivalConfirm(t('a3', 3, 'booked'), 'a9'), true); // confirmation was for another token
  assert.equal(needsArrivalConfirm(t('a5', 5, 'arrived'), null), false);
  assert.equal(needsArrivalConfirm(null, null), false);
});
