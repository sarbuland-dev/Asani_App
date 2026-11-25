import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/push/push_service.dart';

/// This phone's FCM token in the Supabase `devices` table (D-52), keyed by (user_id, device_id).
/// The send-push Edge Function reads it; FCM-dead tokens are deleted there.
class SupabasePushAccount implements PushAccount {
  SupabaseClient get _db => Supabase.instance.client;

  @override
  String? get uid => _db.auth.currentUser?.id;

  /// Only real changes of the account (a token refresh is not a new account).
  @override
  Stream<String?> get uidChanges => _db.auth.onAuthStateChange.map((e) => e.session?.user.id).distinct();

  @override
  Future<void> saveDevice(String uid, String deviceId, {required String token, required String platform, required String appVersion}) =>
      _db.from('devices').upsert(
        {'user_id': uid, 'device_id': deviceId, 'fcm_token': token, 'platform': platform, 'app_version': appVersion},
        onConflict: 'user_id,device_id',
      );

  @override
  Future<void> deleteDevice(String uid, String deviceId) =>
      _db.from('devices').delete().eq('user_id', uid).eq('device_id', deviceId);
}
