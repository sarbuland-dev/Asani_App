/**
 * Business dates are Asia/Karachi (ARCHITECTURE.md §7). Never use the
 * server's time zone for queue day IDs.
 */
const TZ = 'Asia/Karachi';

export const WEEKDAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'] as const;
export type WeekdayKey = (typeof WEEKDAYS)[number];

export interface PktNow {
  /** yyyy-MM-dd in PKT */
  date: string;
  /** minutes since PKT midnight */
  minutes: number;
}

export function pktNow(now: Date = new Date()): PktNow {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(now);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? '00';
  return {
    date: `${get('year')}-${get('month')}-${get('day')}`,
    minutes: Number(get('hour')) * 60 + Number(get('minute')),
  };
}

export const DAY_ID = /^\d{4}-\d{2}-\d{2}$/;

/** Weekday of a yyyy-MM-dd date (the date itself has no time zone). */
export function weekdayOf(date: string): WeekdayKey {
  const [y, m, d] = date.split('-').map(Number);
  const js = new Date(Date.UTC(y, m - 1, d)).getUTCDay(); // 0 = Sunday
  return WEEKDAYS[(js + 6) % 7];
}

/** Whole days from `from` to `to` (both yyyy-MM-dd). */
export function daysBetween(from: string, to: string): number {
  const ms = (s: string) => {
    const [y, m, d] = s.split('-').map(Number);
    return Date.UTC(y, m - 1, d);
  };
  return Math.round((ms(to) - ms(from)) / 86_400_000);
}

export function hhmmToMinutes(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
}
