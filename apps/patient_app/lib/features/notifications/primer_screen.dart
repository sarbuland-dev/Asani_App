import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/push/push_service.dart';
import 'package:asani_ui/asani_ui.dart';
import '../../data/providers.dart';

/// Shows a route's page as a bottom sheet (board P4 S-17, D-50).
class BottomSheetPage<T> extends Page<T> {
  const BottomSheetPage({required this.child, super.key});
  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => ModalBottomSheetRoute<T>(
        settings: this,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (_) => child,
      );
}

/// S-17 notification permission primer, shown once before the first booking.
/// A bottom sheet (board P4, D-50). "Allow" opens the phone's own permission
/// popup (Firebase mode, PushService); if the phone already refused, the
/// button opens the phone's settings instead.
class PrimerScreen extends ConsumerStatefulWidget {
  const PrimerScreen({super.key, this.next});
  final String? next;

  @override
  ConsumerState<PrimerScreen> createState() => _PrimerScreenState();
}

class _PrimerScreenState extends ConsumerState<PrimerScreen> {
  /// The phone already said no: only its settings can turn alerts on.
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    final push = ref.read(pushServiceProvider);
    if (push != null && !kIsWeb) {
      push.permission().then((p) {
        if (mounted && p == PushPermission.denied) setState(() => _denied = true);
      });
    }
  }

  Future<void> _finish(bool allow) async {
    final repo = ref.read(settingsRepositoryProvider);
    final push = ref.read(pushServiceProvider);
    var allowed = allow;
    if (allow && _denied) {
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
      allowed = await push?.permission() == PushPermission.granted;
    } else if (allow && push != null) {
      allowed = await push.requestPermission() == PushPermission.granted;
      if (!allowed && mounted) await _explainDenied();
    }
    await repo.update(repo.settings.copyWith(primerShown: true, notificationsAllowed: allow ? allowed : null));
    // "Allow" also turns the account-wide switch back on if it was off (D-18).
    if (allow && ref.read(currentUserProvider)?.queueAlertsEnabled == false) {
      try {
        await ref.read(authRepositoryProvider).setQueueAlerts(true);
      } catch (_) {
        // Not critical: the switch can be turned on later in Account.
      }
    }
    if (!mounted) return;
    if (widget.next != null) {
      context.go(widget.next!);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  /// The phone blocked notifications. Android/iOS won't show the popup again,
  /// so the only way is the phone's settings.
  Future<void> _explainDenied() async {
    if (kIsWeb) {
      showSnack(context, 'Notifications are blocked. Allow them for this site in your browser settings.');
      return;
    }
    final open = await confirmDialog(
      context,
      title: 'Notifications are off',
      message: "Asani can't alert you when your turn is near. Turn on notifications for Asani in your phone's settings.",
      confirmLabel: 'Open settings',
      cancelLabel: 'Not now',
    );
    if (open) await AppSettings.openAppSettings(type: AppSettingsType.notification);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.md, Gap.xl, Gap.xl),
      // Board P4 S-17: handle, green bell tile, the promise, the 4 alerts, Allow / Not now.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(height: Gap.lg),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.notifications_none_rounded, size: 32, color: AppColors.onPrimary),
          ),
          const SizedBox(height: Gap.lg),
          Text('Get notified when your turn is near',
              style: AppText.headline.copyWith(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2)),
          const SizedBox(height: Gap.sm),
          Text(_denied ? "Notifications are off on this phone. Turn them on in the phone's settings." : 'At most 4 alerts per token.',
              style: AppText.bodyLarge.copyWith(fontSize: 15, color: AppColors.textSecondary)),
          const SizedBox(height: Gap.lg),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              _step(const Text('3'), '3 patients ahead of you', AppColors.surface, AppColors.primary),
              _step(const Text('2'), '2 patients ahead of you', AppColors.surface, AppColors.primary),
              _step(const Text('1'), "You're next", AppColors.primary, AppColors.onPrimary),
              _step(const Icon(Icons.check_rounded, size: 16, color: AppColors.surface), 'Your turn now', AppColors.info,
                  AppColors.surface,
                  last: true),
            ]),
          ),
          const SizedBox(height: Gap.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _finish(true),
              child: Text(_denied ? 'Open settings' : 'Allow notifications'),
            ),
          ),
          const SizedBox(height: Gap.sm),
          Center(child: TextButton(onPressed: () => _finish(false), child: const Text('Not now'))),
        ],
      ),
    );
  }

  Widget _step(Widget leading, String text, Color bg, Color fg, {bool last = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
            child: DefaultTextStyle(style: AppText.labelMedium.copyWith(color: fg, fontWeight: FontWeight.w700, fontSize: 13), child: leading),
          ),
          const SizedBox(width: Gap.md),
          Expanded(child: Text(text, style: AppText.bodyMedium.copyWith(color: AppColors.textPrimary, fontWeight: last ? FontWeight.w700 : FontWeight.w400))),
        ]),
      );
}
