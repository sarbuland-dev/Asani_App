import { BookingErrorCode } from '../lib/errors';
import { PktNow, daysBetween, hhmmToMinutes, weekdayOf } from '../lib/dates';

/** PRD F-04. Active = booked, arrived, called, onHold (BR-5). */
export const ACTIVE_STATUSES = ['booked', 'arrived', 'called', 'onHold'];
/** Counted as "ahead" in the queue (DATABASE.md §7). */
export const WAITING_STATUSES = ['booked', 'arrived', 'onHold'];
/** Patient may cancel only while booked or arrived (PRD F-05). */
export const CANCELLABLE_STATUSES = ['booked', 'arrived'];
/** BR-1 */
export const BOOKABLE_CLINIC_STATUSES = ['pilot', 'active', 'grace'];
/** BR-6 */
export const MAX_ACTIVE_TOKENS_PER_ACCOUNT = 5;

export interface DoctorData {
  clinicId: string;
  active?: boolean;
  maxTokensPerDay?: number;
  bookingWindowDays?: number;
  schedule?: Record<string, { start: string; end: string } | null>;
  onLeaveDates?: string[];
}

export interface DayData {
  sessionStatus?: string;
  bookedCount?: number;
}

/**
 * BR-1..BR-4 for one doctor and date. Returns the error code, or null when
 * booking is allowed. Same order as the app's `availabilityFor`.
 */
export function checkAvailability(params: {
  clinicStatus: string;
  doctor: DoctorData;
  date: string;
  day: DayData | undefined;
  now: PktNow;
}): BookingErrorCode | null {
  const { clinicStatus, doctor, date, day, now } = params;
  if (!BOOKABLE_CLINIC_STATUSES.includes(clinicStatus)) return 'clinic-unavailable';

  // Only today .. today + bookingWindowDays - 1 (PRD F-04 step 2).
  const offset = daysBetween(now.date, date);
  if (offset < 0 || offset >= (doctor.bookingWindowDays ?? 7)) return 'doctor-unavailable';

  if (doctor.active === false) return 'doctor-unavailable';
  if ((doctor.onLeaveDates ?? []).includes(date)) return 'doctor-unavailable';
  const schedule = doctor.schedule?.[weekdayOf(date)] ?? null;
  if (!schedule) return 'doctor-unavailable';

  if ((day?.bookedCount ?? 0) >= (doctor.maxTokensPerDay ?? 40)) return 'tokens-full';

  if (offset === 0 && (day?.sessionStatus === 'ended' || now.minutes >= hhmmToMinutes(schedule.end))) {
    return 'session-ended';
  }
  return null;
}

/** activeNumbers after adding or removing one number: sorted, no duplicates. */
export function withNumber(list: number[] | undefined, n: number): number[] {
  return [...new Set([...(list ?? []), n])].sort((a, b) => a - b);
}

export function withoutNumber(list: number[] | undefined, n: number): number[] {
  return (list ?? []).filter((x) => x !== n);
}
