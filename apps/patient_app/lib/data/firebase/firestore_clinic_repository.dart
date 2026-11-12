import 'dart:async';

import 'package:asani_core/asani_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../../core/utils/logger.dart';
import '../demo/demo_backend.dart';
import '../repositories/repositories.dart';

/// Clinics from Firestore `clinics/{clinicId}` (PRD F-02, DATABASE.md §4) and
/// doctors from `doctors/{doctorId}` (DATABASE.md §5). IDs match the demo IDs
/// (`c_alshifa`, `d_ayesha`, ...), so demo tokens and queues keep pointing at
/// real clinics and doctors until they move to Firebase (DEMO_TO_FIREBASE.txt).
class FirestoreClinicRepository implements ClinicRepository {
  FirestoreClinicRepository(this._demo, this._tokens, {fs.FirebaseFirestore? db}) : _db = db ?? fs.FirebaseFirestore.instance;

  final DemoBackend _demo;
  final TokenRepository _tokens;
  final fs.FirebaseFirestore _db;

  /// DATABASE.md §4: patients see pilot, active and grace clinics.
  static const visibleStatuses = ['pilot', 'active', 'grace'];

  fs.CollectionReference<Map<String, dynamic>> get _clinics => _db.collection('clinics');

  static Clinic _fromDoc(fs.DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = Map<String, Object?>.from(doc.data()!);
    m['id'] = doc.id;
    // Firestore stores a geopoint; the shared model reads {lat, lng}.
    final loc = m['location'];
    if (loc is fs.GeoPoint) m['location'] = {'lat': loc.latitude, 'lng': loc.longitude};
    return Clinic.fromMap(m);
  }

  /// Bad documents are logged and skipped instead of breaking the whole list.
  static List<Clinic> _parse(Iterable<fs.DocumentSnapshot<Map<String, dynamic>>> docs) {
    final out = <Clinic>[];
    for (final d in docs) {
      try {
        out.add(_fromDoc(d));
      } catch (e) {
        AppLogger.warn('Skipping clinic ${d.id}: $e');
      }
    }
    return out;
  }

  // ---------------------------------------------------------------- clinics

  @override
  Stream<List<String>> watchCities() => _clinics
      .where('status', whereIn: visibleStatuses)
      .snapshots()
      .map((s) => (_parse(s.docs).map((c) => c.city).toSet().toList())..sort());

  @override
  Stream<List<Clinic>> watchClinics(String city) => _clinics
      .where('city', isEqualTo: city)
      .where('status', whereIn: visibleStatuses)
      .snapshots()
      .map((s) => _parse(s.docs)..sort((a, b) => a.name.compareTo(b.name)));

  @override
  Stream<Clinic?> watchClinic(String clinicId) => _clinics.doc(clinicId).snapshots().map((d) {
        if (!d.exists) return null;
        try {
          return _fromDoc(d);
        } catch (e) {
          AppLogger.warn('Bad clinic $clinicId: $e');
          return null;
        }
      });

  /// Clinics the user booked before, latest first, max 5 (PRD F-02).
  /// The order comes from the user's tokens; suspended clinics are included.
  @override
  Stream<List<Clinic>> watchRecentClinics() => _tokens.watchMyTokens().map(_recentIds).distinct(_sameList).asyncMap((ids) async {
        if (ids.isEmpty) return const <Clinic>[];
        final docs = await Future.wait(ids.map((id) => _clinics.doc(id).get()));
        return _parse(docs.where((d) => d.exists));
      });

  /// Clinic IDs from my tokens, latest booking first, max 5.
  static List<String> _recentIds(List<Token> tokens) {
    final sorted = [...tokens]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final ids = <String>[];
    for (final t in sorted) {
      if (!ids.contains(t.clinicId)) ids.add(t.clinicId);
    }
    return ids.take(5).toList();
  }

  static bool _sameList(List<String> a, List<String> b) => a.join(',') == b.join(',');

  // ---------------------------------------------------------------- doctors

  fs.CollectionReference<Map<String, dynamic>> get _doctors => _db.collection('doctors');

  /// Every doctor read here is also handed to the demo backend, so booking and
  /// the queue (still demo) use the same schedule the screen shows.
  List<Doctor> _parseDoctors(Iterable<fs.DocumentSnapshot<Map<String, dynamic>>> docs) {
    final out = <Doctor>[];
    for (final d in docs) {
      try {
        out.add(Doctor.fromMap({...d.data()!, 'id': d.id}));
      } catch (e) {
        AppLogger.warn('Skipping doctor ${d.id}: $e');
      }
    }
    _demo.useDoctors(out);
    return out;
  }

  /// DATABASE.md §9 index: clinicId + active + sortOrder.
  @override
  Stream<List<Doctor>> watchDoctors(String clinicId) => _doctors
      .where('clinicId', isEqualTo: clinicId)
      .where('active', isEqualTo: true)
      .orderBy('sortOrder')
      .snapshots()
      .map((s) => _parseDoctors(s.docs));

  @override
  Stream<Doctor?> watchDoctor(String doctorId) => _doctors.doc(doctorId).snapshots().map((d) {
        if (!d.exists) return null;
        return _parseDoctors([d]).firstOrNull;
      });

  /// Active doctors grouped by clinic, for availability on clinic cards.
  @override
  Stream<Map<String, List<Doctor>>> watchDoctorsByClinic() =>
      _doctors.where('active', isEqualTo: true).snapshots().map((s) {
        final byClinic = <String, List<Doctor>>{};
        for (final d in _parseDoctors(s.docs)) {
          byClinic.putIfAbsent(d.clinicId, () => []).add(d);
        }
        for (final list in byClinic.values) {
          list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        }
        return byClinic;
      });
}
