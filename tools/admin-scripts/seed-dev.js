#!/usr/bin/env node
/**
 * Seeds demo clinics and doctors into Firestore (docs/06 §7, DATABASE.md §4–5).
 *
 *   node seed-dev.js                 # Firestore emulator (127.0.0.1:8080)
 *   node seed-dev.js --project dev   # asani-b2b17, needs serviceAccount.dev.json here
 *
 * There is deliberately no prod option (AGENTS.md §7).
 * Safe to run again: documents are overwritten with the same data.
 *
 * Clinic IDs match the app's demo seed (apps/patient_app/lib/data/demo/demo_seed.dart)
 * so demo doctors and tokens keep pointing at these clinics.
 * Doctor schedules are fixed (not "running now" like the in-app demo).
 * Dr. Kamran is on leave today (PKT) to show the "On leave" state.
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const DEV_PROJECT_ID = 'asani-b2b17';

const CLINICS = [
  { id: 'c_alshifa', name: 'Al-Shifa Clinic', area: 'Johar Town', city: 'Lahore', address: 'Main Boulevard, Johar Town', phone: '042-1234567', location: [31.4697, 74.2728] },
  { id: 'c_citycare', name: 'City Care Clinic', area: 'Gulberg', city: 'Lahore', address: 'MM Alam Road, Gulberg III', phone: '042-3576543', location: [31.5102, 74.3511] },
  { id: 'c_modeltown', name: 'Model Town Medical', area: 'Model Town', city: 'Lahore', address: 'Link Road, Model Town', phone: '042-3588812', location: [31.4835, 74.3239] },
  { id: 'c_dha', name: 'DHA Family Clinic', area: 'DHA Phase 5', city: 'Lahore', address: 'Sector C, DHA Phase 5', phone: '042-3712990', location: [31.4625, 74.4086] },
  { id: 'c_shifafamily', name: 'Shifa Family Clinic', area: 'Model Town', city: 'Lahore', address: 'Block K, Model Town', phone: '042-3591177', location: null },
  { id: 'c_rehman', name: 'Rehman Clinic', area: 'Iqbal Town', city: 'Lahore', address: 'Moon Market, Iqbal Town', phone: '042-3781100', location: null, status: 'suspended' },
  { id: 'c_clifton', name: 'Clifton Care Clinic', area: 'Clifton', city: 'Karachi', address: 'Block 5, Clifton', phone: '021-35871234', location: [24.8138, 67.03] },
  { id: 'c_capital', name: 'Capital Health Clinic', area: 'F-8 Markaz', city: 'Islamabad', address: 'F-8 Markaz', phone: '051-2287654', location: [33.7086, 73.0375] },
];

const DAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

/** Weekly schedule: the same hours every day except `off` days (null). */
function week(start, end, off = ['sun']) {
  return Object.fromEntries(DAYS.map((d) => [d, off.includes(d) ? null : { start, end }]));
}

/** Today as yyyy-MM-dd in Asia/Karachi (queue day IDs use PKT). */
function todayPkt() {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Karachi', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
}

const DOCTORS = [
  { id: 'd_ayesha', clinicId: 'c_alshifa', name: 'Dr. Ayesha Malik', speciality: 'General Physician', qualification: 'MBBS, FCPS', tokenPrefix: 'A', schedule: week('17:00', '21:00'), sortOrder: 1 },
  { id: 'd_kamran', clinicId: 'c_alshifa', name: 'Dr. Kamran Ahmed', speciality: 'Child Specialist', qualification: 'MBBS, DCH', tokenPrefix: 'B', schedule: week('10:00', '14:00'), onLeaveToday: true, sortOrder: 2 },
  { id: 'd_sana', clinicId: 'c_alshifa', name: 'Dr. Sana Riaz', speciality: 'Gynecologist', qualification: 'MBBS, FCPS', tokenPrefix: 'C', avgConsultMinutes: 15, maxTokensPerDay: 30, schedule: week('18:00', '21:00'), sortOrder: 3 },
  { id: 'd_imran', clinicId: 'c_citycare', name: 'Dr. Imran Qureshi', speciality: 'General Physician', tokenPrefix: 'A', schedule: week('16:00', '22:00'), sortOrder: 1 },
  { id: 'd_farah', clinicId: 'c_citycare', name: 'Dr. Farah Naz', speciality: 'Dermatologist', tokenPrefix: 'B', avgConsultMinutes: 12, schedule: week('11:00', '15:00'), sortOrder: 2 },
  { id: 'd_usman', clinicId: 'c_modeltown', name: 'Dr. Usman Tariq', speciality: 'ENT Specialist', tokenPrefix: 'A', schedule: week('16:00', '20:00', ['sat', 'sun']), sortOrder: 1 },
  { id: 'd_hina', clinicId: 'c_dha', name: 'Dr. Hina Shah', speciality: 'Pediatrician', tokenPrefix: 'A', schedule: week('09:00', '13:00', []), sortOrder: 1 },
  { id: 'd_bilal', clinicId: 'c_dha', name: 'Dr. Bilal Ahmed', speciality: 'General Physician', tokenPrefix: 'B', schedule: week('17:00', '21:00'), sortOrder: 2 },
  { id: 'd_nadia', clinicId: 'c_shifafamily', name: 'Dr. Nadia Karim', speciality: 'General Physician', tokenPrefix: 'A', schedule: week('17:00', '21:00'), sortOrder: 1 },
  { id: 'd_rehman', clinicId: 'c_rehman', name: 'Dr. Abdul Rehman', speciality: 'General Physician', tokenPrefix: 'A', schedule: week('17:00', '21:00'), sortOrder: 1 },
  { id: 'd_zara', clinicId: 'c_clifton', name: 'Dr. Zara Hussain', speciality: 'General Physician', tokenPrefix: 'A', schedule: week('17:00', '21:00'), sortOrder: 1 },
  { id: 'd_omar', clinicId: 'c_capital', name: 'Dr. Omar Farooq', speciality: 'Cardiologist', tokenPrefix: 'A', avgConsultMinutes: 15, schedule: week('16:00', '21:00'), sortOrder: 1 },
];

/** Words of name + area and their prefixes (min 2 letters), lowercase. */
function searchKeywords(...parts) {
  const out = new Set();
  for (const word of parts.join(' ').toLowerCase().split(/[^a-z0-9]+/)) {
    for (let i = 2; i <= word.length; i++) out.add(word.slice(0, i));
  }
  return [...out].sort();
}

function init() {
  const args = process.argv.slice(2);
  const pi = args.indexOf('--project');
  const target = pi >= 0 ? args[pi + 1] : 'emulator';

  if (target === 'emulator') {
    process.env.FIRESTORE_EMULATOR_HOST ||= '127.0.0.1:8080';
    admin.initializeApp({ projectId: DEV_PROJECT_ID });
    return `emulator (${process.env.FIRESTORE_EMULATOR_HOST})`;
  }
  if (target === 'dev') {
    const keyPath = path.join(__dirname, 'serviceAccount.dev.json');
    if (!fs.existsSync(keyPath)) {
      console.error(`Missing ${keyPath}\nFirebase console → Project settings → Service accounts → Generate new private key.\nNever commit this file.`);
      process.exit(1);
    }
    const key = JSON.parse(fs.readFileSync(keyPath, 'utf8'));
    if (key.project_id !== DEV_PROJECT_ID) {
      console.error(`serviceAccount.dev.json is for "${key.project_id}", expected "${DEV_PROJECT_ID}". Stopping.`);
      process.exit(1);
    }
    admin.initializeApp({ credential: admin.credential.cert(key), projectId: DEV_PROJECT_ID });
    return `dev project ${DEV_PROJECT_ID}`;
  }
  console.error(`Unknown target "${target}". Use no flag (emulator) or --project dev. There is no prod option.`);
  process.exit(1);
}

async function main() {
  const where = init();
  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = db.batch();

  for (const c of CLINICS) {
    batch.set(db.collection('clinics').doc(c.id), {
      name: c.name,
      nameLower: c.name.toLowerCase(),
      area: c.area,
      city: c.city,
      address: c.address,
      phone: c.phone,
      location: c.location ? new admin.firestore.GeoPoint(c.location[0], c.location[1]) : null,
      searchKeywords: searchKeywords(c.name, c.area),
      status: c.status || 'active',
      doctorCount: DOCTORS.filter((d) => d.clinicId === c.id).length,
      timezone: 'Asia/Karachi',
      printFormat: 'none',
      createdAt: now,
      updatedAt: now,
    });
  }

  const today = todayPkt();
  for (const d of DOCTORS) {
    batch.set(db.collection('doctors').doc(d.id), {
      clinicId: d.clinicId,
      name: d.name,
      speciality: d.speciality,
      qualification: d.qualification || null,
      avgConsultMinutes: d.avgConsultMinutes || 10,
      maxTokensPerDay: d.maxTokensPerDay || 40,
      bookingWindowDays: 7,
      tokenPrefix: d.tokenPrefix,
      schedule: d.schedule,
      onLeaveDates: d.onLeaveToday ? [today] : [],
      active: true,
      sortOrder: d.sortOrder,
      createdAt: now,
      updatedAt: now,
    });
  }

  await batch.commit();
  console.log(`Seeded ${CLINICS.length} clinics and ${DOCTORS.length} doctors into ${where} (leave date ${today}).`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
