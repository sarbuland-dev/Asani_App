import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:asani_ui/asani_ui.dart';
import '../../core/utils/launch.dart';
import '../../data/providers.dart';
import '../../core/widgets/error_state.dart';

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
      return Scaffold(appBar: AppBar(), body: ErrorState(error: clinicAsync.error, onRetry: () => ref.invalidate(clinicProvider(widget.clinicId))));
    }
    if (clinicAsync.isLoading && clinic == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (clinic == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.local_hospital_outlined, title: 'Clinic not found', message: 'This clinic link is not valid any more.'),
      );
    }
    final now = nowFrom(ref);

    return Scaffold(
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
                            style: AppText.bodyLarge.copyWith(color: AppColors.warning, fontSize: 15)),
                      ),
                    ]),
                  ),
                ),
              Row(children: [
                Expanded(child: Text('Choose a doctor', style: AppText.titleLarge.copyWith(fontSize: 20))),
                Text(Fmt.relativeDay(dayKey(now)).replaceFirst('Today, ', 'Today, ${_weekday(now)} '), style: AppText.labelSmall),
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
    );
  }

  String _weekday(DateTime d) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
}

class _ClinicHeader extends StatelessWidget {
  const _ClinicHeader({required this.clinic});
  final Clinic clinic;

  @override
  Widget build(BuildContext context) {
    return GradientHeader(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HeaderBackButton(),
          const SizedBox(height: Gap.lg),
          Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.card)),
              child: const Icon(Icons.local_hospital_outlined, color: AppColors.primary, size: 28),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(clinic.name, style: AppText.titleLarge.copyWith(color: AppColors.onPrimary, fontSize: 24)),
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 16, color: AppColors.onPrimary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(clinic.address,
                        style: AppText.bodyMedium.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.9))),
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
                Row(children: [
                  Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(day.sessionStatus == SessionStatus.paused ? 'QUEUE PAUSED' : 'LIVE QUEUE',
                      style: AppText.overline.copyWith(color: AppColors.primary, fontSize: 11)),
                ]),
                const SizedBox(height: Gap.sm),
                Row(children: [
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
                ]),
              ],
              if (canBookClinic) ...[
                const SizedBox(height: Gap.md),
                Row(children: [
                  if (availability == DoctorAvailability.notStarted && day != null && day.bookedCount > 0)
                    Expanded(child: Text('${day.bookedCount} tokens booked so far', style: AppText.labelSmall))
                  else
                    const Spacer(),
                  if (availability.canBook)
                    _BookButton(onTap: () => context.push('/book/${clinic.id}/${doctor.id}'))
                  else
                    OutlinedButton.icon(
                      onPressed: () => context.push('/book/${clinic.id}/${doctor.id}'),
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: const Text('Book another day'),
                    ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BookButton extends StatelessWidget {
  const _BookButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: Padding(
          padding: const EdgeInsets.only(left: Gap.md),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Book token', style: AppText.labelLarge.copyWith(color: AppColors.primary)),
            const SizedBox(width: Gap.sm),
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.arrow_forward_rounded, color: AppColors.onPrimary),
            ),
          ]),
        ),
      );
}
