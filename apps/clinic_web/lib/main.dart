import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/demo_clinic_repository.dart';
import 'data/providers.dart';

/// Asani Clinic Web (PRD-CLINIC-WEB): clinic dashboard + super admin.
///
/// Today it runs on the in-memory demo backend. The Firebase version
/// (email/password auth, custom-claim roles, callable functions) plugs in
/// here by overriding [repositoryProvider] with a Firebase repository.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ProviderScope(
    overrides: [repositoryProvider.overrideWithValue(DemoClinicRepository())],
    child: const ClinicWebApp(),
  ));
}
