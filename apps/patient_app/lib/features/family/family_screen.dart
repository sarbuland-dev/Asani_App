import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:asani_ui/asani_ui.dart';
import '../../data/providers.dart';
import '../shell/main_shell.dart';
import 'profile_form.dart';
import '../../core/widgets/error_state.dart';

/// S-13 Family tab (PRD F-07, board P6): green header with how many profiles
/// are on this number and a cream "+"; a 2-column grid of profile cards
/// (initials, name, relation · age · sex, and visits or "Follow-up due").
class FamilyScreen extends ConsumerWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patients = ref.watch(myPatientsProvider);
    final tokens = ref.watch(myTokensProvider).value ?? const <Token>[];
    final followUps = ref.watch(upcomingFollowUpsProvider);
    final phone = ref.watch(currentUserProvider)?.phone;
    final count = patients.value?.length;

    return StatusBarScrim(
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header)),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, Gap.xl, 20, 18),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Family',
                            style: AppText.headline.copyWith(color: AppColors.onPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          count == null
                              ? 'Book tokens for anyone in your family.'
                              : '$count ${count == 1 ? 'profile' : 'profiles'}${phone == null ? '' : ' on ${Fmt.phone(phone)}'}',
                          style: AppText.labelSmall.copyWith(color: AppColors.onPrimaryMuted, fontSize: 13),
                        ),
                      ]),
                    ),
                    Semantics(
                      button: true,
                      label: 'Add family member',
                      excludeSemantics: true,
                      child: Material(
                        color: AppColors.cream,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => context.push('/family/new'),
                          child: const SizedBox.square(dimension: 44, child: Icon(Icons.add_rounded, color: AppColors.primary, size: 26)),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            Expanded(
              child: patients.when(
                loading: () => const Padding(padding: EdgeInsets.all(Gap.screen), child: SkeletonList()),
                error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(myPatientsProvider)),
                data: (list) => GridView(
                  padding: const EdgeInsets.fromLTRB(20, Gap.lg, 20, kNavBarClearance),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    // Grows with the text size so nothing clips.
                    mainAxisExtent: 120 + 56 * MediaQuery.textScalerOf(context).scale(14) / 14,
                  ),
                  children: [
                    for (final p in list)
                      _ProfileCard(
                        patient: p,
                        visits: tokens.where((t) => t.patientId == p.id && t.status == TokenStatus.completed).length,
                        followUpDue: followUps.any((f) => f.patientId == p.id),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.patient, required this.visits, required this.followUpDue});
  final Patient patient;
  final int visits;
  final bool followUpDue;

  @override
  Widget build(BuildContext context) {
    final self = patient.isSelf;
    return Semantics(
      button: true,
      label: '${patient.name}, ${patientSubtitle(patient)}. ${followUpDue ? 'Follow-up due' : '$visits visits'}',
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/family/${patient.id}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: self ? AppColors.primary : AppColors.primaryContainer, shape: BoxShape.circle),
                child: Text(Fmt.initials(patient.name),
                    style: AppText.labelMedium.copyWith(color: self ? AppColors.onPrimary : AppColors.primary, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 10),
              Text(patient.name, style: AppText.labelLarge.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(patientSubtitle(patient, shortGender: true), style: AppText.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: followUpDue ? AppColors.primary : AppColors.cream,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(
                  followUpDue ? 'Follow-up due' : '$visits ${visits == 1 ? 'visit' : 'visits'}',
                  style: AppText.labelSmall.copyWith(
                      fontSize: 11, fontWeight: FontWeight.w600, color: followUpDue ? AppColors.onPrimary : AppColors.textSecondary),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
