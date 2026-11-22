import { test } from 'node:test';
import assert from 'node:assert/strict';

import { INBOX_DAYS, inboxEntry } from './inbox';

test('D-45: inbox entry keeps the push text and route, expires after 30 days', () => {
  const now = new Date('2026-11-23T10:00:00Z');
  const e = inboxEntry({ type: 'queue', title: "You're next", body: 'Token A-11 · Please be at the reception.', route: '/token/t1', tokenId: 't1' }, now);
  assert.equal(e.title, "You're next");
  assert.equal(e.route, '/token/t1');
  assert.equal(e.tokenId, 't1');
  assert.equal(e.expireAt.getTime() - now.getTime(), INBOX_DAYS * 24 * 3600 * 1000);
  assert.equal(inboxEntry({ type: 'followUp', title: 'x', body: 'y', route: '/book/c/d' }, now).tokenId, null);
});
