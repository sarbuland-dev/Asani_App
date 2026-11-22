import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:asani_ui/asani_ui.dart' hide AppColors;
import 'package:clinic_web/core/theme/web_colors.dart';

/// Online or not. If the check itself fails we assume online.
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

/// True unless we know we're offline. Actions are disabled while offline (§10).
final isOnlineProvider = Provider<bool>((ref) => ref.watch(onlineProvider).value ?? true);

/// PRD-CLINIC-WEB §10: red banner "Offline: actions disabled"; the queue
/// keeps showing the last data.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isOnlineProvider)) return const SizedBox.shrink();
    return Material(
      color: AppColors.danger,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.xl, vertical: Gap.sm),
        child: Row(children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.onPrimary),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text('Offline: actions disabled. The queue shows the last data until the internet is back.',
                style: AppText.labelMedium.copyWith(color: AppColors.onPrimary)),
          ),
        ]),
      ),
    );
  }
}
