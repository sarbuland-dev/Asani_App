import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'package:asani_ui/asani_ui.dart';

class ClinicWebApp extends ConsumerWidget {
  const ClinicWebApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Asani Clinic',
      debugShowCheckedModeBanner: false,
      theme: buildDesktopAppTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
