import { test } from 'node:test';
import assert from 'node:assert/strict';

import { messageFor, nextStep, patientsAhead } from './steps';

test('N-1 patients ahead = lower waiting numbers', () => {
  assert.equal(patientsAhead([3, 4, 6, 9], 6), 2);
  assert.equal(patientsAhead([], 6), 0);
});

test('steps 3, 2, 1 and your turn, each once (N-2)', () => {
  assert.deepEqual(nextStep('booked', 3, {}), { send: 'ahead3', mark: ['ahead3'] });
  assert.deepEqual(nextStep('booked', 2, { ahead3: 1 }), { send: 'ahead2', mark: ['ahead2'] });
  assert.deepEqual(nextStep('arrived', 1, { ahead3: 1, ahead2: 1 }), { send: 'ahead1', mark: ['ahead1'] });
  assert.deepEqual(nextStep('called', 0, { ahead3: 1, ahead2: 1, ahead1: 1 }), { send: 'yourTurn', mark: ['yourTurn'] });
  assert.equal(nextStep('booked', 2, { ahead3: 1, ahead2: 1 }), null);
});

test('N-3 a jump sends only the latest step and marks the skipped ones', () => {
  assert.deepEqual(nextStep('booked', 1, {}), { send: 'ahead1', mark: ['ahead3', 'ahead2', 'ahead1'] });
  assert.deepEqual(nextStep('called', 0, { ahead3: 1 }), { send: 'yourTurn', mark: ['ahead2', 'ahead1', 'yourTurn'] });
});

test('nothing for 4+ ahead, 0 ahead while waiting, or closed tokens', () => {
  assert.equal(nextStep('booked', 4, {}), null);
  assert.equal(nextStep('booked', 0, {}), null);
  assert.equal(nextStep('onHold', 2, {}), null);
  assert.equal(nextStep('cancelled', 1, {}), null);
  assert.equal(nextStep('completed', 0, {}), null);
});

test('DESIGN copy', () => {
  assert.deepEqual(messageFor('ahead1', 'A-11', 'Dr. Ayesha Malik'), {
    title: "You're next",
    body: 'Token A-11 · Please be at the reception.',
  });
  assert.equal(messageFor('yourTurn', 'A-11', 'Dr. Ayesha Malik').body, 'Token A-11 · Please go to Dr. Ayesha Malik.');
});
