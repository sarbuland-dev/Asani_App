import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/demo/demo_backend.dart';
import 'data/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Demo backend until Firebase (asani-dev) is connected.
  final backend = await DemoBackend.create();

  runApp(ProviderScope(
    overrides: [backendProvider.overrideWithValue(backend)],
    child: const AsaniApp(),
  ));
}
