import { initializeApp } from 'firebase-admin/app';

initializeApp();

export { bookToken } from './booking/bookToken';
export { cancelToken } from './booking/cancelToken';
export { onTokenWrite, onQueueDayWrite } from './queue/triggers';
export { followUpReminders } from './followups/schedule';
export { deleteAccount } from './account/deleteAccount';
