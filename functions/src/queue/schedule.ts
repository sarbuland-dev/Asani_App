import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { REGION } from '../lib/options';
import { runAutoClose } from './autoClose';

/** PRD D-21: daily 03:00 Asia/Karachi, closes open tokens from before today. Runs after Blaze + deploy. */
export const autoCloseTokens = onSchedule(
  { schedule: '0 3 * * *', timeZone: 'Asia/Karachi', region: REGION },
  async () => {
    const log = await runAutoClose(getFirestore());
    logger.info('auto-closed tokens', { count: log.length, log });
  },
);
