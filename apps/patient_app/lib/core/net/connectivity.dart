import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:asani_ui/asani_ui.dart';
import 'package:asani_core/asani_core.dart';

/// Online or not (ARCHITECTURE.md §8). The Supabase reads keep no copy on the
/// phone; booking and cancelling need a connection. If the check itself
/// fails (e.g. in tests), we assume online rather than block the user.
final onlineProvider = StreamProvider<bool>((ref) async* {
  final c = Connectivity();
  bool online(List<ConnectivityResult> r) => r.any((x) => x != ConnectivityResult.none);
  try {
    yield online(await c.checkConnectivity());
    yield* c.onConnectivityChanged.map(online);
  } catch (_) {
    yield true;
  }
});

/// True unless we know we're offline.
final isOnlineProvider = Provider<bool>((ref) => ref.watch(onlineProvider).value ?? true);

/// When the app went offline, for "Offline, last updated 4:32 PM".
class OfflineSince extends Notifier<DateTime?> {
  @override
  DateTime? build() {
    ref.listen(isOnlineProvider, (_, online) => state = online ? null : (state ?? DateTime.now()));
    return ref.read(isOnlineProvider) ? null : DateTime.now();
  }
}

final offlineSinceProvider = NotifierProvider<OfflineSince, DateTime?>(OfflineSince.new);

/// DESIGN.md §6 / PRD §6: top banner while offline; cached data stays visible.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final since = ref.watch(offlineSinceProvider);
    if (since == null) return child;
    return Column(children: [
      Material(
        color: AppColors.textPrimary,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
            child: Row(children: [
              const Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.onPrimary),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  'Offline, last updated ${Fmt.clock(since)}',
                  style: AppText.labelMedium.copyWith(color: AppColors.onPrimary),
                ),
              ),
            ]),
          ),
        ),
      ),
      // The banner already covers the status bar.
      Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: child)),
    ]);
  }
}
