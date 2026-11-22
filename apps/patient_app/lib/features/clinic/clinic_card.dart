import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:asani_ui/asani_ui.dart';
import '../../data/location_service.dart';
import '../../data/providers.dart';

/// "Open today" / "Closed now" (every doctor's session today is over, D-27) /
/// "Closed today", plus next opening info for closed clinics.
({bool open, String label, String? hours, String? nextOpen}) clinicOpenInfo(List<Doctor> doctors, DateTime now) {
  final today = dateOnly(now);
  final worksToday = clinicOpenOn(doctors, today);
  final open = worksToday && clinicOpenNow(doctors, now);
  final label = open ? 'Open today' : (worksToday ? 'Closed now' : 'Closed today');
  String? hours;
  if (open) {
    final scheds = doctors.where((d) => !d.onLeave(today)).map((d) => d.scheduleOn(today)).whereType<DaySchedule>().toList();
    if (scheds.isNotEmpty) {
      final start = scheds.map((s) => s.startMinutes).reduce((a, b) => a < b ? a : b);
      final end = scheds.map((s) => s.endMinutes).reduce((a, b) => a > b ? a : b);
      hours = Fmt.timeRange(DaySchedule(minutesToHhmm(start), minutesToHhmm(end)));
    }
  }
  String? nextOpen;
  if (!open) {
    for (var i = 1; i <= 7; i++) {
      final d = today.add(Duration(days: i));
      if (clinicOpenOn(doctors, d)) {
        nextOpen = 'Opens ${Fmt.shortDay(dayKey(d))}';
        break;
      }
    }
  }
  return (open: open, label: label, hours: hours, nextOpen: nextOpen);
}

/// Stub / initials colours by status: open = green, closed = red,
/// online booking paused = grey. Text is the dark shade of the same colour.
(Color, Color) clinicStatusColors({required bool open, bool suspended = false}) => suspended
    ? (AppColors.muted, AppColors.textSecondary)
    : open
        ? (AppColors.successContainer, AppColors.success)
        : (AppColors.dangerContainer, AppColors.danger);

/// "AS" for Al-Shifa Clinic: initials without words like Clinic / Medical.
String clinicInitials(String name) =>
    Fmt.initials(name.replaceAll(RegExp(r'\b(Clinic|Medical|Hospital|Centre|Center)\b'), '').replaceAll('-', ' '));

/// Clinic initials in a rounded square ("AS" for Al-Shifa Clinic): tells
/// clinics apart at a glance, where one shared hospital icon could not.
class ClinicInitials extends StatelessWidget {
  const ClinicInitials({super.key, required this.name, required this.open, this.suspended = false, this.size = 44});
  final String name;
  final bool open;
  final bool suspended;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (tint, ink) = clinicStatusColors(open: open, suspended: suspended);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(Radii.button)),
      child: ExcludeSemantics(child: Text(clinicInitials(name), style: AppText.labelLarge.copyWith(color: ink))),
    );
  }
}

/// What a clinic card shows, worked out once for the big and mini cards.
class _ClinicFacts {
  _ClinicFacts(WidgetRef ref, Clinic clinic) {
    final now = nowFrom(ref);
    doctors = ref.watch(doctorsByClinicProvider).value?[clinic.id] ?? const <Doctor>[];
    final info = clinicOpenInfo(doctors, now);
    suspended = !clinic.status.acceptsBookings;
    open = info.open && !suspended;
    when = suspended
        ? 'online booking paused'
        : open
            ? (info.hours == null ? 'Open today' : 'Today ${info.hours}')
            : (info.nextOpen ?? info.label);
    final me = ref.watch(userLocationProvider).value;
    km = me == null || clinic.location == null ? null : distanceKm(me, clinic.location!);
    final count = clinic.doctorCount > 0 ? clinic.doctorCount : doctors.length;
    doctorsText = '$count ${count == 1 ? 'doctor' : 'doctors'}';
  }

  late final List<Doctor> doctors;
  late final bool suspended;
  late final bool open;
  late final String when;
  late final double? km;
  late final String doctorsText;

  /// Board chip: "● Open now" (cream), "○ Closed" (red), "❚❚ Booking paused" (amber).
  (String, Color, Color) get chip => suspended
      ? ('❚❚ Booking paused', AppColors.warningContainer, AppColors.warningText)
      : open
          ? ('● Open now', AppColors.cream, AppColors.primary)
          : ('○ Closed', AppColors.dangerContainer, AppColors.dangerText);

  String? get distance => km == null ? null : '${km! < 10 ? km!.toStringAsFixed(1) : km!.round()} km';
}

/// Dark forest cover with soft rings, the status chip and the distance
/// (board P2 "cover card"). [mirror] flips the light so lists look varied.
class _Cover extends StatelessWidget {
  const _Cover({required this.height, required this.facts, required this.mirror});
  final double height;
  final _ClinicFacts facts;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = facts.chip;
    Widget chip(String text, Color b, Color f) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: b, borderRadius: BorderRadius.circular(Radii.pill)),
          child: Text(text, style: AppText.labelSmall.copyWith(color: f, fontSize: 11, fontWeight: FontWeight.w600)),
        );
    return SizedBox(
      height: height,
      child: Stack(clipBehavior: Clip.hardEdge, children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: mirror ? Alignment.topRight : Alignment.topLeft,
                end: mirror ? Alignment.bottomLeft : Alignment.bottomRight,
                colors: const [AppColors.primaryDeep, AppColors.navy, AppColors.primaryMid],
                stops: const [0, 0.65, 1],
              ),
            ),
          ),
        ),
        // Soft light in the top corner and a faint ring.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: mirror ? Alignment.topLeft : Alignment.topRight,
                radius: 1.2,
                colors: [AppColors.primarySoft.withValues(alpha: 0.30), AppColors.primarySoft.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
        Positioned(
          right: mirror ? null : -30,
          left: mirror ? -30 : null,
          top: -40,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.cream.withValues(alpha: 0.07), width: 18),
            ),
          ),
        ),
        Positioned(left: 12, top: 12, child: chip(label, bg, fg)),
        if (facts.distance != null)
          Positioned(right: 12, top: 12, child: chip(facts.distance!, AppColors.cream.withValues(alpha: 0.14), AppColors.cream)),
      ]),
    );
  }
}

/// Clinic initials on a cream tile with a white edge, sitting on the cover's edge.
class _CoverTile extends StatelessWidget {
  const _CoverTile({required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.cream,
          borderRadius: BorderRadius.circular(size * 0.3),
          border: Border.all(color: AppColors.surface, width: 3),
          boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Text(clinicInitials(name),
            style: AppText.labelLarge.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: size * 0.34)),
      );
}

/// Clinic as a cover card (board P2: Home "Clinics in …", search results):
/// a dark forest cover with Open now / Closed / Booking paused and the
/// distance, the initials tile on its edge, then name, area and today's
/// hours, a View button, and the doctors with their specialities.
class ClinicCard extends ConsumerWidget {
  const ClinicCard({super.key, required this.clinic, this.highlight = ''});
  final Clinic clinic;
  final String highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = _ClinicFacts(ref, clinic);
    final mirror = clinic.id.hashCode.isOdd;
    final specialities = <String>{for (final d in f.doctors) d.specialityEnum.label.split(' ').first}.take(3).toList();
    final (status, _, _) = f.chip;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Semantics(
        button: true,
        label: '${clinic.name}, ${clinic.area}, ${f.doctorsText}. ${status.substring(2)}. ${f.when}'
            '${f.distance == null ? '' : ', ${f.distance} away'}',
        excludeSemantics: true,
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.primaryLight, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          child: InkWell(
            onTap: () => context.push('/clinic/${clinic.id}'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _Cover(height: 80, facts: f, mirror: mirror),
              Stack(clipBehavior: Clip.none, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 30, 14, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _HighlightText(clinic.name, highlight, AppText.titleSmall.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text('${clinic.area} · ${f.when}',
                              style: AppText.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                      const SizedBox(width: Gap.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                        child: Text('View ›',
                            style: AppText.labelSmall.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    if (f.doctors.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        _DoctorFaces(doctors: f.doctors),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: Text(
                            specialities.isEmpty ? f.doctorsText : '${f.doctorsText} · ${specialities.join(', ')}',
                            style: AppText.labelSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ],
                  ]),
                ),
                Positioned(left: 14, top: -26, child: _CoverTile(name: clinic.name, size: 50)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Up to three overlapping doctor initials.
class _DoctorFaces extends StatelessWidget {
  const _DoctorFaces({required this.doctors});
  final List<Doctor> doctors;

  @override
  Widget build(BuildContext context) {
    final shown = doctors.take(3).toList();
    return SizedBox(
      width: 24 + 18.0 * (shown.length - 1),
      height: 24,
      child: Stack(children: [
        for (var i = 0; i < shown.length; i++)
          Positioned(
            left: 18.0 * i,
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: i.isEven ? AppColors.primaryContainer : AppColors.cream,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
              ),
              child: Text(Fmt.initials(shown[i].name),
                  style: AppText.labelSmall.copyWith(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w700)),
            ),
          ),
      ]),
    );
  }
}

/// Small cover card for the Home "Recent clinics" row (board P2, 220 wide).
class ClinicMiniCard extends ConsumerWidget {
  const ClinicMiniCard({super.key, required this.clinic});
  final Clinic clinic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = _ClinicFacts(ref, clinic);
    final (status, _, _) = f.chip;
    final sub = f.open || f.suspended ? '${clinic.area} · ${f.doctorsText}' : '${clinic.area} · ${f.when.toLowerCase()}';
    return Semantics(
      button: true,
      label: '${clinic.name}, ${clinic.area}. ${status.substring(2)}.',
      excludeSemantics: true,
      child: SizedBox(
        width: 220,
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppColors.primaryLight, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/clinic/${clinic.id}'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              _Cover(height: 58, facts: f, mirror: clinic.id.hashCode.isOdd),
              Stack(clipBehavior: Clip.none, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(clinic.name,
                        style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(sub, style: AppText.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                Positioned(left: 12, top: -20, child: _CoverTile(name: clinic.name, size: 40)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Bolds/highlights the part of [text] that matches [query].
class _HighlightText extends StatelessWidget {
  const _HighlightText(this.text, this.query, this.style);
  final String text;
  final String query;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final i = q.isEmpty ? -1 : text.toLowerCase().indexOf(q);
    if (i < 0) return Text(text, style: style, overflow: TextOverflow.ellipsis);
    return Text.rich(
      TextSpan(style: style, children: [
        TextSpan(text: text.substring(0, i)),
        TextSpan(
            text: text.substring(i, i + q.length),
            style: TextStyle(backgroundColor: AppColors.primaryContainer, color: AppColors.primary)),
        TextSpan(text: text.substring(i + q.length)),
      ]),
      overflow: TextOverflow.ellipsis,
    );
  }
}
