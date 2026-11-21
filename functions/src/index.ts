import { initializeApp } from 'firebase-admin/app';

initializeApp();

export { bookToken } from './booking/bookToken';
export { cancelToken } from './booking/cancelToken';
export { onTokenWrite, onQueueDayWrite } from './queue/triggers';
export { followUpReminders } from './followups/schedule';
export { autoCloseTokens } from './queue/schedule';
export { deleteAccount } from './account/deleteAccount';

// Clinic web (PRD-CLINIC-WEB): clinic login callables.
export { queueAction } from './clinic/queueAction';
export { clinicLookupPhone } from './clinic/phoneLookup';
export {
  clinicCreateWalkIn,
  clinicUpdatePatient,
  setFollowUp,
  saveDoctor,
  setDoctorActive,
  setDoctorLeave,
  cancelDoctorTokens,
  updateClinicSettings,
  logExport,
  clinicLoginTouch,
  clinicPasswordChanged,
} from './clinic/clinicData';
// Super admin callables + daily billing job.
export {
  adminCreateClinic,
  adminResendClinicInvite,
  adminSetClinicLogin,
  adminSetClinicStatus,
  adminChangePlan,
  adminExtendPilot,
  recordPayment,
  waiveInvoice,
  giveExtension,
  saveAdminSettings,
  billingJobs,
  adminRunBillingJobs,
} from './admin/adminClinics';
// Same doctor at two clinics (D-32, A-09).
export { adminLinkDoctors, adminMarkNotSame, adminUnlinkDoctor } from './admin/doctorLinks';
