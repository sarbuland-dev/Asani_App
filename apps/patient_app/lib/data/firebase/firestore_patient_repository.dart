import 'dart:async';

import 'package:asani_core/asani_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/logger.dart';
import '../demo/demo_backend.dart';
import '../repositories/repositories.dart';

/// Family profiles in Firestore `patients/{patientId}` (PRD F-07, DATABASE.md §3).
///
/// Writes follow firestore.rules: the client sets only the allowed fields,
/// `nameLower == name.lower()`, and profiles are never hard-deleted.
/// Every list read is also handed to the demo backend, so booking (still demo)
/// can book for these profiles (DEMO_TO_FIREBASE.txt step 3).
class FirestorePatientRepository implements PatientRepository {
  FirestorePatientRepository(this._demo, {FirebaseAuth? auth, fs.FirebaseFirestore? db})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? fs.FirebaseFirestore.instance;

  final DemoBackend _demo;
  final FirebaseAuth _auth;
  final fs.FirebaseFirestore _db;

  fs.CollectionReference<Map<String, dynamic>> get _patients => _db.collection('patients');

  static String _clean(String name) => name.trim().replaceAll(RegExp(r'\s+'), ' ');

  static Patient? _fromDoc(fs.DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final m = Map<String, Object?>.from(doc.data()!);
      m['id'] = doc.id;
      // Server timestamps are null until the write is confirmed.
      final created = m['createdAt'];
      m['createdAt'] = created is fs.Timestamp ? created.millisecondsSinceEpoch : DateTime.now().millisecondsSinceEpoch;
      return Patient.fromMap(m);
    } catch (e) {
      AppLogger.warn('Skipping patient ${doc.id}: $e');
      return null;
    }
  }

  static AppException _map(Object e, String fallback) {
    if (e is fs.FirebaseException) {
      AppLogger.warn('Firestore ${e.code}: ${e.message}');
      if (e.code == 'unavailable') return const AppException('offline', 'No internet connection. Please try again.');
    }
    return AppException('patient-write', fallback);
  }

  // ---------------------------------------------------------------- read

  /// Self first, then in the order they were added. The provider restarts
  /// this stream when the signed-in user changes.
  @override
  Stream<List<Patient>> watchMyPatients() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const []);
    return _patients
        .where('ownerUid', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt') // DATABASE.md §9 index: ownerUid + status + createdAt
        .snapshots()
        .map((s) {
      final list = s.docs.map(_fromDoc).whereType<Patient>().toList()
        ..sort((a, b) {
          if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
          return a.createdAt.compareTo(b.createdAt);
        });
      _demo.usePatients(list);
      return list;
    });
  }

  // ---------------------------------------------------------------- write

  @override
  Future<Patient> addPatient({
    required String name,
    int? age,
    required Gender gender,
    required Relation relation,
    String? patientPhone,
  }) async {
    final user = _auth.currentUser;
    final phone = user?.phoneNumber;
    if (user == null || phone == null) throw const AppException('session-expired', 'Session expired. Please log in again.');
    if (age == null) throw const AppException('age-required', 'Please enter the age.');

    final clean = _clean(name);
    final ref = _patients.doc();
    final now = fs.FieldValue.serverTimestamp();
    try {
      await ref.set({
        'phone': phone,
        'ownerUid': user.uid,
        'name': clean,
        'nameLower': clean.toLowerCase(),
        'birthYear': DateTime.now().year - age,
        'gender': gender.name,
        'relation': relation.name,
        'patientPhone': patientPhone,
        'status': 'active',
        'mergedInto': null,
        'personId': null,
        'createdBy': 'app',
        'createdAt': now,
        'updatedAt': now,
      });
    } catch (e) {
      throw _map(e, 'Could not add this profile. Please try again.');
    }
    final patient = Patient(
      id: ref.id,
      ownerUid: user.uid,
      phone: phone,
      name: clean,
      birthYear: DateTime.now().year - age,
      gender: gender,
      relation: relation,
      patientPhone: patientPhone,
      createdAt: DateTime.now(),
    );
    _demo.usePatients([patient]);
    return patient;
  }

  /// Editing Self also renames the account (users/{uid}.name), in one batch.
  @override
  Future<void> updatePatient(Patient patient, {int? age}) async {
    final user = _auth.currentUser;
    if (user == null) throw const AppException('session-expired', 'Session expired. Please log in again.');
    final clean = _clean(patient.name);
    final now = fs.FieldValue.serverTimestamp();
    final batch = _db.batch()
      ..update(_patients.doc(patient.id), {
        'name': clean,
        'nameLower': clean.toLowerCase(),
        'birthYear': age == null ? patient.birthYear : DateTime.now().year - age,
        'gender': patient.gender.name,
        'relation': patient.relation.name,
        'patientPhone': patient.patientPhone,
        'updatedAt': now,
      });
    if (patient.isSelf) {
      batch.update(_db.collection('users').doc(user.uid), {'name': clean, 'updatedAt': now});
    }
    try {
      await batch.commit();
    } catch (e) {
      throw _map(e, 'Could not save changes. Please try again.');
    }
  }

  /// Soft delete (PRD F-07). Self cannot be removed (also enforced by rules).
  @override
  Future<void> removePatient(String patientId) async {
    final doc = await _patients.doc(patientId).get().catchError((Object e) => throw _map(e, 'Could not remove this profile.'));
    final p = doc.exists ? _fromDoc(doc) : null;
    if (p == null || p.isSelf) throw const AppException('cannot-remove', 'This profile cannot be removed.');
    try {
      await _patients.doc(patientId).update({'status': 'deleted', 'updatedAt': fs.FieldValue.serverTimestamp()});
    } catch (e) {
      throw _map(e, 'Could not remove this profile. Please try again.');
    }
    _demo.usePatients([p.copyWith(status: PatientStatus.deleted)]);
  }
}
