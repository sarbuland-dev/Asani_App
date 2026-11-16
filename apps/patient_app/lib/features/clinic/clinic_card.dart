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

class ClinicCard extends ConsumerWidget {
  const ClinicCard({super.key, required this.clinic, this.highlight = ''});
  final Clinic clinic;
  final String highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = nowFrom(ref);
    final doctors = ref.watch(doctorsByClinicProvider).value?[clinic.id] ?? const <Doctor>[];
    final info = clinicOpenInfo(doctors, now);
    final suspended = !clinic.status.acceptsBookings;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: AppCard(
        onTap: () => context.push('/clinic/${clinic.id}'),
        padding: const EdgeInsets.all(Gap.md + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBox(
                  icon: Icons.local_hospital_outlined,
                  bg: info.open && !suspended ? AppColors.primaryContainer : AppColors.muted,
                  fg: info.open && !suspended ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HighlightText(clinic.name, highlight, AppText.titleMedium),
                      const SizedBox(height: 2),
                      Row(children: [
                        const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            '${clinic.area} · ${clinic.doctorCount} ${clinic.doctorCount == 1 ? 'doctor' : 'doctors'}',
                            style: AppText.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                if (suspended)
                  const Flexible(child: Pill(label: 'Online booking not available', fg: AppColors.textSecondary, bg: AppColors.muted))
                else
                  Text.rich(
                    TextSpan(children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                              shape: BoxShape.circle, color: info.open ? AppColors.success : AppColors.textMuted),
                        ),
                      ),
                      TextSpan(text: info.label),
                    ]),
                    style: AppText.labelSmall.copyWith(
                        color: info.open ? AppColors.success : AppColors.textSecondary, fontWeight: FontWeight.w600),
                  ),
                const SizedBox(width: Gap.sm),
                if (!suspended && (info.hours ?? info.nextOpen) != null)
                  Expanded(
                    child: Text(info.hours ?? info.nextOpen!,
                        style: AppText.labelSmall, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ],
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
