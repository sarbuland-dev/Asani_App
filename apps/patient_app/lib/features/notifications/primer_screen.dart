import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/push/push_service.dart';
import 'package:asani_ui/asani_ui.dart';
import '../../data/providers.dart';

/// S-17 notification permission primer, shown once before the first booking.
/// "Allow" opens the phone's own permission popup (Firebase mode, PushService);
/// if the phone says no, we offer to open the phone's settings.
class PrimerScreen extends ConsumerWidget {
  const PrimerScreen({super.key, this.next});
  final String? next;

  Future<void> _finish(BuildContext context, WidgetRef ref, bool allow) async {
    final repo = ref.read(settingsRepositoryProvider);
    final push = ref.read(pushServiceProvider);
    var allowed = allow;
    if (allow && push != null) {
      allowed = await push.requestPermission() == PushPermission.granted;
      if (!allowed && context.mounted) await _explainDenied(context);
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
    if (!context.mounted) return;
    if (next != null) {
      context.go(next!);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  /// The phone blocked notifications. Android/iOS won't show the popup again,
  /// so the only way is the phone's settings.
  Future<void> _explainDenied(BuildContext context) async {
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
  Widget build(BuildContext context, WidgetRef ref) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kStatusBarDark,
      child: Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: FillScrollView(
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryContainer.withValues(alpha: 0.5)),
                alignment: Alignment.center,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryContainer),
                  child: Stack(alignment: Alignment.center, children: [
                    const Icon(Icons.notifications_rounded, size: 76, color: AppColors.primary),
                    Positioned(
                      right: 26,
                      top: 24,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.surface, width: 3),
                        ),
                        child: const Icon(Icons.add_rounded, color: AppColors.onPrimary, size: 20),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: Gap.xl),
              Text('Never miss your turn', style: AppText.headline, textAlign: TextAlign.center),
              const SizedBox(height: Gap.md),
              Text(
                "We'll alert you when 3, 2 and 1 patients are ahead, and when it's your turn.",
                textAlign: TextAlign.center,
                style: AppText.bodyLarge.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: Gap.xl),
              Container(
                padding: const EdgeInsets.all(Gap.lg),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(Radii.card)),
                child: Column(children: [
                  _step(const Text('3'), 'Start heading to the clinic'),
                  _step(const Text('2'), '2 patients ahead of you'),
                  _step(const Text('1'), "You're next, be at reception"),
                  _step(const Icon(Icons.check_rounded, size: 16, color: AppColors.onPrimary), 'Your turn now', filled: true),
                ]),
              ),
              const Spacer(),
              FilledButton(onPressed: () => _finish(context, ref, true), child: const Text('Allow notifications')),
              const SizedBox(height: Gap.sm),
              TextButton(onPressed: () => _finish(context, ref, false), child: const Text('Not now')),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _step(Widget leading, String text, {bool filled = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.sm),
        child: Row(children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: filled ? AppColors.primary : AppColors.primaryContainer),
            child: DefaultTextStyle(style: AppText.labelMedium.copyWith(color: AppColors.primary), child: leading),
          ),
          const SizedBox(width: Gap.md),
          Expanded(child: Text(text, style: AppText.labelMedium)),
        ]),
      );
}
