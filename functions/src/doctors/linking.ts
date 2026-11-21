/**
 * Doctor search + same-doctor linking (PRD D-31..D-33, DATABASE §5, §8b).
 * Pure helpers, no Firestore: mirrors packages/asani_core speciality.dart and
 * doctor_search.dart so the app, the web and the backend agree.
 */

/** Fixed speciality keys (PRD F-13). Firestore stores one of these. */
export const SPECIALITY_KEYS = [
  'generalPhysician', 'child', 'heart', 'teeth', 'skin', 'womensHealth', 'eye', 'ent', 'bones',
  'diabetes', 'stomach', 'chest', 'kidney', 'brain', 'mentalHealth', 'physio', 'other',
] as const;
export type SpecialityKey = (typeof SPECIALITY_KEYS)[number];

export function isSpecialityKey(v: unknown): v is SpecialityKey {
  return typeof v === 'string' && (SPECIALITY_KEYS as readonly string[]).includes(v);
}

/** Exact labels / terms of the fixed list, lower case → key. */
const EXACT: Record<string, SpecialityKey> = {
  'general physician': 'generalPhysician', 'child specialist': 'child',
  heart: 'heart', cardiologist: 'heart', teeth: 'teeth', dentist: 'teeth', skin: 'skin', dermatologist: 'skin',
  'women s health': 'womensHealth', gynecologist: 'womensHealth', gynaecologist: 'womensHealth',
  eye: 'eye', 'eye specialist': 'eye', 'ear nose throat': 'ent', ent: 'ent', 'bones joints': 'bones',
  orthopedic: 'bones', 'diabetes hormones': 'diabetes', endocrinologist: 'diabetes', 'stomach liver': 'stomach',
  gastro: 'stomach', 'chest lungs': 'chest', pulmonologist: 'chest', kidney: 'kidney', nephrologist: 'kidney',
  'brain nerves': 'brain', neurologist: 'brain', 'mental health': 'mentalHealth', psychiatrist: 'mentalHealth',
  physiotherapy: 'physio', other: 'other',
};

/** Word starts for old free text (D-33 migration). Order matters: first match wins. */
const WORDS: [string, SpecialityKey][] = [
  ['general physician', 'generalPhysician'], ['gp', 'generalPhysician'], ['family physician', 'generalPhysician'],
  ['family medicine', 'generalPhysician'], ['physician', 'generalPhysician'],
  ['child', 'child'], ['pediatric', 'child'], ['paediatric', 'child'],
  ['cardio', 'heart'], ['dent', 'teeth'], ['derma', 'skin'], ['gyn', 'womensHealth'], ['obstetric', 'womensHealth'],
  ['women', 'womensHealth'], ['eye', 'eye'], ['ophthal', 'eye'], ['ent', 'ent'], ['ortho', 'bones'], ['bone', 'bones'],
  ['endocrin', 'diabetes'], ['diabet', 'diabetes'], ['gastro', 'stomach'], ['liver', 'stomach'], ['hepat', 'stomach'],
  ['pulmo', 'chest'], ['chest', 'chest'], ['lung', 'chest'], ['nephro', 'kidney'], ['kidney', 'kidney'],
  ['urolog', 'kidney'], ['neuro', 'brain'], ['brain', 'brain'], ['psychiat', 'mentalHealth'],
  ['psycholog', 'mentalHealth'], ['mental', 'mentalHealth'], ['physio', 'physio'],
];

/** Old free-text speciality → key, or null when unknown (the migration sets `other` + flag). */
export function legacySpeciality(text: unknown): SpecialityKey | null {
  if (isSpecialityKey(text)) return text;
  const t = String(text ?? '').toLowerCase().replace(/[^a-z ]/g, ' ').replace(/\s+/g, ' ').trim();
  if (!t) return null;
  if (EXACT[t]) return EXACT[t];
  const parts = t.split(' ');
  for (const [w, key] of WORDS) {
    if (t === w || t.startsWith(`${w} `)) return key;
    if (w.length > 2 && parts.some((p) => p.startsWith(w))) return key;
  }
  return null;
}

/** "12345-p " → "12345-P" (D-32). */
export function normalisePmdc(raw: string): string {
  return raw.replace(/\s+/g, '').toUpperCase();
}

/** Loose check: 3–7 digits, optional "-" + 1–2 letters. */
export function isValidPmdc(raw: string): boolean {
  return /^\d{3,7}(-[A-Z]{1,2})?$/.test(normalisePmdc(raw));
}

/** "Dr. Ayesha  Malik." → "ayesha malik" (weak match). */
export function doctorNameKey(name: string): string {
  return name.toLowerCase().replace(/[^a-z ]/g, ' ').replace(/\s+/g, ' ').trim().replace(/^(dr|doctor) /, '');
}

export function pairIdOf(a: string, b: string): string {
  return [a, b].sort().join('_');
}

export type Strength = 'strong' | 'weak';
export type LinkStatus = 'open' | 'linked' | 'notSame' | 'unlinked';

/**
 * What to write for a candidate pair (DATABASE §8b): a new open suggestion,
 * an upgrade weak → strong, or nothing. Decided pairs (linked, notSame,
 * unlinked) are never touched: Not the same and Unlink are remembered (D-33).
 */
export function suggestionChange(
  existing: { status: LinkStatus; strength: Strength } | null,
  strong: boolean,
): 'create' | 'upgrade' | null {
  if (!existing) return 'create';
  if (existing.status !== 'open') return null;
  return strong && existing.strength === 'weak' ? 'upgrade' : null;
}

/**
 * Unlink (D-33): the records that lose their group. The unlinked one always;
 * the last one left too, since a group of one means nothing.
 */
export function unlinkPlan(doctorId: string, groupMembers: string[]): string[] {
  const rest = groupMembers.filter((x) => x !== doctorId);
  return rest.length === 1 ? [doctorId, rest[0]] : [doctorId];
}
