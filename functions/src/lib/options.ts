import { CallableOptions } from 'firebase-functions/v2/https';

/** Only the production project enforces App Check (ARCHITECTURE.md §5–6). */
const isProd = process.env.GCLOUD_PROJECT === 'asani-prod';

export const REGION = 'asia-south1';

export const callableOptions: CallableOptions = {
  region: REGION,
  enforceAppCheck: isProd,
  minInstances: 0,
};
