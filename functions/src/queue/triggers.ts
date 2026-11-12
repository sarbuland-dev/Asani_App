import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';

import { REGION } from '../lib/options';
import { WAITING_STATUSES } from '../booking/rules';
import { evaluateQueue } from './notify';

/**
 * ARCHITECTURE.md §5 triggers. They run once the project is on Blaze and
 * functions are deployed; until then bookToken, cancelToken and queue-sim
 * call the same evaluateQueue directly (PRD D-17). Both are idempotent.
 */

/** Recompute day.activeNumbers from the tokens, then re-evaluate notifications. */
export const onTokenWrite = onDocumentWritten({ document: 'tokens/{tokenId}', region: REGION }, async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  const t = after ?? before;
  if (!t) return;
  // Only status changes matter (notified/updatedAt writes would loop otherwise).
  if (before && after && before.status === after.status) return;

  const db = getFirestore();
  const tokens = await db
    .collection('tokens')
    .where('doctorId', '==', t.doctorId)
    .where('date', '==', t.date)
    .where('status', 'in', WAITING_STATUSES)
    .get();
  const activeNumbers = tokens.docs.map((d) => d.data().number as number).sort((a, b) => a - b);
  await db
    .collection('doctors')
    .doc(t.doctorId)
    .collection('days')
    .doc(t.date)
    .set({ activeNumbers, waitingCount: activeNumbers.length }, { merge: true });

  const sent = await evaluateQueue(db, getMessaging(), t.doctorId, t.date);
  if (sent.length) logger.info('queue notifications', { doctorId: t.doctorId, date: t.date, sent });
});

/** currentToken / sessionStatus changes can also move people forward. */
export const onQueueDayWrite = onDocumentWritten(
  { document: 'doctors/{doctorId}/days/{date}', region: REGION },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after) return;
    if (before && JSON.stringify(before.activeNumbers) === JSON.stringify(after.activeNumbers) && before.currentToken === after.currentToken) {
      return;
    }
    const sent = await evaluateQueue(getFirestore(), getMessaging(), event.params.doctorId, event.params.date);
    if (sent.length) logger.info('queue notifications', { ...event.params, sent });
  },
);
