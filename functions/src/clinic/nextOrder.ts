/**
 * PRD D-24: who "Next" calls.
 *
 * 1. A Skipped patient who checked in again (status `arrived` + `priorityAt`)
 *    is called right after the patient now with the doctor (oldest first).
 * 2. Otherwise the LOWEST token number among Booked and Arrived.
 *
 * If the pick is not Arrived, the receptionist must confirm first
 * ("A-7 has not arrived. Skip / Call anyway"). The 3-2-1 alerts keep counting
 * by token number (steps.ts), so they match this order.
 */

export interface NextCandidate {
  id: string;
  number: number;
  status: string;
  /** ms; set when a Skipped patient checks in again. */
  priorityAt?: number | null;
}

export function pickNext<T extends NextCandidate>(list: T[]): T | null {
  const priority = list
    .filter((t) => t.status === 'arrived' && typeof t.priorityAt === 'number')
    .sort((a, b) => (a.priorityAt as number) - (b.priorityAt as number) || a.number - b.number);
  if (priority.length > 0) return priority[0];
  const waiting = list.filter((t) => t.status === 'arrived' || t.status === 'booked').sort((a, b) => a.number - b.number);
  return waiting[0] ?? null;
}

/** True when Next must ask "not arrived: Skip / Call anyway" before calling [pick]. */
export function needsArrivalConfirm(pick: NextCandidate | null, confirmedTokenId: string | null | undefined): boolean {
  return !!pick && pick.status === 'booked' && pick.id !== confirmedTokenId;
}
