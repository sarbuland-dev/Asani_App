import { test } from 'node:test';
import assert from 'node:assert/strict';

import { cancelMessage, rebookRoute } from './cancelNotice';

test('D-23: cancel push copy with a reason', () => {
  assert.deepEqual(cancelMessage('A-5', 'Al-Shifa Clinic', 'Doctor on leave'), {
    title: 'Token A-5 cancelled by Al-Shifa Clinic',
    body: 'Doctor on leave. Tap to book another day.',
  });
});

test('D-23: no double full stop, and no reason is fine', () => {
  assert.equal(cancelMessage('B-2', 'X', 'Doctor busy. ').body, 'Doctor busy. Tap to book another day.');
  assert.equal(cancelMessage('B-2', 'X', null).body, 'Tap to book another day.');
  assert.equal(cancelMessage('B-2', 'X', '  ').body, 'Tap to book another day.');
});

test('D-23: tap opens booking for the same clinic, doctor and patient', () => {
  assert.equal(rebookRoute({ clinicId: 'c1', doctorId: 'd1', patientId: 'p1' }), '/book/c1/d1?patient=p1');
});
