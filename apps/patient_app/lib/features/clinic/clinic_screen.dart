import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:asani_ui/asani_ui.dart';
import '../../core/utils/launch.dart';
import '../../core/widgets/drawn_map.dart';
import '../../data/location_service.dart';
import '../../data/providers.dart';
import '../../core/widgets/error_state.dart';
import '../doctor_search/doctor_search_providers.dart';
import '../doctor_search/doctors_tab.dart' show weeklyTimings;
import 'clinic_card.dart' show clinicInitials, clinicOpenInfo;

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
          SliverToBoxAdapter(child: ClinicHeader(clinic: clinic)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Gap.screen, 14, Gap.screen, Gap.xxl),
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
                Expanded(child: Text('Choose a doctor', style: AppText.titleSmall.copyWith(fontWeight: FontWeight.w700))),
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

/// Board P3 S-07 header: back, "Clinic", call; the clinic tile with name and
/// "2.1 km · 3 doctors · Open now"; a cream card with the address, a
/// directions button and the drawn map (tap opens Google Maps).
class ClinicHeader extends ConsumerWidget {
  const ClinicHeader({super.key, required this.clinic, this.title = 'Clinic'});
  final String title;
  final Clinic clinic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctors = ref.watch(doctorsProvider(clinic.id)).value ?? const <Doctor>[];
    final info = clinicOpenInfo(doctors, nowFrom(ref));
    final me = ref.watch(userLocationProvider).value;
    final km = me == null || clinic.location == null ? null : distanceKm(me, clinic.location!);
    final count = doctors.isNotEmpty ? doctors.length : clinic.doctorCount;
    final facts = [
      if (km != null) '${km < 10 ? km.toStringAsFixed(1) : km.round()} km',
      '$count ${count == 1 ? 'doctor' : 'doctors'}',
      if (!clinic.status.acceptsBookings) 'Booking paused' else (info.open ? 'Open now' : info.label),
    ].join(' · ');

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, Gap.sm, 20, 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const HeaderBackButton(),
              Expanded(
                child: Text(title,
                    textAlign: TextAlign.center,
                    style: AppText.labelLarge.copyWith(color: AppColors.onPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              Semantics(
                button: true,
                label: 'Call clinic',
                excludeSemantics: true,
                child: Material(
                  color: AppColors.primaryMid,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => callNumber(context, clinic.phone),
                    child: const SizedBox.square(dimension: 44, child: Icon(Icons.call_outlined, size: 19, color: AppColors.onPrimary)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(16)),
                child: ExcludeSemantics(
                  child: Text(clinicInitials(clinic.name),
                      style: AppText.titleMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(clinic.name,
                      style: AppText.titleMedium.copyWith(color: AppColors.onPrimary, fontSize: 19, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(facts, style: AppText.labelSmall.copyWith(color: AppColors.onPrimaryMuted)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
                  child: Row(children: [
                    Expanded(child: Text(clinic.address, style: AppText.labelSmall.copyWith(fontSize: 13, color: AppColors.textPrimary))),
                    const SizedBox(width: Gap.sm),
                    Semantics(
                      button: true,
                      label: 'Directions',
                      excludeSemantics: true,
                      child: Material(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => openDirections(context, clinic),
                          child: const SizedBox.square(dimension: 40, child: Icon(Icons.near_me_outlined, size: 17, color: AppColors.onPrimary)),
                        ),
                      ),
                    ),
                  ]),
                ),
                GestureDetector(
                  onTap: () => openDirections(context, clinic),
                  child: DrawnMap(label: clinic.name.split(' ').first),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Board P3 S-07 doctor card. Working today: name, letter, speciality and
/// a status chip; today's timing and bookings; Now serving / In queue /
/// Est. wait; a bar for how full the day is; Book token. Not working today:
/// one quiet row with the reason and "Another day".
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
    final canBookClinic = clinic.status.acceptsBookings;
    final also = ref.watch(alsoSitsAtProvider((doctor.doctorGroupId, doctor.id)));

    final quiet = availability == DoctorAvailability.onLeave ||
        availability == DoctorAvailability.notScheduled ||
        availability == DoctorAvailability.ended;
    if (quiet) {
      final reason = switch (availability) {
        DoctorAvailability.onLeave => 'On leave today',
        DoctorAvailability.ended => 'Session ended for today',
        _ => 'Not at this clinic today',
      };
      return Padding(
        padding: const EdgeInsets.only(bottom: Gap.md),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              DoctorFace(name: doctor.name, dot: null, quiet: true),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(doctor.name,
                      style: AppText.labelLarge.copyWith(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(reason, style: AppText.labelSmall.copyWith(color: AppColors.dangerText)),
                ]),
              ),
              if (canBookClinic)
                TextButton(onPressed: () => context.push('/book/${clinic.id}/${doctor.id}'), child: const Text('Another day ›')),
            ]),
            for (final o in also) _AlsoAt(o: o),
          ]),
        ),
      );
    }

    final session = day?.sessionStatus;
    final (chip, chipBg, chipFg) = switch (session) {
      SessionStatus.running => ('● Running', AppColors.successContainer, AppColors.successText),
      SessionStatus.paused => ('❚❚ Paused', AppColors.warningContainer, AppColors.warningText),
      _ => availability == DoctorAvailability.full
          ? ('Full today', AppColors.dangerContainer, AppColors.dangerText)
          : ('Not started', AppColors.cream, AppColors.textSecondary),
    };
    final booked = day?.bookedCount ?? 0;
    final fill = doctor.maxTokensPerDay == 0 ? 0.0 : (booked / doctor.maxTokensPerDay).clamp(0.0, 1.0);
    final live = session == SessionStatus.running || session == SessionStatus.paused;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            DoctorFace(name: doctor.name, dot: AppColors.success),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(doctor.name,
                        style: AppText.labelLarge.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(Radii.pill)),
                    child: Text(doctor.tokenPrefix,
                        style: AppText.labelSmall.copyWith(color: AppColors.onPrimary, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ]),
                Text(doctor.specialityEnum.display, style: AppText.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: Gap.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(Radii.pill)),
              child: Text(chip, style: AppText.labelSmall.copyWith(color: chipFg, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 11),
          Row(children: [
            Expanded(
              child: Text(schedule == null ? 'Today' : 'Today · ${Fmt.timeRange(schedule)}',
                  style: AppText.labelSmall.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
            ),
            Text('$booked of ${doctor.maxTokensPerDay} booked', style: AppText.labelSmall),
          ]),
          if (live && day != null) ...[
            const SizedBox(height: 11),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(14)),
              child: IntrinsicHeight(
                child: Row(children: [
                  QueueStat('Now serving', day.currentToken == 0 ? '—' : doctor.tokenLabel(day.currentToken), AppColors.primary),
                  const VerticalDivider(width: 24, color: AppColors.border),
                  QueueStat('In queue', '${day.waitingCount}', AppColors.textPrimary),
                  const VerticalDivider(width: 24, color: AppColors.border),
                  QueueStat('Est. wait', '~${Fmt.wait(estimatedWaitMinutes(day.waitingCount, doctor.avgConsultMinutes))}', AppColors.textPrimary),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 11),
          Semantics(
            label: '$booked of ${doctor.maxTokensPerDay} tokens booked today',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: fill,
                minHeight: 6,
                backgroundColor: AppColors.cream,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ),
          for (final o in also) _AlsoAt(o: o),
          if (canBookClinic) ...[
            const SizedBox(height: 11),
            FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => context.push('/book/${clinic.id}/${doctor.id}'),
              child: Text(availability.canBook ? 'Book token ›' : 'Book another day ›'),
            ),
          ],
        ]),
      ),
    );
  }
}

class QueueStat extends StatelessWidget {
  const QueueStat(this.label, this.value, this.color, {super.key});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppText.labelSmall.copyWith(fontSize: 11)),
          Text(value,
              style: AppText.labelMedium.copyWith(color: color, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      );
}

/// Doctor initials with a small status dot (green = working today).
class DoctorFace extends StatelessWidget {
  const DoctorFace({super.key, required this.name, required this.dot, this.quiet = false});
  final String name;
  final Color? dot;
  final bool quiet;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 48,
        child: Stack(children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: quiet ? AppColors.cream : AppColors.primaryContainer, shape: BoxShape.circle),
            child: Text(Fmt.initials(name),
                style: AppText.labelLarge.copyWith(color: quiet ? AppColors.textSecondary : AppColors.primary, fontWeight: FontWeight.w700)),
          ),
          if (dot != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle, border: Border.all(color: AppColors.surface, width: 2)),
              ),
            ),
        ]),
      );
}

/// D-32: the same doctor at another clinic in this city.
class _AlsoAt extends StatelessWidget {
  const _AlsoAt({required this.o});
  final ({Doctor doctor, Clinic clinic}) o;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => context.push('/book/${o.clinic.id}/${o.doctor.id}'),
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Also sits at '),
                  TextSpan(text: o.clinic.name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                  TextSpan(text: ' · ${weeklyTimings(o.doctor)}'),
                ]),
                style: AppText.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.primary),
          ]),
        ),
      );
}
