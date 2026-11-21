/**
 * Queue notification steps (PRD F-06, N-1..N-4). Pure logic, mirrors the
 * app's `nextQueueNotification` in packages/asani_core/lib/src/queue_math.dart.
 */

/** Keys of `token.notified` (DATABASE.md §7), in order. */
export const STEP_KEYS = ['ahead3', 'ahead2', 'ahead1', 'yourTurn'] as const;
export type StepKey = (typeof STEP_KEYS)[number];

/** N-1: tokens with a lower number that are still waiting. */
export function patientsAhead(activeNumbers: number[], myNumber: number): number {
  return activeNumbers.filter((n) => n < myNumber).length;
}

/**
 * The step to send now, or null. `mark` is every step to record as done:
 * the sent step plus any earlier step that was skipped (N-3), so a skipped
 * step is never sent later. Each step is sent at most once (N-2).
 */
export function nextStep(
  status: string,
  ahead: number,
  notified: Partial<Record<StepKey, unknown>>,
  /** D-39: a patient is with the doctor now (a `called` token on this doctor/day). */
  someoneWithDoctor = false,
): { send: StepKey; mark: StepKey[] } | null {
  let current: StepKey | null = null;
  if (status === 'called') current = 'yourTurn';
  else if ((status === 'booked' || status === 'arrived') && ahead >= 1 && ahead <= 3) {
    current = (`ahead${ahead}` as StepKey);
  } else if ((status === 'booked' || status === 'arrived') && ahead === 0 && someoneWithDoctor) {
    // D-39: nobody waiting before me but someone is with the doctor → "You're next".
    current = 'ahead1';
  }
  if (!current || notified[current]) return null;
  const upTo = STEP_KEYS.indexOf(current);
  const mark = STEP_KEYS.slice(0, upTo + 1).filter((k) => !notified[k]);
  return { send: current, mark };
}

/** DESIGN.md §8 copy. Token labels use the doctor's letter (D-13). */
export function messageFor(step: StepKey, label: string, doctorName: string): { title: string; body: string } {
  switch (step) {
    case 'ahead3':
      return { title: '3 patients ahead of you', body: `Token ${label} · ${doctorName}. Please start heading to the clinic.` };
    case 'ahead2':
      return { title: '2 patients ahead of you', body: `Token ${label} · ${doctorName}` };
    case 'ahead1':
      return { title: "You're next", body: `Token ${label} · Please be at the reception.` };
    case 'yourTurn':
      return { title: 'Your turn now', body: `Token ${label} · Please go to ${doctorName}.` };
  }
}

/**
 * PRD D-35: exception to N-2. When a token that already got "Your turn now"
 * is skipped, the step is cleared once (and `turnRepeatUsed` set), so the
 * patient gets ONE more "Your turn now" when recalled. Never more than once
 * per token.
 */
/**
 * D-38: the same one-time repeat when the clinic undoes the Next that called
 * this token (the patient may already have "Your turn now").
 */
export const turnRepeatOnUndo = (t: { notified?: Partial<Record<StepKey, unknown>> | null; turnRepeatUsed?: boolean | null }) =>
  turnRepeatOnSkip(t);

export function turnRepeatOnSkip(t: { notified?: Partial<Record<StepKey, unknown>> | null; turnRepeatUsed?: boolean | null }): boolean {
  return !!t.notified?.yourTurn && !t.turnRepeatUsed;
}
