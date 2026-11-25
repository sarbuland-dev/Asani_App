import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/firebase_setup.dart';
import 'data/clinic_repository.dart';
import 'data/demo_clinic_repository.dart';
import 'data/firebase_clinic_repository.dart';
import 'data/providers.dart';
import 'data/supabase_clinic_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, FlutterAuthClientOptions, AuthFlowType;

/// Asani Clinic Web (PRD-CLINIC-WEB): clinic dashboard + super admin.
///
/// `--dart-define=BACKEND=supabase`: Supabase (D-52). `--dart-define=BACKEND=firebase`: old Firebase (same project as the
/// patient app). Without it: the in-memory demo backend.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ClinicRepository repo;
  if (Env.useSupabase) {
    // An invite / reset email link lands here with "#access_token=…&type=invite|recovery"; read the type before
    // Supabase consumes the link, so the clinic is asked for a password first (D-52).
    final linkType = Uri.splitQueryString(Uri.base.fragment.contains('=') ? Uri.base.fragment.replaceFirst(RegExp(r'^/?'), '') : '')['type'];
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabaseKey,
        // Server-sent links (invites, resets) carry the session in the URL fragment.
        authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.implicit),
      );
      repo = await SupabaseClinicRepository.create(linkType: linkType);
    } catch (e) {
      runApp(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Supabase setup failed.\n\n$e', textAlign: TextAlign.center)))),
      ));
      return;
    }
  } else if (Env.useFirebase) {
    try {
      await FirebaseSetup.init();
      repo = await FirebaseClinicRepository.create();
    } catch (e) {
      runApp(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Firebase setup is not finished.\n\n$e', textAlign: TextAlign.center)))),
      ));
      return;
    }
  } else {
    repo = DemoClinicRepository();
  }
  runApp(ProviderScope(
    overrides: [repositoryProvider.overrideWithValue(repo)],
    child: const ClinicWebApp(),
  ));
}
