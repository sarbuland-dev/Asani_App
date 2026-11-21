import 'package:asani_core/asani_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/env.dart';

/// Where the patient's location permission stands (PRD F-13, DESIGN S-18).
enum LocationAccess {
  granted,
  denied,

  /// Refused for good: only the phone's settings can turn it on.
  deniedForever,

  /// Location (GPS) is switched off on the phone.
  off,
}

/// The patient's position for "nearest first" (D-31). Foreground only.
abstract interface class LocationService {
  Future<LocationAccess> access();

  /// Shows the phone's own permission popup (after the S-18 card).
  Future<LocationAccess> request();

  /// Null when not granted or not available. Never asks for permission.
  Future<GeoPoint?> current();

  Future<void> openSettings();
}

/// Demo backend: a fixed spot in Johar Town, Lahore, so distances show without GPS.
class DemoLocationService implements LocationService {
  const DemoLocationService();
  static const johar = GeoPoint(31.4700, 74.2700);
  @override
  Future<LocationAccess> access() async => LocationAccess.granted;
  @override
  Future<LocationAccess> request() async => LocationAccess.granted;
  @override
  Future<GeoPoint?> current() async => johar;
  @override
  Future<void> openSettings() async {}
}

/// Real GPS through geolocator (Android, iOS, web).
class DeviceLocationService implements LocationService {
  const DeviceLocationService();
  static geo.GeolocatorPlatform get _g => geo.GeolocatorPlatform.instance;

  static LocationAccess _map(geo.LocationPermission p) => switch (p) {
        geo.LocationPermission.always || geo.LocationPermission.whileInUse => LocationAccess.granted,
        geo.LocationPermission.deniedForever => LocationAccess.deniedForever,
        _ => LocationAccess.denied,
      };

  @override
  Future<LocationAccess> access() async {
    try {
      if (!await _g.isLocationServiceEnabled()) return LocationAccess.off;
      return _map(await _g.checkPermission());
    } catch (e) {
      AppLogger.warn('location access: $e');
      return LocationAccess.denied;
    }
  }

  @override
  Future<LocationAccess> request() async {
    try {
      if (!await _g.isLocationServiceEnabled()) return LocationAccess.off;
      return _map(await _g.requestPermission());
    } catch (e) {
      AppLogger.warn('location request: $e');
      return LocationAccess.denied;
    }
  }

  @override
  Future<GeoPoint?> current() async {
    if (await access() != LocationAccess.granted) return null;
    try {
      // Low accuracy is enough for "2.4 km" and is faster / kinder to the battery.
      final p = await _g.getCurrentPosition(
        locationSettings: const geo.LocationSettings(accuracy: geo.LocationAccuracy.low, timeLimit: Duration(seconds: 10)),
      );
      return GeoPoint(p.latitude, p.longitude);
    } catch (e) {
      AppLogger.warn('location: $e');
      final last = await _g.getLastKnownPosition().catchError((_) => null);
      return last == null ? null : GeoPoint(last.latitude, last.longitude);
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await _g.openAppSettings();
    } catch (e) {
      AppLogger.warn('open location settings: $e');
    }
  }
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => Env.backend == 'demo' ? const DemoLocationService() : const DeviceLocationService(),
);

final locationAccessProvider = FutureProvider<LocationAccess>((ref) => ref.watch(locationServiceProvider).access());

/// The patient's position, re-read whenever the permission changes.
final userLocationProvider = FutureProvider<GeoPoint?>((ref) async {
  final access = await ref.watch(locationAccessProvider.future);
  if (access != LocationAccess.granted) return null;
  return ref.watch(locationServiceProvider).current();
});

/// S-18 card is shown once per phone (stored on the device, not in Firestore).
class LocationPrimerSeen extends AsyncNotifier<bool> {
  static const _key = 'locationPrimerShown';

  @override
  Future<bool> build() async => (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  Future<void> markSeen() async {
    await (await SharedPreferences.getInstance()).setBool(_key, true);
    state = const AsyncData(true);
  }
}

final locationPrimerSeenProvider = AsyncNotifierProvider<LocationPrimerSeen, bool>(LocationPrimerSeen.new);

/// "Allow location" on the S-18 card or the "Turn on location" note.
Future<void> askForLocation(WidgetRef ref) async {
  final svc = ref.read(locationServiceProvider);
  final now = await svc.access();
  if (now == LocationAccess.deniedForever || now == LocationAccess.off) {
    await svc.openSettings();
  } else {
    await svc.request();
  }
  await ref.read(locationPrimerSeenProvider.notifier).markSeen();
  ref.invalidate(locationAccessProvider);
}
