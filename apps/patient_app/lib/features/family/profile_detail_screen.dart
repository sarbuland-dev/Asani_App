import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:asani_ui/asani_ui.dart';
import '../../data/providers.dart';
import '../home/home_screen.dart' show followUpBookingPath;
import 'profile_form.dart';
import '../../core/widgets/bottom_clearance.dart';

/// S-15 profile detail (PRD F-08, F-09; board P6): green header with back,
/// "Profile" and Edit, the person, and Visits · n | Follow-ups · n tabs.
/// Visits: the next follow-up (lime) then every token, newest first.
class ProfileDetailScreen extends ConsumerStatefulWidget {
  const ProfileDetailScreen({super.key, required this.patientId});
  final String patientId;

  @override
  ConsumerState<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends ConsumerState<ProfileDetailScreen> {
  bool _followUps = false;

  @override
  Widget build(BuildContext context) {
    final patients = ref.watch(myPatientsProvider);
    final patient = patients.value?.where((p) => p.id == widget.patientId).firstOrNull;
    if (patient == null) {
      return StatusBarScrim(
        child: Scaffold(
          appBar: AppBar(),
          body: patients.isLoading
              ? const Center(child: AsaniLoader())
              : const EmptyState(icon: Icons.person_off_outlined, title: 'Profile not found', message: 'This profile was removed.'),
        ),
      );
    }
    final tokens = (ref.watch(myTokensProvider).value ?? const <Token>[]).where((t) => t.patientId == widget.patientId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final followUps = ref.watch(upcomingFollowUpsProvider).where((f) => f.patientId == widget.patientId).toList();
    final visits = tokens.where((t) => t.status == TokenStatus.completed).length;

    Widget tab(String label, bool on, VoidCallback onTap) => Expanded(
          child: Semantics(
            button: true,
            selected: on,
            child: InkWell(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: on ? AppColors.onPrimary : Colors.transparent, width: 3)),
                ),
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: AppText.labelMedium.copyWith(color: on ? AppColors.onPrimary : AppColors.primarySoft, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        );

    return StatusBarScrim(
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header)),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, Gap.sm, 20, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      const HeaderBackButton(),
                      Expanded(
                        child: Text('Profile',
                            textAlign: TextAlign.center,
                            style: AppText.labelLarge.copyWith(color: AppColors.onPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: AppColors.onPrimary),
                        onPressed: () => context.push('/family/${patient.id}/edit'),
                        child: const Text('Edit'),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    Row(children: [
                      Container(
                        width: 60,
                        height: 60,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: AppColors.cream, shape: BoxShape.circle),
                        child: Text(Fmt.initials(patient.name),
                            style: AppText.titleMedium.copyWith(color: AppColors.primary, fontSize: 20, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(patient.name,
                              style: AppText.titleMedium.copyWith(color: AppColors.onPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
                          Text(patientSubtitle(patient), style: AppText.labelSmall.copyWith(color: AppColors.onPrimaryMuted, fontSize: 13)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: Gap.sm),
                    Row(children: [
                      tab('Visits · $visits', !_followUps, () => setState(() => _followUps = false)),
                      tab('Follow-ups · ${followUps.length}', _followUps, () => setState(() => _followUps = true)),
                    ]),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottomClearance(context)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_followUps) ...[
                  if (followUps.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Gap.xl),
                      child: Text('No follow-ups due.', textAlign: TextAlign.center, style: AppText.bodyMedium),
                    ),
                  for (final f in followUps) _FollowUpCard(followUp: f),
                ] else ...[
                  if (followUps.isNotEmpty) _FollowUpCard(followUp: followUps.first),
                  if (tokens.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Gap.xl),
                      child: Text('No visits yet.', textAlign: TextAlign.center, style: AppText.bodyMedium),
                    ),
                  for (final t in tokens) _VisitCard(token: t),
                  const SizedBox(height: Gap.md),
                  FilledButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('Book a token'),
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lime follow-up card with Book (board P6).
class _FollowUpCard extends ConsumerWidget {
  const _FollowUpCard({required this.followUp});
  final FollowUp followUp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctor = ref.watch(doctorProvider(followUp.doctorId)).value;
    final doc = (doctor?.name ?? '').split(' ').take(2).join(' ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(gradient: AppColors.limeGradient, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('FOLLOW-UP DUE',
                  style: AppText.labelSmall.copyWith(color: AppColors.onLimeMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              Text('${Fmt.shortDay(followUp.dueDate)} · $doc',
                  style: AppText.labelMedium.copyWith(color: AppColors.onLime, fontWeight: FontWeight.w700)),
            ]),
          ),
          Material(
            color: AppColors.onLime,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => context.push(followUpBookingPath(followUp)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text('Book', style: AppText.labelMedium.copyWith(color: AppColors.cream, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// One visit: token tile, date, doctor · clinic · wait, and a status chip.
class _VisitCard extends ConsumerWidget {
  const _VisitCard({required this.token});
  final Token token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctor = ref.watch(doctorProvider(token.doctorId)).value;
    final clinic = ref.watch(clinicProvider(token.clinicId)).value;
    final status = token.status;
    final completed = status == TokenStatus.completed;
    final (chip, bg, fg) = switch (status) {
      TokenStatus.completed => ('Done', AppColors.successContainer, AppColors.successText),
      TokenStatus.cancelled => ('Cancelled', AppColors.dangerContainer, AppColors.dangerText),
      TokenStatus.noShow => ('Missed', AppColors.warningContainer, AppColors.warningText),
      _ when status.isOpenForPatient => ('Active', AppColors.primaryContainer, AppColors.primary),
      _ => (status.label, AppColors.cream, AppColors.textSecondary),
    };
    final doc = (doctor?.name ?? '').split(' ').take(2).join(' ');
    final sub = [
      doc,
      clinic?.name ?? '',
      if (completed && token.waitedMinutes != null) 'waited ${token.waitedMinutes} min',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/token/${token.id}'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(14)),
                child: FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(token.label,
                        style: AppText.labelLarge.copyWith(
                            color: completed || status.isOpenForPatient ? AppColors.primary : AppColors.textSecondary,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(Fmt.shortDay(token.date), style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700)),
                  Text(sub, style: AppText.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              const SizedBox(width: Gap.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.pill)),
                child: Text(chip, style: AppText.labelSmall.copyWith(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
