import { test } from 'node:test';
import assert from 'node:assert/strict';

import { LOOKUP_LIMIT, LOOKUP_WINDOW_MS, ageOf, nextRateWindow } from './phoneLookup';

test('D-22 rate limit: first lookup opens a window', () => {
  assert.deepEqual(nextRateWindow(null, 1000), { windowStart: 1000, count: 1 });
});

test('D-22 rate limit: counts up to the limit, then blocks', () => {
  let w = nextRateWindow(null, 0)!;
  for (let i = 1; i < LOOKUP_LIMIT; i++) w = nextRateWindow(w, i)!;
  assert.equal(w.count, LOOKUP_LIMIT);
  assert.equal(nextRateWindow(w, LOOKUP_LIMIT), null);
});

test('D-22 rate limit: a new window starts after the window time', () => {
  const full = { windowStart: 0, count: LOOKUP_LIMIT };
  assert.deepEqual(nextRateWindow(full, LOOKUP_WINDOW_MS), { windowStart: LOOKUP_WINDOW_MS, count: 1 });
});

test('D-22: age from birth year, null when unknown', () => {
  assert.equal(ageOf(1990, 2026), 36);
  assert.equal(ageOf(null, 2026), null);
  assert.equal(ageOf(undefined, 2026), null);
});
