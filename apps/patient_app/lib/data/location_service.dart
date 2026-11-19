import 'package:asani_core/asani_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/env.dart';

/// The patient's position for "nearest first" (PRD F-13, D-31).
abstract interface class LocationService {
  /// Null when location is off, refused or unavailable.
  Future<GeoPoint?> current();
}

/// Demo backend: a fixed spot in Johar Town, Lahore, so distances show without GPS.
class DemoLocationService implements LocationService {
  const DemoLocationService();
  static const johar = GeoPoint(31.4700, 74.2700);
  @override
  Future<GeoPoint?> current() async => johar;
}

/// Firebase builds until `geolocator` is wired (docs/09 §5, integration side):
/// no location, so the list falls back to area order.
class NoLocationService implements LocationService {
  const NoLocationService();
  @override
  Future<GeoPoint?> current() async => null;
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => Env.backend == 'demo' ? const DemoLocationService() : const NoLocationService(),
);

final userLocationProvider = FutureProvider<GeoPoint?>((ref) => ref.watch(locationServiceProvider).current());
