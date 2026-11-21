import { test } from 'node:test';
import assert from 'node:assert/strict';

import { skipMessage } from './skipNotice';
import { turnRepeatOnSkip } from './steps';

test('D-34: skip push copy', () => {
  assert.deepEqual(skipMessage('A-7'), {
    title: 'You missed your turn',
    body: 'Token A-7 · Go to reception to be called next.',
  });
});

test('D-35: a skip after "Your turn now" allows one repeat, only once per token', () => {
  assert.equal(turnRepeatOnSkip({ notified: { ahead1: 1, yourTurn: 2 } }), true);
  assert.equal(turnRepeatOnSkip({ notified: { ahead1: 1, yourTurn: 2 }, turnRepeatUsed: true }), false);
});

test('D-35: a skip before the patient was called needs no repeat', () => {
  assert.equal(turnRepeatOnSkip({ notified: { ahead1: 1 } }), false);
  assert.equal(turnRepeatOnSkip({}), false);
});
