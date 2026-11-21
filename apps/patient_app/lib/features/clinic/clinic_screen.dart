import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:asani_ui/asani_ui.dart';
import '../../core/utils/launch.dart';
import '../../data/providers.dart';
import '../../core/widgets/error_state.dart';
import '../doctor_search/doctor_search_providers.dart';
import '../doctor_search/doctors_tab.dart' show weeklyTimings;

/// S-07 Clinic page: choose a doctor (PRD F-03).
class ClinicScreen extends ConsumerStatefulWidget {
  const ClinicScreen({super.key, required this.clinicId});
  final String clinicId;

  @override
  ConsumerState<ClinicScreen> createState() => _ClinicScreenState();
}

class _ClinicScreenState extends ConsumerState<ClinicScreen> {
  bool _redirected = false;

  @override
  Widget build(BuildContext context) {
    final clinicAsync = ref.watch(clinicProvider(widget.clinicId));
    final doctorsAsync = ref.watch(doctorsProvider(widget.clinicId));
    final clinic = clinicAsync.value;
    final doctors = doctorsAsync.value;

    // Exactly one doctor → go straight to booking (PRD F-03).
    if (!_redirected && clinic != null && clinic.status.acceptsBookings && doctors != null && doctors.length == 1) {
      _redirected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pushReplacement('/book/${clinic.id}/${doctors.first.id}');
      });
    }

    if (clinicAsync.hasError) {
      return StatusBarScrim(
      child: Scaffold(appBar: AppBar(), body: ErrorState(error: clinicAsync.error, onRetry: () => ref.invalidate(clinicProvider(widget.clinicId)))));
    }
    if (clinicAsync.isLoading && clinic == null) {
      return const LoadingScreen(message: 'Loading clinic…');
    }
    if (clinic == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.local_hospital_outlined, title: 'Clinic not found', message: 'This clinic link is not valid any more.'),
      );
    }
    final now = nowFrom(ref);

    return StatusBarScrim(
      child: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _ClinicHeader(clinic: clinic)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.xl, Gap.screen, Gap.xxl),
            sliver: SliverList.list(children: [
              if (!clinic.status.acceptsBookings)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.lg),
                  child: AppCard(
                    color: AppColors.warningContainer,
                    borderColor: AppColors.warningContainer,
                    child: Row(children: [
                      const Icon(Icons.info_outline_rounded, color: AppColors.warning),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: Text('Online booking is not available for this clinic right now.',
                            style: AppText.bodyLarge.copyWith(color: AppColors.warning)),
                      ),
                    ]),
                  ),
                ),
              Row(children: [
                Expanded(child: Text('Choose a doctor', style: AppText.titleLarge)),
                Text(Fmt.relativeDay(dayKey(now)).replaceFirst('Today, ', 'Today, ${_weekday(now)} '),
                    style: AppText.labelMedium.copyWith(color: AppColors.textSecondary)),
              ]),
              const SizedBox(height: Gap.md),
              ...doctorsAsync.when(
                loading: () => [const SkeletonList(height: 200)],
                error: (e, _) => [ErrorState(error: e, onRetry: () => ref.invalidate(doctorsProvider(widget.clinicId)))],
                data: (list) => list.isEmpty
                    ? [const EmptyState(icon: Icons.medical_services_outlined, title: 'No doctors listed', message: 'This clinic has not added doctors yet.')]
                    : [for (final d in list) _DoctorCard(clinic: clinic, doctor: d)],
              ),
            ]),
          ),
        ],
      ),
    ));
  }

  String _weekday(DateTime d) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
}

class _ClinicHeader extends StatelessWidget {
  const _ClinicHeader({required this.clinic});
  final Clinic clinic;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.md, Gap.screen, Gap.xl),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HeaderBackButton(),
          const SizedBox(height: Gap.lg),
          Row(children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.card)),
              child: ExcludeSemantics(
                child: Text(
                  Fmt.initials(clinic.name.replaceAll(RegExp(r'\b(Clinic|Medical|Hospital|Centre|Center)\b'), '').replaceAll('-', ' ')),
                  style: AppText.titleMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(clinic.name, style: AppText.titleLarge.copyWith(color: AppColors.onPrimary)),
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 16, color: AppColors.onPrimary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(clinic.address, style: AppText.bodyMedium.copyWith(color: AppColors.primaryContainer)),
                  ),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: Gap.lg),
          Row(children: [
            Expanded(
              child: _HeaderAction(icon: Icons.call_outlined, label: 'Call', onTap: () => callNumber(context, clinic.phone)),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: _HeaderAction(icon: Icons.near_me_outlined, label: 'Directions', onTap: () => openDirections(context, clinic)),
            ),
          ]),
        ],
      ),
        ),
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: Gap.sm),
              Text(label, style: AppText.labelMedium.copyWith(color: AppColors.primary)),
            ]),
          ),
        ),
      );
}

class _DoctorCard extends ConsumerWidget {
  const _DoctorCard({required this.clinic, required this.doctor});
  final Clinic clinic;
  final Doctor doctor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = nowFrom(ref);
    final today = dayKey(now);
    final day = ref.watch(queueDayProvider((doctorId: doctor.id, date: today))).value;
    final availability = availabilityFor(doctor: doctor, date: now, day: day, now: now);
    final schedule = doctor.scheduleOn(now);
    final greyed = !availability.canBook;
    final canBookClinic = clinic.status.acceptsBookings;
    final running = day?.sessionStatus == SessionStatus.running || day?.sessionStatus == SessionStatus.paused;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Opacity(
        opacity: greyed ? 0.85 : 1,
        child: AppCard(
          color: greyed ? AppColors.muted.withValues(alpha: 0.6) : AppColors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InitialsAvatar(
                    name: doctor.name,
                    size: 52,
                    bg: greyed ? AppColors.border : AppColors.primaryContainer,
                    fg: greyed ? AppColors.textSecondary : AppColors.primary,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(doctor.name, style: AppText.titleMedium, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: Gap.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                          decoration: BoxDecoration(
                            color: greyed ? AppColors.border : AppColors.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(doctor.tokenPrefix,
                              style: AppText.labelSmall.copyWith(
                                  color: greyed ? AppColors.textSecondary : AppColors.onPrimary, fontWeight: FontWeight.w700)),
                        ),
                      ]),
                      Text(doctor.speciality, style: AppText.bodyMedium),
                      const SizedBox(height: Gap.sm),
                      AvailabilityPill(availability: availability, schedule: schedule),
                    ]),
                  ),
                ],
              ),
              if (availability == DoctorAvailability.available && running && day != null) ...[
                const SizedBox(height: Gap.md),
                if (day.sessionStatus == SessionStatus.paused) ...[
                  Text('Queue is paused for a moment', style: AppText.labelMedium.copyWith(color: AppColors.warning)),
                  const SizedBox(height: Gap.sm),
                ],
                // Equal-height tiles even when one value is longer ("Any moment").
                IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    child: StatTile(
                        label: 'Now serving',
                        value: day.currentToken == 0 ? '—' : doctor.tokenLabel(day.currentToken),
                        big: false),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(child: StatTile(label: 'Waiting', value: '${day.waitingCount}', big: false)),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: StatTile(
                        label: 'Est. wait',
                        value: Fmt.wait(estimatedWaitMinutes(day.waitingCount, doctor.avgConsultMinutes)),
                        big: false),
                  ),
                ])),
              ],
              // D-32: the same doctor at other clinics in this city (linked by the Super Admin).
              for (final o in ref.watch(alsoSitsAtProvider((doctor.doctorGroupId, doctor.id))))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Also sits at: ${o.clinic.name} · ${o.clinic.area}'),
                  subtitle: Text(weeklyTimings(o.doctor)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/book/${o.clinic.id}/${o.doctor.id}'),
                ),
              if (canBookClinic) ...[
                if (availability == DoctorAvailability.notStarted && day != null && day.bookedCount > 0) ...[
                  const SizedBox(height: Gap.sm),
                  Text('${day.bookedCount} tokens booked so far', style: AppText.labelSmall),
                ],
                const SizedBox(height: Gap.md),
                if (availability.canBook)
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => context.push('/book/${clinic.id}/${doctor.id}'),
                    child: const Text('Book token'),
                  )
                else
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => context.push('/book/${clinic.id}/${doctor.id}'),
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: const Text('Book another day'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
