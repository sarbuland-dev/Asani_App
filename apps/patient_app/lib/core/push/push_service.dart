import 'dart:async';
import 'dart:math';

import 'package:asani_core/asani_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repositories/repositories.dart';
import '../config/app_info.dart';

/// The phone's notification permission, as the OS reports it.
enum PushPermission { granted, denied, notAsked }

/// FCM queue notifications (PRD F-06, ARCHITECTURE.md §3.3 / §8).
///
/// - asks the OS for permission (the real system popup),
/// - keeps this phone's FCM token for the signed-in account through a [PushAccount]
///   (Supabase `devices` table, D-52; or Firestore `users/{uid}/devices` in the old Firebase mode;
///   deviceId is a random ID stored on the phone),
/// - shows pushes that arrive while the app is open as in-app alerts,
/// - reports taps on a notification so the app opens that token (N-6).
///
/// Web (dev preview only) gets the browser permission prompt but no device
/// token: the rules accept only `android` / `ios` devices.
/// Where this phone's FCM token is stored for the signed-in account.
abstract interface class PushAccount {
  String? get uid;

  /// Emits the signed-in account ID (null when signed out) whenever it changes.
  Stream<String?> get uidChanges;
  Future<void> saveDevice(String uid, String deviceId, {required String token, required String platform, required String appVersion});
  Future<void> deleteDevice(String uid, String deviceId);
}

/// Old Firebase mode: `users/{uid}/devices/{deviceId}` in Firestore.
class FirebasePushAccount implements PushAccount {
  FirebasePushAccount({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  @override
  String? get uid => _auth.currentUser?.uid;

  @override
  Stream<String?> get uidChanges => _auth.authStateChanges().map((u) => u?.uid);

  @override
  Future<void> saveDevice(String uid, String deviceId, {required String token, required String platform, required String appVersion}) =>
      _db.collection('users').doc(uid).collection('devices').doc(deviceId).set({
        'fcmToken': token,
        'platform': platform,
        'appVersion': appVersion,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> deleteDevice(String uid, String deviceId) =>
      _db.collection('users').doc(uid).collection('devices').doc(deviceId).delete();
}

class PushService {
  PushService({FirebaseMessaging? messaging, PushAccount? account})
      : _messaging = messaging ?? FirebaseMessaging.instance,
        _account = account ?? FirebasePushAccount();

  static const channelId = 'queue_alerts'; // DESIGN.md §8
  static const followUpChannelId = 'follow_ups';
  static const _deviceIdKey = 'asani.deviceId';

  final FirebaseMessaging _messaging;
  final PushAccount _account;

  final _alerts = StreamController<QueueAlert>.broadcast();
  final _opened = StreamController<String>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  String? _initialRoute;

  /// Pushes received while the app is in the foreground.
  Stream<QueueAlert> get alerts => _alerts.stream;

  /// Screens to open from notifications the user tapped: a token's live
  /// screen (N-6) or booking pre-filled from a follow-up (F-09).
  Stream<String> get openedRoutes => _opened.stream;

  /// A tap that cold-started the app; read once after the router is ready.
  String? takeInitialRoute() {
    final route = _initialRoute;
    _initialRoute = null;
    return route;
  }

  /// Only our own screens, never an arbitrary link from a message.
  static String? _routeOf(RemoteMessage m) {
    final route = m.data['route'] as String?;
    if (route != null && (route.startsWith('/token/') || route.startsWith('/book/'))) return route;
    final tokenId = m.data['tokenId'] as String?;
    return tokenId == null ? null : '/token/$tokenId';
  }

  static bool get _isMobile =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init() async {
    if (_isMobile && defaultTargetPlatform == TargetPlatform.android) {
      // DESIGN.md §8: queue alerts high importance (sound + vibration), follow-ups default.
      final android = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        channelId,
        'Queue alerts',
        description: 'When your turn is near, and when it is your turn.',
        importance: Importance.high,
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        followUpChannelId,
        'Follow-up reminders',
        description: 'Reminders for follow-up visits.',
      ));
    }
    _subs
      ..add(FirebaseMessaging.onMessage.listen(_onForeground))
      ..add(FirebaseMessaging.onMessageOpenedApp.listen(_onOpened))
      // getToken/onTokenRefresh are deprecated in firebase_messaging 17 in favour of
      // register()/onRegistered (Installation IDs). The Admin SDK sends to FCM
      // registration tokens, so we keep these until the server moves too.
      // ignore: deprecated_member_use
      ..add(_messaging.onTokenRefresh.listen((_) => register()))
      ..add(_account.uidChanges.listen((uid) async {
        if (uid != null && await permission() == PushPermission.granted) await register();
      }));
    try {
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _initialRoute = _routeOf(initial);
    } catch (e) {
      AppLogger.warn('getInitialMessage: $e');
    }
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _alerts.close();
    _opened.close();
  }

  // ---------------------------------------------------------------- permission

  Future<PushPermission> permission() async {
    try {
      return _map((await _messaging.getNotificationSettings()).authorizationStatus);
    } catch (e) {
      AppLogger.warn('getNotificationSettings: $e');
      return PushPermission.notAsked;
    }
  }

  /// Shows the system popup ("Allow Asani to send notifications?"). Once the
  /// user said no, Android/iOS return `denied` without asking again; the app
  /// then offers to open the phone's settings.
  Future<PushPermission> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(alert: true, badge: true, sound: true);
      final result = _map(settings.authorizationStatus);
      if (result == PushPermission.granted) await register();
      return result;
    } catch (e) {
      AppLogger.warn('requestPermission: $e');
      return PushPermission.denied;
    }
  }

  static PushPermission _map(AuthorizationStatus s) => switch (s) {
        AuthorizationStatus.authorized || AuthorizationStatus.provisional => PushPermission.granted,
        AuthorizationStatus.denied || AuthorizationStatus.deniedPermanently => PushPermission.denied,
        AuthorizationStatus.notDetermined => PushPermission.notAsked,
      };

  // ---------------------------------------------------------------- device token

  static Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null) return existing;
    final rnd = Random.secure();
    final id = List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await prefs.setString(_deviceIdKey, id);
    return id;
  }

  /// Saves this phone's FCM token for the signed-in account.
  Future<void> register() async {
    final uid = _account.uid;
    if (uid == null || !_isMobile) return;
    try {
      // ignore: deprecated_member_use
      final token = await _messaging.getToken();
      if (token == null) return;
      await _account.saveDevice(uid, await _deviceId(),
          token: token, platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android', appVersion: appVersion);
    } catch (e) {
      AppLogger.warn('Could not register this phone for alerts: $e');
    }
  }

  /// Call BEFORE signing out (the rules need the signed-in user), so the next
  /// person on this phone doesn't get the previous account's alerts.
  Future<void> unregister() async {
    final uid = _account.uid;
    if (uid == null || !_isMobile) return;
    try {
      await _account.deleteDevice(uid, await _deviceId());
    } catch (e) {
      AppLogger.warn('Could not unregister this phone: $e');
    }
  }

  // ---------------------------------------------------------------- messages

  static const _steps = {
    'ahead3': QueueStep.threeAhead,
    'ahead2': QueueStep.twoAhead,
    'ahead1': QueueStep.oneAhead,
    'yourTurn': QueueStep.called,
  };

  void _onForeground(RemoteMessage m) {
    final tokenId = m.data['tokenId'] as String?;
    final step = _steps[m.data['step']];
    if (tokenId == null || step == null) return;
    _alerts.add(QueueAlert(
      tokenId: tokenId,
      step: step,
      title: m.notification?.title ?? '',
      body: m.notification?.body ?? '',
    ));
  }

  void _onOpened(RemoteMessage m) {
    final route = _routeOf(m);
    if (route != null) _opened.add(route);
  }
}
