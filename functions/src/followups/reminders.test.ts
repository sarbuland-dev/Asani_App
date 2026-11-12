import { test } from 'node:test';
import assert from 'node:assert/strict';

import { addDays, decideReminder, reminderMessage } from './reminders';

const today = '2026-11-12';
const tomorrow = '2026-11-13';

test('day before: one reminder', () => {
  assert.equal(decideReminder({ status: 'pending', dueDate: tomorrow }, today, tomorrow), 'tomorrow');
  assert.equal(decideReminder({ status: 'pending', dueDate: tomorrow, remindersSent: 1 }, today, tomorrow), null);
});

test('due day: reminder until 2 were sent', () => {
  assert.equal(decideReminder({ status: 'pending', dueDate: today, remindersSent: 0 }, today, tomorrow), 'today');
  assert.equal(decideReminder({ status: 'pending', dueDate: today, remindersSent: 1 }, today, tomorrow), 'today');
  assert.equal(decideReminder({ status: 'pending', dueDate: today, remindersSent: 2 }, today, tomorrow), null);
});

test('past due → missed; booked/done are left alone; far future waits', () => {
  assert.equal(decideReminder({ status: 'pending', dueDate: '2026-11-10' }, today, tomorrow), 'missed');
  assert.equal(decideReminder({ status: 'booked', dueDate: today }, today, tomorrow), null);
  assert.equal(decideReminder({ status: 'done', dueDate: '2026-11-10' }, today, tomorrow), null);
  assert.equal(decideReminder({ status: 'pending', dueDate: '2026-11-20' }, today, tomorrow), null);
});

test('dates and copy', () => {
  assert.equal(addDays('2026-11-30', 1), '2026-12-01');
  assert.deepEqual(reminderMessage('tomorrow', 'Shazia Begum', 'Dr. Ayesha Malik', 'Al-Shifa Clinic'), {
    title: 'Follow-up visit tomorrow',
    body: 'Shazia Begum · Dr. Ayesha Malik, Al-Shifa Clinic. Tap to book.',
  });
});
