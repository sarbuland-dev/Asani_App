import { test } from 'node:test';
import assert from 'node:assert/strict';

import { decideAutoClose } from './autoClose';

const today = '2026-11-15';

test('D-21: past-day Booked → No-show', () => {
  assert.equal(decideAutoClose('booked', '2026-11-14', today), 'noShow');
  assert.equal(decideAutoClose('booked', '2026-10-01', today), 'noShow');
});

test('D-21: past-day Arrived / On hold / Called → Completed', () => {
  assert.equal(decideAutoClose('arrived', '2026-11-14', today), 'completed');
  assert.equal(decideAutoClose('onHold', '2026-11-14', today), 'completed');
  assert.equal(decideAutoClose('called', '2026-11-14', today), 'completed');
});

test("D-21: today's and future tokens are never touched (clinics run past midnight)", () => {
  for (const s of ['booked', 'arrived', 'onHold', 'called']) {
    assert.equal(decideAutoClose(s, today, today), null);
    assert.equal(decideAutoClose(s, '2026-11-16', today), null);
  }
});

test('D-21: closed statuses are left as they are', () => {
  for (const s of ['completed', 'cancelled', 'noShow', 'skipped']) {
    assert.equal(decideAutoClose(s, '2026-11-14', today), null);
  }
});
