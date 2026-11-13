import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:asani_ui/asani_ui.dart';
import '../../data/providers.dart';
import '../shell/main_shell.dart';
import 'profile_form.dart';
import '../../core/widgets/error_state.dart';

/// S-13 Family tab (PRD F-07).
class FamilyScreen extends ConsumerWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patients = ref.watch(myPatientsProvider);
    final tokens = ref.watch(myTokensProvider).value ?? const [];
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GradientHeader(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: Gap.sm),
              Text('Family', style: AppText.displaySmall.copyWith(color: AppColors.onPrimary, fontSize: 28)),
              const SizedBox(height: Gap.xs),
              Text('Book tokens for anyone in your family.',
                  style: AppText.bodyLarge.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.9))),
            ]),
          ),
          Expanded(
            child: patients.when(
              loading: () => const Padding(padding: EdgeInsets.all(Gap.screen), child: SkeletonList()),
              error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(myPatientsProvider)),
              data: (list) => ListView(
                padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.lg, Gap.screen, kNavBarClearance),
                children: [
                  for (final p in list)
                    Builder(builder: (context) {
                      final visits = tokens.where((t) => t.patientId == p.id && t.status.name == 'completed').length;
                      final (bg, fg) = InitialsAvatar.colorsFor(p.relation);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: Gap.md),
                        child: AppCard(
                          onTap: () => context.push('/family/${p.id}'),
                          padding: const EdgeInsets.all(Gap.md),
                          child: Row(children: [
                            InitialsAvatar(name: p.name, size: 52, bg: bg, fg: fg),
                            const SizedBox(width: Gap.md),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(p.name, style: AppText.titleMedium.copyWith(fontSize: 17)),
                                Text(patientSubtitle(p, shortGender: true), style: AppText.bodyMedium),
                              ]),
                            ),
                            Pill(label: '$visits ${visits == 1 ? 'visit' : 'visits'}', fg: AppColors.textSecondary, bg: AppColors.muted),
                            const SizedBox(width: Gap.xs),
                            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                          ]),
                        ),
                      );
                    }),
                  const SizedBox(height: Gap.sm),
                  SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/family/new'),
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Add family member'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
