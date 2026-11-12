import { test } from 'node:test';
import assert from 'node:assert/strict';

import { checkAvailability, withNumber, withoutNumber, DoctorData } from './rules';
import { pktNow, weekdayOf } from '../lib/dates';

const evening = { start: '17:00', end: '21:00' };
const doctor: DoctorData = {
  clinicId: 'c1',
  maxTokensPerDay: 3,
  bookingWindowDays: 7,
  schedule: { mon: evening, tue: evening, wed: evening, thu: evening, fri: evening, sat: evening, sun: null },
  onLeaveDates: ['2026-11-13'],
};
// 2026-11-12 is a Thursday.
const at = (minutes: number) => ({ date: '2026-11-12', minutes });

test('weekday and PKT date', () => {
  assert.equal(weekdayOf('2026-11-12'), 'thu');
  assert.equal(weekdayOf('2026-11-15'), 'sun');
  // 2026-11-11 20:30 UTC = 2026-11-12 01:30 PKT
  assert.deepEqual(pktNow(new Date('2026-11-11T20:30:00Z')), { date: '2026-11-12', minutes: 90 });
});

test('allowed before and during the session', () => {
  const base = { clinicStatus: 'active', doctor, day: undefined };
  assert.equal(checkAvailability({ ...base, date: '2026-11-12', now: at(10 * 60) }), null);
  assert.equal(checkAvailability({ ...base, date: '2026-11-12', now: at(18 * 60) }), null);
  assert.equal(checkAvailability({ ...base, date: '2026-11-14', now: at(23 * 60) }), null);
});

test('BR-1 clinic status', () => {
  const r = checkAvailability({ clinicStatus: 'suspended', doctor, date: '2026-11-12', day: undefined, now: at(600) });
  assert.equal(r, 'clinic-unavailable');
});

test('BR-2 leave, day off, inactive, outside the booking window', () => {
  const base = { clinicStatus: 'active', day: undefined, now: at(600) };
  assert.equal(checkAvailability({ ...base, doctor, date: '2026-11-13' }), 'doctor-unavailable'); // leave
  assert.equal(checkAvailability({ ...base, doctor, date: '2026-11-15' }), 'doctor-unavailable'); // Sunday
  assert.equal(checkAvailability({ ...base, doctor: { ...doctor, active: false }, date: '2026-11-12' }), 'doctor-unavailable');
  assert.equal(checkAvailability({ ...base, doctor, date: '2026-11-11' }), 'doctor-unavailable'); // past
  assert.equal(checkAvailability({ ...base, doctor, date: '2026-11-19' }), 'doctor-unavailable'); // 7 days ahead
});

test('BR-3 same day only until the session end', () => {
  const base = { clinicStatus: 'active', doctor, date: '2026-11-12' };
  assert.equal(checkAvailability({ ...base, day: undefined, now: at(21 * 60) }), 'session-ended');
  assert.equal(checkAvailability({ ...base, day: { sessionStatus: 'ended' }, now: at(18 * 60) }), 'session-ended');
});

test('BR-4 max tokens per day', () => {
  const r = checkAvailability({ clinicStatus: 'active', doctor, date: '2026-11-14', day: { bookedCount: 3 }, now: at(600) });
  assert.equal(r, 'tokens-full');
});

test('activeNumbers stay sorted and unique', () => {
  assert.deepEqual(withNumber([1, 3], 2), [1, 2, 3]);
  assert.deepEqual(withNumber([1, 2], 2), [1, 2]);
  assert.deepEqual(withNumber(undefined, 1), [1]);
  assert.deepEqual(withoutNumber([1, 2, 3], 2), [1, 3]);
});
