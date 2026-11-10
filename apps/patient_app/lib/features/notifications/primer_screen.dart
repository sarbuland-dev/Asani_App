import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/providers.dart';

/// S-17 notification permission primer, shown once before the first booking.
/// The system permission request is added with FCM (push_service).
class PrimerScreen extends ConsumerWidget {
  const PrimerScreen({super.key, this.next});
  final String? next;

  Future<void> _finish(BuildContext context, WidgetRef ref, bool allow) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.update(repo.settings.copyWith(primerShown: true, notificationsAllowed: allow ? true : null));
    if (!context.mounted) return;
    if (next != null) {
      context.go(next!);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
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
              Text('Never miss your turn', style: AppText.displaySmall.copyWith(fontSize: 28), textAlign: TextAlign.center),
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
    );
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
