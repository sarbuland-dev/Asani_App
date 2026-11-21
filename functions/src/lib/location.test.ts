import { test } from 'node:test';
import assert from 'node:assert/strict';

import { readLocation } from './location';

test('D-31 / BW-12: clinic location is required and must be in Pakistan', () => {
  assert.deepEqual(readLocation({ location: { lat: 31.47, lng: 74.27 } }), { lat: 31.47, lng: 74.27 });
  assert.throws(() => readLocation({}), /Add the clinic location/);
  assert.throws(() => readLocation({ location: null }), /Add the clinic location/);
  assert.throws(() => readLocation({ location: { lat: 'x', lng: 74 } }), /Add the clinic location/);
  assert.throws(() => readLocation({ location: { lat: 74.27, lng: 31.47 } }), /in Pakistan/);
});
