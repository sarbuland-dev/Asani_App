import { HttpsError } from 'firebase-functions/v2/https';

/**
 * Booking error codes from DESIGN.md §7. The app reads `details.code` and
 * shows the matching message.
 */
export type BookingErrorCode =
  | 'clinic-unavailable'
  | 'doctor-unavailable'
  | 'session-ended'
  | 'tokens-full'
  | 'duplicate-token'
  | 'too-many-active';

export function bookingError(code: BookingErrorCode, extra: Record<string, unknown> = {}): HttpsError {
  return new HttpsError('failed-precondition', code, { code, ...extra });
}

export function badInput(message: string): HttpsError {
  return new HttpsError('invalid-argument', message);
}
