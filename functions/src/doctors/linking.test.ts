import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  doctorNameKey, isSpecialityKey, isValidPmdc, legacySpeciality, normalisePmdc, pairIdOf, suggestionChange, unlinkPlan,
} from './linking';

test('D-31: speciality keys and old free text', () => {
  assert.equal(isSpecialityKey('heart'), true);
  assert.equal(isSpecialityKey('Cardiologist'), false);
  assert.equal(legacySpeciality('Cardiologist'), 'heart');
  assert.equal(legacySpeciality('General Physician'), 'generalPhysician');
  assert.equal(legacySpeciality('ENT Specialist'), 'ent');
  assert.equal(legacySpeciality('Pediatrician'), 'child');
  assert.equal(legacySpeciality('Gynecologist'), 'womensHealth');
  assert.equal(legacySpeciality('Dermatologist'), 'skin');
  assert.equal(legacySpeciality('Child Specialist'), 'child');
  assert.equal(legacySpeciality('Astrologer'), null);
  assert.equal(legacySpeciality(''), null);
});

test('D-32: PMDC format and name key', () => {
  assert.equal(isValidPmdc('12345'), true);
  assert.equal(isValidPmdc(' 12345-p '), true);
  assert.equal(normalisePmdc(' 12345-p '), '12345-P');
  assert.equal(isValidPmdc('abc'), false);
  assert.equal(isValidPmdc('12-34-5'), false);
  assert.equal(doctorNameKey('Dr. Ayesha  Malik.'), 'ayesha malik');
  assert.equal(doctorNameKey('doctor Ayesha Malik'), 'ayesha malik');
  assert.equal(pairIdOf('d2', 'd1'), 'd1_d2');
});

test('D-32/D-33: suggestions are created, upgraded, never revived', () => {
  assert.equal(suggestionChange(null, false), 'create');
  assert.equal(suggestionChange({ status: 'open', strength: 'weak' }, true), 'upgrade');
  assert.equal(suggestionChange({ status: 'open', strength: 'weak' }, false), null);
  assert.equal(suggestionChange({ status: 'open', strength: 'strong' }, true), null);
  assert.equal(suggestionChange({ status: 'notSame', strength: 'weak' }, true), null);
  assert.equal(suggestionChange({ status: 'unlinked', strength: 'strong' }, true), null);
  assert.equal(suggestionChange({ status: 'linked', strength: 'strong' }, true), null);
});

test('D-33: unlink clears the last member of a group too', () => {
  assert.deepEqual(unlinkPlan('a', ['a', 'b']), ['a', 'b']);
  assert.deepEqual(unlinkPlan('a', ['a', 'b', 'c']), ['a']);
});
