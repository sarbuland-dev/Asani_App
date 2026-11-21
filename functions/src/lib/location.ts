import { HttpsError } from 'firebase-functions/v2/https';

/** Rough Pakistan box, to catch swapped or mistyped numbers (D-31). */
export function inPakistan(lat: number, lng: number): boolean {
  return lat >= 23.5 && lat <= 37.5 && lng >= 60.5 && lng <= 77.5;
}

/**
 * Clinic map location is REQUIRED (PRD D-31, BW-12): `{location: {lat, lng}}`.
 * Used by adminCreateClinic (A-04) and updateClinicSettings (C-13).
 */
export function readLocation(d: Record<string, unknown>): { lat: number; lng: number } {
  const l = d.location as Record<string, unknown> | null | undefined;
  const lat = Number(l?.lat), lng = Number(l?.lng);
  if (!l || !Number.isFinite(lat) || !Number.isFinite(lng)) {
    throw new HttpsError('invalid-argument', 'Add the clinic location on the map.');
  }
  if (!inPakistan(lat, lng)) throw new HttpsError('invalid-argument', 'The clinic location must be in Pakistan. Check the numbers.');
  return { lat, lng };
}
