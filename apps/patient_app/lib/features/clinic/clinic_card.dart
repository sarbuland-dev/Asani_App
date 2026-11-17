import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:asani_ui/asani_ui.dart';
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

/// Clinic initials in a rounded square ("AS" for Al-Shifa Clinic): tells
/// clinics apart at a glance, where one shared hospital icon could not.
class ClinicInitials extends StatelessWidget {
  const ClinicInitials({super.key, required this.name, this.active = true, this.size = 44});
  final String name;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.primaryContainer : AppColors.muted,
          borderRadius: BorderRadius.circular(Radii.button),
        ),
        child: ExcludeSemantics(
          child: Text(
            Fmt.initials(name.replaceAll(RegExp(r'\b(Clinic|Medical|Hospital|Centre|Center)\b'), '').replaceAll('-', ' ')),
            style: AppText.labelLarge.copyWith(color: active ? AppColors.primary : AppColors.textSecondary),
          ),
        ),
      );
}

/// Clinic as a paper ticket (Home "All clinics", search results): a tinted
/// stub with the clinic initials and Open / Closed, a dashed tear line with
/// two notches, then name, area and doctors, and today's hours or when it
/// next opens.
class ClinicCard extends ConsumerWidget {
  const ClinicCard({super.key, required this.clinic, this.highlight = ''});
  final Clinic clinic;
  final String highlight;

  static const _stub = 78.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = nowFrom(ref);
    final doctors = ref.watch(doctorsByClinicProvider).value?[clinic.id] ?? const <Doctor>[];
    final info = clinicOpenInfo(doctors, now);
    final suspended = !clinic.status.acceptsBookings;
    final open = info.open && !suspended;
    final status = suspended ? 'Paused' : (open ? 'Open' : 'Closed');
    final when = suspended ? 'Online booking not available' : (info.hours ?? info.nextOpen ?? info.label);
    final doctorsText = '${clinic.doctorCount} ${clinic.doctorCount == 1 ? 'doctor' : 'doctors'}';

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Semantics(
        button: true,
        label: '${clinic.name}, ${clinic.area}, $doctorsText. ${open ? info.label : status}. $when',
        excludeSemantics: true,
        child: Material(
          color: AppColors.surface,
          shape: const TicketBorder(notchX: _stub, side: BorderSide(color: AppColors.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/clinic/${clinic.id}'),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Stub: initials + open state.
                  Container(
                    width: _stub,
                    color: open ? AppColors.primaryContainer : AppColors.muted,
                    padding: const EdgeInsets.symmetric(vertical: Gap.lg, horizontal: Gap.xs),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          Fmt.initials(clinic.name.replaceAll(RegExp(r'\b(Clinic|Medical|Hospital|Centre|Center)\b'), '').replaceAll('-', ' ')),
                          style: AppText.titleLarge.copyWith(
                              color: open ? AppColors.primary : AppColors.textSecondary, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: Gap.xs),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle, color: open ? AppColors.success : AppColors.textSecondary),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(status,
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: AppText.labelSmall.copyWith(
                                    color: open ? AppColors.success : AppColors.textSecondary, fontWeight: FontWeight.w700)),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  // Tear line, between the two notches.
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: Gap.md),
                    child: DashedLine(axis: Axis.vertical),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.xs, Gap.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _HighlightText(clinic.name, highlight, AppText.titleMedium),
                          const SizedBox(height: 2),
                          Row(children: [
                            const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textSecondary),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text('${clinic.area} · $doctorsText',
                                  style: AppText.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ]),
                          const SizedBox(height: Gap.sm),
                          Row(children: [
                            Icon(open ? Icons.schedule_rounded : Icons.event_outlined, size: 14, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(when,
                                  style: AppText.labelSmall.copyWith(color: AppColors.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: Gap.sm),
                    child: Center(child: Icon(Icons.chevron_right_rounded, color: AppColors.textMuted)),
                  ),
                ],
              ),
            ),
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
