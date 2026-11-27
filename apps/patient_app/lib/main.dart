import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/config/firebase_setup.dart';
import 'core/push/push_service.dart';
import 'package:asani_core/asani_core.dart';
import 'data/demo/demo_backend.dart';
import 'data/providers.dart';
import 'data/repositories/repositories.dart';
import 'data/supabase/supabase_auth_repository.dart';
import 'data/supabase/supabase_push_account.dart';
import 'data/supabase/supabase_repositories.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inter is bundled in assets/google_fonts (DESIGN.md §3.2): never fetch it.
  GoogleFonts.config.allowRuntimeFetching = false;
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Demo backend: demo mode, plus this phone's settings (intro, primer) in Supabase mode.
  final backend = await DemoBackend.create();

  // Supabase with --dart-define=BACKEND=supabase (D-52), demo data otherwise (D-11).
  final overrides = [backendProvider.overrideWithValue(backend)];
  if (Env.useSupabase) {
    try {
      await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
    } catch (e) {
      runApp(_SetupError('Supabase setup failed.\n\n$e'));
      return;
    }
    backend.stopSimulator(); // the real queue moves from the clinic web (or tools/queue-sim)

    // Push stays on Firebase Cloud Messaging (free Spark plan); the device token goes to Supabase.
    PushService? push;
    try {
      await FirebaseSetup.initForPushOnly();
      push = await _startPush(backend, SupabasePushAccount());
      overrides.add(pushServiceProvider.overrideWithValue(push));
    } catch (e) {
      AppLogger.warn('Push not available: $e');
    }

    // Phase 5 (D-52): login, clinics, doctors, queue, tokens, family, follow-ups and the notifications list.
    final auth = SupabaseAuthRepository(backend, beforeSignOut: push?.unregister);
    overrides.add(authRepositoryProvider.overrideWithValue(auth));
    // A device can only be saved once the account row exists (after profile setup), so register on sign-in.
    if (push != null) {
      final p = push;
      auth.watchAuth().where((s) => s.status == AuthStatus.signedIn).map((s) => s.user?.uid).distinct().listen((_) async {
        if (await p.permission() == PushPermission.granted) await p.register();
      });
    }
    final tokens = SupabaseTokenRepository(alerts: push?.alerts);
    overrides.add(tokenRepositoryProvider.overrideWithValue(tokens));
    overrides.add(clinicRepositoryProvider.overrideWithValue(SupabaseClinicRepository(tokens)));
    overrides.add(queueRepositoryProvider.overrideWithValue(SupabaseQueueRepository()));
    overrides.add(patientRepositoryProvider.overrideWithValue(SupabasePatientRepository()));
    overrides.add(followUpRepositoryProvider.overrideWithValue(SupabaseFollowUpRepository()));
    overrides.add(notificationRepositoryProvider.overrideWithValue(SupabaseNotificationRepository()));
  }

  runApp(ProviderScope(overrides: overrides, child: const AsaniApp()));
}

/// FCM queue notifications. The OS permission is the truth: if it was turned off in phone settings,
/// Account shows "Off" (and the primer can ask again).
Future<PushService> _startPush(DemoBackend backend, PushAccount account) async {
  final push = PushService(account);
  try {
    await push.init();
    final permission = await push.permission();
    final s = backend.settings;
    if (permission != PushPermission.granted && s.notificationsAllowed) {
      await backend.update(s.copyWith(notificationsAllowed: false));
    } else if (permission == PushPermission.granted && s.primerShown && !s.notificationsAllowed) {
      await backend.update(s.copyWith(notificationsAllowed: true));
    }
  } catch (e) {
    AppLogger.warn('Push setup failed: $e');
  }
  return push;
}

/// Shown instead of a blank screen when the backend cannot start.
class _SetupError extends StatelessWidget {
  const _SetupError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(padding: const EdgeInsets.all(24), child: Text(message, textAlign: TextAlign.center)),
          ),
        ),
      );
}
