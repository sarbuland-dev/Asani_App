import { test } from 'node:test';
import assert from 'node:assert/strict';

import { LOCK_MS, PIN, afterTry, hashPin, isLocked, pinMatches } from './pinRules';

test('D-41: PIN is 4 digits, stored hashed with a salt', () => {
  assert.equal(PIN.test('1234'), true);
  assert.equal(PIN.test('12345'), false);
  assert.equal(PIN.test('12a4'), false);
  const h = hashPin('1234');
  assert.notEqual(h.hash, '1234');
  assert.equal(pinMatches('1234', h.salt, h.hash), true);
  assert.equal(pinMatches('4321', h.salt, h.hash), false);
  assert.notEqual(hashPin('1234').salt, h.salt); // new salt each time
});

test('D-41: 5 wrong tries lock it for 15 minutes; a right PIN resets the count', () => {
  let s = { failed: 0, lockedUntil: null as number | null };
  const now = 1_000_000;
  for (let i = 0; i < 4; i++) s = afterTry(s, false, now);
  assert.equal(s.failed, 4);
  assert.equal(isLocked(s, now), false);
  s = afterTry(s, false, now);
  assert.equal(isLocked(s, now), true);
  assert.equal(isLocked(s, now + LOCK_MS + 1), false);
  assert.deepEqual(afterTry({ failed: 3, lockedUntil: null }, true, now), { failed: 0, lockedUntil: null });
});
