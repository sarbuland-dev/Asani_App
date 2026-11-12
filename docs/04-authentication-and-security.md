# 04 — Authentication and Security

How users log in, who can read/write what, and how patient data is protected.

---

## 1. Identity model

| Who | How they log in | Identity | Role source |
|---|---|---|---|
| **Patient app user** (account owner) | Phone OTP (Firebase Phone Auth) | Auth `uid` + verified `phone_number` | No custom claim → treated as patient |
| Patient profile (mother, child…) | Does not log in | `patients/{patientId}` | n/a |
| Clinic staff | **Phase 2:** phone/username + password (decided) | Auth `uid` | Custom claims `{role, clinicId, doctorId?}` set only by Admin SDK |
| Super admin | Phase 3 (TBD) | Auth `uid` | Custom claim `{role: "superAdmin"}` |

**Rule:** roles are **never** read from Firestore documents. Only custom claims (`request.auth.token.role`) count, because only the server can set them.

---

## 2. Patient login flow (F-01)

1. App validates the number: `+92` + 10 digits starting with `3`.
2. `FirebaseAuth.verifyPhoneNumber` (Android: auto-retrieval / instant verification; iOS: silent APNs or reCAPTCHA fallback).
3. User enters OTP → `signInWithCredential`.
4. App calls `linkPatientProfiles()`:
   - finds `patients` where `phone == auth.phone_number` and `ownerUid == null`
   - sets `ownerUid = uid` on them and `patientOwnerUid = uid` on their tokens
   - returns the count (the app can show "We found 2 family members from your clinic visits")
5. First login: create `users/{uid}` and the Self profile **in one batch**.
6. Register the device FCM token in `users/{uid}/devices/{deviceId}`.

Logout: delete this device's doc from `devices`, then `FirebaseAuth.signOut()`.

### Staff login (Phase 2, reference only)
Decided: phone/username + password. Likely implementation: Firebase Email/Password provider with an internal email such as `<username>@staff.asani.app`, accounts created by the admin script with claims. **Do not build in Phase 1.**

---

## 3. OTP abuse and cost protection

Phone OTP SMS costs money and is a common abuse target.

- **SMS region policy:** allow **Pakistan only** (Auth → Settings).
- **App Check** enforced for Auth (where supported), Firestore and Functions in production.
- App-side: resend disabled for 60 s; max 3 resends per session.
- Firebase default rate limits per number/IP stay on.
- **Budget alerts** on both projects.
- Dev: use **test phone numbers** and the Auth emulator; never test with real SMS in loops.

---

## 4. App Check

| Platform | Provider |
|---|---|
| Android | Play Integrity |
| iOS | App Attest (DeviceCheck fallback) |
| Dev builds / emulators | Debug provider (register debug token in console) |

Callables use `enforceAppCheck: true` in prod. Enable Firestore App Check enforcement only after the app version with App Check is widely installed (watch the console metrics first).

---

## 5. Firestore security rules (Phase 1)

`firestore.rules`:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // ---------- helpers ----------
    function signedIn() { return request.auth != null; }
    function uid() { return request.auth.uid; }
    function myPhone() { return request.auth.token.phone_number; }
    function changedOnly(keys) {
      return request.resource.data.diff(resource.data).affectedKeys().hasOnly(keys);
    }
    function validRelation(r) {
      return r in ['self','mother','father','spouse','son','daughter','brother','sister','other'];
    }
    function validPatient(d) {
      return d.name is string && d.name.size() >= 2 && d.name.size() <= 60
        && d.nameLower == d.name.lower()
        && d.birthYear is int
        && d.birthYear >= request.time.year() - 120
        && d.birthYear <= request.time.year()
        && d.gender in ['male','female','other']
        && validRelation(d.relation)
        && (d.patientPhone == null || d.patientPhone.matches('^\\+923[0-9]{9}$'));
    }

    // ---------- users ----------
    match /users/{userId} {
      allow read: if signedIn() && uid() == userId;

      allow create: if signedIn() && uid() == userId
        && request.resource.data.phone == myPhone()
        && request.resource.data.role == 'patient'
        && request.resource.data.name is string
        && request.resource.data.name.size() >= 2
        && request.resource.data.name.size() <= 60;

      allow update: if signedIn() && uid() == userId
        && changedOnly(['name','city','updatedAt','lastLoginAt',
                        'consentAcceptedAt','consentVersion','queueAlertsEnabled'])
        && request.resource.data.name.size() >= 2
        && request.resource.data.name.size() <= 60
        && request.resource.data.get('queueAlertsEnabled', true) is bool;

      allow delete: if false;                 // deleteAccount function only

      match /devices/{deviceId} {
        allow read, delete: if signedIn() && uid() == userId;
        allow create, update: if signedIn() && uid() == userId
          && request.resource.data.keys().hasOnly(['fcmToken','platform','appVersion','updatedAt'])
          && request.resource.data.platform in ['android','ios'];
      }
    }

    // ---------- patients (family profiles) ----------
    match /patients/{patientId} {
      allow read: if signedIn() && resource.data.ownerUid == uid();

      allow create: if signedIn()
        && request.resource.data.ownerUid == uid()
        && request.resource.data.phone == myPhone()
        && request.resource.data.status == 'active'
        && request.resource.data.createdBy == 'app'
        && validPatient(request.resource.data)
        // only one Self profile: allowed only while the user doc has no selfPatientId
        && (request.resource.data.relation != 'self'
            || !exists(/databases/$(database)/documents/users/$(uid()))
            || get(/databases/$(database)/documents/users/$(uid())).data.get('selfPatientId', null) == null);

      allow update: if signedIn()
        && resource.data.ownerUid == uid()
        && request.resource.data.ownerUid == uid()
        && changedOnly(['name','nameLower','birthYear','gender','relation',
                        'patientPhone','status','updatedAt'])
        && request.resource.data.status in ['active','deleted']
        && !(resource.data.relation == 'self' && request.resource.data.status == 'deleted')
        && !(resource.data.relation != 'self' && request.resource.data.relation == 'self')
        && validPatient(request.resource.data);

      allow delete: if false;                 // soft delete only
    }

    // ---------- clinics & doctors (read-only for patients) ----------
    match /clinics/{clinicId} {
      allow read: if signedIn();
      allow write: if false;
      match /private/{docId} { allow read, write: if false; }   // billing, Phase 3
      match /stats/{docId}   { allow read, write: if false; }   // Phase 2
    }

    match /doctors/{doctorId} {
      allow read: if signedIn();
      allow write: if false;
      match /days/{date} {
        allow read: if signedIn();             // numbers only, no personal data
        allow write: if false;
      }
    }

    // ---------- tokens ----------
    match /tokens/{tokenId} {
      allow read: if signedIn()
        && (resource.data.bookedByUserId == uid()
            || resource.data.patientOwnerUid == uid());
      allow write: if false;                  // bookToken / cancelToken / triggers only
    }

    // ---------- follow-ups ----------
    match /followUps/{id} {
      allow read: if signedIn() && resource.data.ownerUid == uid();
      allow write: if false;
    }
  }
}
```

Notes:
- The users doc `selfPatientId` is set by the onboarding batch. Because `changedOnly` excludes it, the client can't change it later. The **first** create of the users doc must include it (rule above allows any fields on create except role/phone checks; keep the create payload to the documented fields in code review).
- Queries must include the filter that rules check (e.g. `where('bookedByUserId', isEqualTo: uid)` or `where('patientOwnerUid', isEqualTo: uid)`), otherwise Firestore rejects the whole query.
- **Phase 2** will add staff rules based on `request.auth.token.clinicId`. Do not add them now.
- Every rule change needs a test (docs/07 §3).

---

## 6. Cloud Functions security

Every callable:
1. `if (!request.auth) throw new HttpsError('unauthenticated', ...)`
2. App Check enforced (prod).
3. Validate every input field (type, length, format, enum). Reject unknown fields.
4. Check ownership: e.g. `bookToken` requires `patient.ownerUid == request.auth.uid`; `cancelToken` requires `token.bookedByUserId == request.auth.uid`.
5. Business rules inside a transaction where counters are involved.
6. Return only what the client needs (`{tokenId, number}`); never return other users' data.

Rate limiting: `bookToken` rejects > 10 calls per user per minute (counter doc `rateLimits/{uid}` written by the function only).

---

## 7. Privacy principles (from the overview, applied)

1. **Minimum data:** name, age (birth year), gender, relation, phone. No diagnosis, medicines or reports in Phase 1.
2. **Limited exposure:** patients only see their own data. Queue info for others is numbers only (`activeNumbers`).
3. **Clinic isolation (Phase 2):** staff see only their clinic, enforced by rules using the `clinicId` claim.
4. **Patient control:** edit/remove profiles; delete account (F-10).
5. **Transparency:** consent screen at first login; hosted Privacy Policy; `consentVersion` stored.
6. **Logs:** never log full phone numbers, names with phone numbers, or FCM tokens. Mask phones (`+92300****567`).
7. **Analytics:** no personal data in events or user properties.

---

## 8. Account deletion (`deleteAccount`)

Required by Google Play and the App Store.

1. Callable verifies the caller.
2. Cancels the user's active tokens.
3. Deletes `users/{uid}` and its `devices`.
4. For profiles with `createdBy == 'app'`: set `name: "Deleted user"`, `nameLower`, `patientPhone: null`, `phone: null`, `ownerUid: null`, `status: deleted`. Token `patientSnapshot` names are replaced the same way.
5. Deletes the Auth user.
6. Logs an anonymised audit line (uid hash + time).

---

## 9. Secrets and keys

| Secret | Where it lives | Never |
|---|---|---|
| Service account JSON (admin scripts, queue-sim) | Developer's machine only | Git, chat, screenshots |
| Android upload keystore + `key.properties` | Developer's machine + secure backup | Git |
| APNs .p8 key | Apple account + Firebase console | Git |
| Codemagic/CI credentials | CI secret store | Git |

If a secret leaks: rotate it immediately (new service account key, revoke the old one) and check the Firebase audit logs.

---

## 10. Security checklist before a production release

- [ ] Rules deployed and all rules tests pass
- [ ] App Check enforced for Functions; Firestore enforcement plan decided
- [ ] SMS region policy = Pakistan only; budget alerts on
- [ ] No test phone numbers in `asani-prod`
- [ ] Release SHA-1/SHA-256 (Play App Signing key) added to Firebase
- [ ] Crashlytics doesn't capture personal data in custom keys
- [ ] Privacy policy URL live and linked in the app and stores
- [ ] Account deletion tested end-to-end
