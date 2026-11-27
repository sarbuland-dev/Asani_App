import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/clinic_theme.dart';
import '../../data/providers.dart';
import 'admin_frame.dart';
import 'clinic_frame.dart';

/// Desktop frame: the clinic and the Super Admin each have their own sidebar.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  /// PRD §9: minimum screen width 1280 px; below that the page scrolls sideways.
  static const minWidth = 1180.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final frame = user.isClinic
        ? ClinicFrame(user: user, location: location, child: child)
        : AdminFrame(user: user, location: location, child: child);

    return ClinicThemed(
      child: Scaffold(
        body: LayoutBuilder(builder: (context, c) {
          if (c.maxWidth >= minWidth) return frame;
          return SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: minWidth, height: c.maxHeight, child: frame));
        }),
      ),
    );
  }
}
