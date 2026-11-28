import 'package:asani_core/asani_core.dart';
import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import 'clinic_screen.dart' show ClinicHeader, DoctorFace, QueueStat;
import '../../core/widgets/bottom_clearance.dart';
import '../../core/widgets/dead_end.dart';

/// S-07b Doctor profile (board P3b): opened from "Search by doctor" → Book
/// token, so the patient sees this doctor at this clinic before booking.
/// Clinic header (call, address, drawn map), the doctor card with today's
/// queue (or why not today and the next free day), the week's timings at
/// this clinic, and "Book for today" / "Book for Sat" + "Another day".
class DoctorProfileScreen extends ConsumerWidget {
  const DoctorProfileScreen({super.key, required this.clinicId, required this.doctorId});
  final String clinicId;
  final String doctorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinicAsync = ref.watch(clinicProvider(clinicId));
    final doctorAsync = ref.watch(doctorProvider(doctorId));
    final clinic = clinicAsync.value;
    final doctor = doctorAsync.value;
    if (clinicAsync.hasError || doctorAsync.hasError) {
      return LoadErrorScreen(
        error: clinicAsync.error ?? doctorAsync.error,
        onRetry: () {
          ref.invalidate(clinicProvider(clinicId));
          ref.invalidate(doctorProvider(doctorId));
        },
      );
    }
    if (clinic == null || doctor == null) {
      if (clinicAsync.isLoading || doctorAsync.isLoading) return const LoadingScreen(message: 'Loading doctor…');
      return const NotFoundScreen(
          icon: Icons.medical_services_outlined, title: 'Doctor not found', message: 'This doctor is no longer listed.');
    }

    final now = nowFrom(ref);
    final today = dayKey(now);
    final day = ref.watch(queueDayProvider((doctorId: doctor.id, date: today))).value;
    final availability = availabilityFor(doctor: doctor, date: now, day: day, now: now);
    final next = availability.canBook ? dateOnly(now) : _nextFreeDay(doctor, now);
    final canBookClinic = clinic.status.acceptsBookings;

    final String primary;
    final String? primaryDate;
    if (availability.canBook) {
      primary = 'Book for today ›';
      primaryDate = today;
    } else if (next != null) {
      primary = 'Book for ${_weekday(next)} ›';
      primaryDate = dayKey(next);
    } else {
      primary = 'Pick a day ›';
      primaryDate = null;
    }
    final bookPath = '/book/${clinic.id}/${doctor.id}';

    return StatusBarScrim(
      child: Scaffold(
        body: Column(children: [
          Expanded(
            child: CustomScrollView(slivers: [
              SliverToBoxAdapter(child: ClinicHeader(clinic: clinic, title: 'Doctor')),
              SliverPadding(
                // With the booking bar below, the bar clears the phone's buttons.
                padding: EdgeInsets.fromLTRB(18, 14, 18, canBookClinic ? Gap.xl : bottomClearance(context)),
                sliver: SliverList.list(children: [
                  _DoctorToday(doctor: doctor, day: day, availability: availability, next: next),
                  const SizedBox(height: Gap.md),
                  Text('Timings at ${clinic.name}', style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: Gap.sm),
                  _Timings(doctor: doctor, now: now, availability: availability, next: next),
                ]),
              ),
            ]),
          ),
          if (canBookClinic)
            Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, Gap.md, 20, Gap.lg),
                  child: Row(children: [
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        onPressed: () => context.push(primaryDate == null ? bookPath : '$bookPath?date=$primaryDate'),
                        child: Text(primary, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          side: const BorderSide(color: AppColors.primary, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () => context.push(bookPath),
                        child: const Text('Another day', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// The first day in the booking window the doctor sits and is not on leave.
DateTime? _nextFreeDay(Doctor d, DateTime now) {
  for (final date in bookingDates(d, now)) {
    if (dayKey(date) == dayKey(now)) continue; // today was already checked
    if (d.active && d.scheduleOn(date) != null && !d.onLeave(date)) return date;
  }
  return null;
}

String _weekday(DateTime d) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];

/// The doctor card. Working today: Running chip, timing and bookings, the
/// queue tiles and fill bar. Not today: a quiet card with the reason and a
/// "Next available" box.
class _DoctorToday extends StatelessWidget {
  const _DoctorToday({required this.doctor, required this.day, required this.availability, required this.next});
  final Doctor doctor;
  final QueueDay? day;
  final DoctorAvailability availability;
  final DateTime? next;

  @override
  Widget build(BuildContext context) {
    final ok = availability.canBook || availability == DoctorAvailability.full;
    final session = day?.sessionStatus;
    final schedule = doctor.scheduleOn(DateTime.now());

    final (chip, chipBg, chipFg) = switch (availability) {
      DoctorAvailability.onLeave => ('On leave', AppColors.dangerContainer, AppColors.dangerText),
      DoctorAvailability.ended => ('Session ended', AppColors.warningContainer, AppColors.warningText),
      DoctorAvailability.notScheduled => ('Not today', AppColors.cream, AppColors.textSecondary),
      DoctorAvailability.full => ('Full today', AppColors.dangerContainer, AppColors.dangerText),
      _ => switch (session) {
          SessionStatus.running => ('● Running', AppColors.successContainer, AppColors.successText),
          SessionStatus.paused => ('❚❚ Paused', AppColors.warningContainer, AppColors.warningText),
          _ => ('Not started', AppColors.cream, AppColors.textSecondary),
        },
    };

    final head = Row(children: [
      DoctorFace(name: doctor.name, dot: ok ? AppColors.success : null, quiet: !ok),
      const SizedBox(width: Gap.md),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(
              child: Text(doctor.name,
                  style: AppText.labelLarge.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
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
    ]);

    final children = <Widget>[head];
    if (ok) {
      final booked = day?.bookedCount ?? 0;
      final fill = doctor.maxTokensPerDay == 0 ? 0.0 : (booked / doctor.maxTokensPerDay).clamp(0.0, 1.0);
      children.addAll([
        const SizedBox(height: 11),
        Row(children: [
          Expanded(
            child: Text(schedule == null ? 'Today' : 'Today · ${Fmt.timeRange(schedule)}',
                style: AppText.labelSmall.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          ),
          Text('$booked of ${doctor.maxTokensPerDay} booked', style: AppText.labelSmall),
        ]),
        if (day != null && (session == SessionStatus.running || session == SessionStatus.paused)) ...[
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(14)),
            child: IntrinsicHeight(
              child: Row(children: [
                QueueStat('Now serving', day!.currentToken == 0 ? '—' : doctor.tokenLabel(day!.currentToken), AppColors.primary),
                const VerticalDivider(width: 20, color: AppColors.border),
                QueueStat('In queue', '${day!.waitingCount}', AppColors.textPrimary),
                const VerticalDivider(width: 20, color: AppColors.border),
                QueueStat('Est. wait', Fmt.wait(estimatedWaitMinutes(day!.waitingCount, doctor.avgConsultMinutes)),
                    AppColors.textPrimary),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 11),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: ExcludeSemantics(child: LinearProgressIndicator(
            value: fill,
            minHeight: 6,
            backgroundColor: AppColors.cream,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          )),
        ),
      ]);
    } else {
      final why = switch (availability) {
        DoctorAvailability.onLeave => 'The doctor is on leave today.',
        DoctorAvailability.ended => schedule == null ? "Today's session is over." : "Today's session (${Fmt.timeRange(schedule)}) is over.",
        _ => 'The doctor does not sit at this clinic today.',
      };
      final nextSched = next == null ? null : doctor.scheduleOn(next!);
      children.addAll([
        const SizedBox(height: 11),
        Text(why,
            style: AppText.labelSmall.copyWith(
                color: availability == DoctorAvailability.onLeave ? AppColors.dangerText : AppColors.textSecondary, height: 1.5)),
        if (next != null) ...[
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.onPrimary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Next available', style: AppText.labelSmall.copyWith(fontSize: 11, color: AppColors.primaryLight)),
                  Text('${Fmt.shortDay(dayKey(next!))}${nextSched == null ? '' : ' · ${Fmt.timeRange(nextSched)}'}',
                      style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),
        ],
      ]);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ok ? AppColors.surface : AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

/// The week at this clinic: same-timing days grouped ("Mon – Wed"), today
/// and the next free day called out in green, days off listed last.
class _Timings extends StatelessWidget {
  const _Timings({required this.doctor, required this.now, required this.availability, required this.next});
  final Doctor doctor;
  final DateTime now;
  final DoctorAvailability availability;
  final DateTime? next;

  static const _keys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  static const _names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final todayIdx = now.weekday - 1;
    final nextIdx = next == null || dayKey(next!) == dayKey(now) ? -1 : next!.weekday - 1;
    final rows = <(String, String, bool, bool)>[]; // label, value, highlight, muted value
    final off = <String>[];
    String? groupStart;
    String? groupEnd;
    String? groupValue;

    void flush() {
      if (groupStart == null) return;
      rows.add((groupStart == groupEnd ? groupStart! : '$groupStart – $groupEnd', groupValue!, false, false));
      groupStart = groupEnd = groupValue = null;
    }

    for (var i = 0; i < 7; i++) {
      final s = doctor.schedule[_keys[i]];
      if (i == todayIdx) {
        flush();
        final value = s == null
            ? 'Off'
            : switch (availability) {
                DoctorAvailability.onLeave => 'On leave',
                DoctorAvailability.ended => 'Ended',
                _ => Fmt.timeRange(s),
              };
        rows.add(('Today (${_names[i]})', value, availability.canBook, !availability.canBook));
        continue;
      }
      if (s == null) {
        flush();
        off.add(_names[i]);
        continue;
      }
      if (i == nextIdx) {
        flush();
        rows.add(('${_names[i]} · next', Fmt.timeRange(s), true, false));
        continue;
      }
      final v = Fmt.timeRange(s);
      if (groupValue == v) {
        groupEnd = _names[i];
      } else {
        flush();
        groupStart = groupEnd = _names[i];
        groupValue = v;
      }
    }
    flush();
    if (off.isNotEmpty) rows.add((off.join(', '), 'Off', false, true));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: i == rows.length - 1 ? null : const Border(bottom: BorderSide(color: AppColors.cream)),
            ),
            child: Row(children: [
              Expanded(
                child: Text(rows[i].$1,
                    style: AppText.labelSmall.copyWith(
                        fontSize: 13,
                        color: rows[i].$3 ? AppColors.primary : AppColors.textSecondary,
                        fontWeight: rows[i].$3 ? FontWeight.w700 : FontWeight.w500)),
              ),
              Text(rows[i].$2,
                  style: AppText.labelSmall.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: rows[i].$4 ? AppColors.textSecondary : (rows[i].$3 ? AppColors.primary : AppColors.textPrimary))),
            ]),
          ),
      ]),
    );
  }
}
