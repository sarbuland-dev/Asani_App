import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/providers.dart';
import '../home/home_screen.dart' show followUpBookingPath;
import 'profile_form.dart';

/// S-15 profile detail: follow-ups + visit history (PRD F-08, F-09).
class ProfileDetailScreen extends ConsumerWidget {
  const ProfileDetailScreen({super.key, required this.patientId});
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patients = ref.watch(myPatientsProvider);
    final patient = patients.value?.where((p) => p.id == patientId).firstOrNull;
    if (patient == null) {
      return Scaffold(
        appBar: AppBar(),
        body: patients.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const EmptyState(icon: Icons.person_off_outlined, title: 'Profile not found', message: 'This profile was removed.'),
      );
    }
    final tokens = (ref.watch(myTokensProvider).value ?? const <Token>[]).where((t) => t.patientId == patientId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final history = tokens.where((t) => !t.status.isActive).toList();
    final active = tokens.where((t) => t.status.isActive).toList();
    final followUps = ref.watch(upcomingFollowUpsProvider).where((f) => f.patientId == patientId).toList();
    final (bg, fg) = InitialsAvatar.colorsFor(patient.relation);

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHeader(
            padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.md, Gap.screen, Gap.xl),
            child: Column(children: [
              Row(children: [
                const HeaderBackButton(),
                const Spacer(),
                HeaderBackButton(icon: Icons.edit_outlined, onPressed: () => context.push('/family/${patient.id}/edit')),
              ]),
              InitialsAvatar(name: patient.name, size: 84, bg: bg, fg: fg),
              const SizedBox(height: Gap.md),
              Text(patient.name, style: AppText.titleLarge.copyWith(color: AppColors.onPrimary, fontSize: 24)),
              const SizedBox(height: 2),
              Text(patientSubtitle(patient), style: AppText.bodyLarge.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.9))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.screen, 0, Gap.screen, Gap.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (active.isNotEmpty) ...[
                  const SectionTitle('Active tokens'),
                  for (final t in active) _HistoryItem(token: t, last: t == active.last),
                ],
                if (followUps.isNotEmpty) ...[
                  const SectionTitle('Upcoming follow-up'),
                  for (final f in followUps) _FollowUpTile(followUp: f),
                ],
                SectionTitle(
                  'Visit history',
                  trailing: Text('${history.where((t) => t.status == TokenStatus.completed).length} visits', style: AppText.labelSmall),
                ),
                if (history.isEmpty)
                  Text('No visits yet.', style: AppText.bodyMedium)
                else
                  for (final t in history) _HistoryItem(token: t, last: t == history.last),
                const SizedBox(height: Gap.xl),
                FilledButton(
                  onPressed: () => context.go('/home'),
                  child: Text('Book a token for ${patient.name.split(' ').first}'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowUpTile extends ConsumerWidget {
  const _FollowUpTile({required this.followUp});
  final FollowUp followUp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctor = ref.watch(doctorProvider(followUp.doctorId)).value;
    return AppCard(
      padding: const EdgeInsets.all(Gap.md),
      child: Row(children: [
        const IconBox(icon: Icons.event_outlined, bg: AppColors.warningContainer, fg: AppColors.warning),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(doctor?.name ?? '', style: AppText.labelLarge),
            Text('Due ${Fmt.shortDay(followUp.dueDate)}', style: AppText.bodyMedium),
            const SizedBox(height: 4),
            Pill(label: followUp.status.label, fg: AppColors.warning, bg: AppColors.warningContainer),
          ]),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(72, 44)),
          onPressed: () => context.push(followUpBookingPath(followUp)),
          child: const Text('Book'),
        ),
      ]),
    );
  }
}

/// Timeline item: date, status, clinic · doctor, token #, wait time.
class _HistoryItem extends ConsumerWidget {
  const _HistoryItem({required this.token, required this.last});
  final Token token;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctor = ref.watch(doctorProvider(token.doctorId)).value;
    final clinic = ref.watch(clinicProvider(token.clinicId)).value;
    final completed = token.status == TokenStatus.completed;
    final dotColor = completed ? AppColors.success : (token.status.isActive ? AppColors.primary : AppColors.danger);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 24,
          child: Column(children: [
            const SizedBox(height: 18),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: dotColor, width: 2.5), color: AppColors.surface),
            ),
            if (!last) Expanded(child: Container(width: 2, color: AppColors.border)),
          ]),
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: AppCard(
              onTap: () => context.push('/token/${token.id}'),
              padding: const EdgeInsets.all(Gap.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(Fmt.longDay(token.date), style: AppText.labelLarge)),
                  StatusChip(token.status),
                ]),
                const SizedBox(height: 2),
                Text('${clinic?.name ?? ''} · ${doctor?.name ?? ''}', style: AppText.bodyMedium),
                const SizedBox(height: Gap.sm),
                Wrap(spacing: Gap.sm, runSpacing: Gap.xs, children: [
                  Pill(label: 'Token ${token.label}', fg: AppColors.textSecondary, bg: AppColors.muted),
                  if (completed && token.waitedMinutes != null)
                    Pill(label: 'Waited ${token.waitedMinutes} min', fg: AppColors.textSecondary, bg: AppColors.muted),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
