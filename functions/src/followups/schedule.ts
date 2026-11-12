import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions/v2';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { REGION } from '../lib/options';
import { runFollowUpReminders } from './reminders';

/** Daily 09:00 Asia/Karachi (ARCHITECTURE.md §3.5). Runs after Blaze + deploy. */
export const followUpReminders = onSchedule(
  { schedule: '0 9 * * *', timeZone: 'Asia/Karachi', region: REGION },
  async () => {
    const log = await runFollowUpReminders(getFirestore(), getMessaging());
    logger.info('follow-up reminders', { count: log.length, log });
  },
);
