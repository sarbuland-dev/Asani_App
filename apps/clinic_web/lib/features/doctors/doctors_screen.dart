import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/desktop.dart';
import '../../data/providers.dart';
import 'doctor_form_dialog.dart';

/// W-17 / C-11: doctors list, add/edit, leave, deactivate.
class DoctorsScreen extends ConsumerWidget {
  const DoctorsScreen(this.clinicId, {super.key});
  final String clinicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctors = ref.watch(allDoctorsProvider(clinicId));
    final repo = ref.watch(repositoryProvider);

    return PageScaffold(
      title: 'Doctors',
      subtitle: 'Letters are assigned automatically and never reused.',
      actions: [
        FilledButton.icon(
          onPressed: () async {
            final d = await showDoctorForm(context, clinicId: clinicId);
            if (d != null && context.mounted) {
              await runAction(context, () => repo.saveDoctor(clinicId, d, isNew: true), success: '${d.name} added.');
            }
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add doctor'),
        ),
      ],
      child: doctors.isEmpty
          ? const EmptyState(icon: Icons.medical_services_outlined, title: 'No doctors yet', message: 'Add your first doctor to start taking tokens.')
          : Column(children: [for (final d in doctors) Padding(padding: const EdgeInsets.only(bottom: Gap.md), child: _DoctorCard(clinicId: clinicId, doctor: d))]),
    );
  }
}

class _DoctorCard extends ConsumerWidget {
  const _DoctorCard({required this.clinicId, required this.doctor});
  final String clinicId;
  final Doctor doctor;

  String _scheduleText() {
    final parts = <String>[];
    for (final k in weekdayKeys) {
      final s = doctor.schedule[k];
      if (s != null) parts.add('${k[0].toUpperCase()}${k.substring(1)} ${Fmt.timeRangeShort(s)}');
    }
    return parts.isEmpty ? 'No working days' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = doctor;
    final repo = ref.watch(repositoryProvider);
    final today = dayKey(pktNow());
    final leaves = d.onLeaveDates.where((x) => x.compareTo(today) >= 0).toList();

    return AppCard(
      color: d.active ? AppColors.surface : AppColors.muted,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LetterBadge(d.tokenPrefix, size: 52),
        const SizedBox(width: Gap.lg),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(d.name, style: AppText.titleMedium),
              const SizedBox(width: Gap.sm),
              d.active
                  ? const Pill(label: 'Active', fg: AppColors.success, bg: AppColors.successContainer, dot: true)
                  : const Pill(label: 'Inactive', fg: AppColors.textSecondary, bg: AppColors.border, dot: true),
            ]),
            Text([d.speciality, ?d.qualification].join(' · '), style: AppText.bodyMedium),
            const SizedBox(height: Gap.sm),
            Text(_scheduleText(), style: AppText.labelSmall),
            const SizedBox(height: Gap.sm),
            Wrap(spacing: Gap.sm, runSpacing: Gap.xs, children: [
              Pill(label: '${d.avgConsultMinutes} min / patient', fg: AppColors.textSecondary, bg: AppColors.muted, icon: Icons.timer_outlined),
              Pill(label: 'Max ${d.maxTokensPerDay} tokens', fg: AppColors.textSecondary, bg: AppColors.muted, icon: Icons.confirmation_number_outlined),
              Pill(label: 'Booking ${d.bookingWindowDays} days ahead', fg: AppColors.textSecondary, bg: AppColors.muted, icon: Icons.event_outlined),
              for (final l in leaves)
                InputChip(
                  label: Text('Leave ${Fmt.shortDay(l)}'),
                  labelStyle: AppText.labelSmall.copyWith(color: AppColors.danger),
                  backgroundColor: AppColors.dangerContainer,
                  side: BorderSide.none,
                  onDeleted: () => runAction(context, () => repo.removeLeave(d.id, l), success: 'Leave removed.'),
                  deleteButtonTooltipMessage: 'Remove leave',
                ),
            ]),
          ]),
        ),
        const SizedBox(width: Gap.md),
        OutlinedButton.icon(
          onPressed: d.active ? () => _addLeave(context, ref) : null,
          icon: const Icon(Icons.event_busy_rounded, size: 18),
          label: const Text('Add leave'),
        ),
        const SizedBox(width: Gap.sm),
        OutlinedButton.icon(
          onPressed: () async {
            final edited = await showDoctorForm(context, initial: d, clinicId: clinicId);
            if (edited != null && context.mounted) await runAction(context, () => repo.saveDoctor(clinicId, edited), success: 'Changes saved.');
          },
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Edit'),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          onSelected: (_) async {
            if (d.active) {
              final ok = await confirmDialog(context,
                  title: 'Deactivate ${d.name}?', message: 'No new bookings. Visit history is kept. You can reactivate later.', confirmLabel: 'Deactivate', danger: true);
              if (!ok || !context.mounted) return;
            }
            await runAction(context, () => repo.setDoctorActive(d.id, !d.active), success: d.active ? 'Doctor deactivated.' : 'Doctor reactivated.');
          },
          itemBuilder: (_) => [PopupMenuItem(value: 'toggle', child: Text(d.active ? 'Deactivate doctor' : 'Reactivate doctor'))],
        ),
      ]),
    );
  }

  /// Leave date; existing tokens that day get a warning + bulk cancel.
  Future<void> _addLeave(BuildContext context, WidgetRef ref) async {
    final today = parseDayKey(dayKey(pktNow()));
    final date = await showDatePicker(context: context, firstDate: today, lastDate: today.add(const Duration(days: 180)), helpText: 'Leave date for ${doctor.name}');
    if (date == null || !context.mounted) return;
    final repo = ref.read(repositoryProvider);
    final key = dayKey(date);
    var tokens = 0;
    final ok = await runAction(context, () async => tokens = await repo.addLeave(doctor.id, key));
    if (!ok || !context.mounted) return;
    if (tokens == 0) {
      showSnack(context, 'Leave added for ${Fmt.shortDay(key)}. Patients see "On leave".');
      return;
    }
    final reason = await askReason(
      context,
      title: '$tokens token${tokens == 1 ? '' : 's'} already booked on ${Fmt.shortDay(key)}',
      options: const ['Doctor on leave', 'Clinic closed', 'Other'],
      confirmLabel: 'Cancel $tokens token${tokens == 1 ? '' : 's'}',
    );
    if (reason == null || !context.mounted) {
      if (context.mounted) showSnack(context, 'Leave added. Existing tokens were kept.');
      return;
    }
    await runAction(context, () => repo.cancelTokensOn(doctor.id, key, reason), success: 'Leave added and $tokens tokens cancelled.');
  }
}
