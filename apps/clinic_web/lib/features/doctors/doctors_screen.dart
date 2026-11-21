import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/desktop.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'doctor_form_dialog.dart';
import '../../core/widgets/pin_gate.dart';

/// W-17 / C-11 (D-19): the clinic adds, edits and deactivates its own
/// doctors and sets leave. Doctors are records only; they never log in.
class DoctorsScreen extends ConsumerWidget {
  const DoctorsScreen(this.clinicId, {super.key});
  final String clinicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PageScaffold(
        title: 'Doctors',
        subtitle: 'Letters (A, B, C…) are given automatically and never reused.',
        actions: [
          FilledButton.icon(
            onPressed: () => addDoctor(context, ref, clinicId),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add doctor'),
          ),
        ],
        child: DoctorList(clinicId: clinicId),
      );
}

/// Opens the doctor form and saves a new doctor (clinic login only).
Future<void> addDoctor(BuildContext context, WidgetRef ref, String clinicId) async {
  if (!await requireManagerPin(context, ref, clinicId) || !context.mounted) return; // D-41
  final r = await showDoctorForm(context, clinicId: clinicId);
  if (r != null && context.mounted) {
    await runAction(context, () => ref.read(repositoryProvider).saveDoctor(clinicId, r.doctor, isNew: true, pmdcNumber: r.pmdc),
        success: '${r.doctor.name} added.');
  }
}

/// Doctor cards. The clinic login can edit, set leave and deactivate; the
/// Super Admin sees a read-only list with New marks and who changed what (A-03).
class DoctorList extends ConsumerWidget {
  const DoctorList({super.key, required this.clinicId});
  final String clinicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctors = ref.watch(allDoctorsProvider(clinicId));
    final canManage = ref.watch(currentUserProvider)!.role.canManageDoctors;

    if (doctors.isEmpty) {
      return EmptyState(
        icon: Icons.medical_services_outlined,
        title: canManage ? 'Add your first doctor' : 'No doctors yet',
        message: canManage ? 'Patients can book once a doctor with a weekly schedule is added.' : 'The clinic adds its own doctors after its first login.',
        actionLabel: canManage ? 'Add doctor' : null,
        onAction: canManage ? () => addDoctor(context, ref, clinicId) : null,
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!canManage)
        const Padding(
          padding: EdgeInsets.only(bottom: Gap.md),
          child: Banner2(
            icon: Icons.visibility_outlined,
            fg: AppColors.info,
            bg: AppColors.infoContainer,
            text: 'View only. The clinic adds and manages its own doctors (D-19).',
          ),
        ),
      for (final d in doctors) Padding(padding: const EdgeInsets.only(bottom: Gap.md), child: _DoctorCard(clinicId: clinicId, doctor: d, canManage: canManage)),
    ]);
  }
}

class _DoctorCard extends ConsumerWidget {
  const _DoctorCard({required this.clinicId, required this.doctor, required this.canManage});
  final String clinicId;
  final Doctor doctor;
  final bool canManage;

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
    final now = pktNow();
    final today = dayKey(now);
    final leaves = d.onLeaveDates.where((x) => x.compareTo(today) >= 0).toList();
    final addedAt = ref.watch(doctorAddedAtProvider)[d.id];
    final last = ref.watch(activityProvider(clinicId)).where((a) => a.target.startsWith(d.name)).firstOrNull;

    return AppCard(
      color: d.active ? AppColors.surface : AppColors.muted,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LetterBadge(d.tokenPrefix, size: 52),
        const SizedBox(width: Gap.lg),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(d.name, style: AppText.titleMedium, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: Gap.sm),
              d.active
                  ? const Pill(label: 'Active', fg: AppColors.success, bg: AppColors.successContainer, dot: true)
                  : const Pill(label: 'Inactive', fg: AppColors.textSecondary, bg: AppColors.border, dot: true),
              if (isNewDoctor(addedAt)) ...[
                const SizedBox(width: Gap.xs),
                const Pill(label: 'New', fg: AppColors.onPrimary, bg: AppColors.primaryLight),
              ],
            ]),
            Text([d.specialityEnum.display, ?d.qualification].join(' · '), style: AppText.bodyMedium),
            if (d.specialityFlagged) const Text('Please pick a speciality (Edit).', style: TextStyle(color: AppColors.warning)),
            const SizedBox(height: Gap.sm),
            Text(_scheduleText(), style: AppText.labelSmall),
            const SizedBox(height: Gap.sm),
            Wrap(spacing: Gap.sm, runSpacing: Gap.xs, children: [
              Pill(label: '${d.avgConsultMinutes} min / patient', fg: AppColors.textSecondary, bg: AppColors.muted, icon: Icons.timer_outlined),
              Pill(label: 'Max ${d.maxTokensPerDay} tokens', fg: AppColors.textSecondary, bg: AppColors.muted, icon: Icons.confirmation_number_outlined),
              Pill(label: 'Booking ${d.bookingWindowDays} days ahead', fg: AppColors.textSecondary, bg: AppColors.muted, icon: Icons.event_outlined),
              for (final l in leaves)
                canManage
                    ? InputChip(
                        label: Text('Leave ${Fmt.shortDay(l)}'),
                        labelStyle: AppText.labelSmall.copyWith(color: AppColors.danger),
                        backgroundColor: AppColors.dangerContainer,
                        side: BorderSide.none,
                        onDeleted: () => runAction(context, () => repo.removeLeave(d.id, l), success: 'Leave removed.'),
                        deleteButtonTooltipMessage: 'Remove leave',
                      )
                    : Pill(label: 'Leave ${Fmt.shortDay(l)}', fg: AppColors.danger, bg: AppColors.dangerContainer),
            ]),
            const SizedBox(height: Gap.sm),
            Text(
              [
                if (addedAt != null) 'Added ${WebFmt.ago(addedAt, now: now)}',
                if (last != null) 'Last change: ${last.action} by ${last.actorName} · ${WebFmt.ago(last.at, now: now)}',
              ].join('  ·  '),
              style: AppText.labelSmall.copyWith(color: AppColors.textMuted),
            ),
          ]),
        ),
        if (canManage) ...[
          const SizedBox(width: Gap.md),
          OutlinedButton.icon(
            onPressed: d.active ? () => _addLeave(context, ref) : null,
            icon: const Icon(Icons.event_busy_rounded, size: 18),
            label: const Text('Add leave'),
          ),
          const SizedBox(width: Gap.sm),
          OutlinedButton.icon(
            onPressed: () async {
              final r = await showDoctorForm(context, initial: d, clinicId: clinicId, hasPmdc: repo.hasPmdc(d.id));
              if (r != null && context.mounted) {
                await runAction(context, () => repo.saveDoctor(clinicId, r.doctor, pmdcNumber: r.pmdc), success: 'Changes saved.');
              }
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (_) async {
              if (d.active) {
                if (!await requireManagerPin(context, ref, clinicId) || !context.mounted) return; // D-41
                final ok = await confirmDialog(context,
                    title: 'Deactivate ${d.name}?', message: 'No new bookings. Visit history is kept. You can reactivate later.', confirmLabel: 'Deactivate', danger: true);
                if (!ok || !context.mounted) return;
              }
              await runAction(context, () => repo.setDoctorActive(d.id, !d.active), success: d.active ? 'Doctor deactivated.' : 'Doctor reactivated.');
            },
            itemBuilder: (_) => [PopupMenuItem(value: 'toggle', child: Text(d.active ? 'Deactivate doctor' : 'Reactivate doctor'))],
          ),
        ],
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
      note: 'Patients who use the Asani app get a notification with this reason.', // D-23
    );
    if (reason == null || !context.mounted) {
      if (context.mounted) showSnack(context, 'Leave added. Existing tokens were kept.');
      return;
    }
    await runAction(context, () => repo.cancelTokensOn(doctor.id, key, reason), success: 'Leave added and $tokens tokens cancelled.');
  }
}
