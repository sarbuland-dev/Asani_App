import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/web/download.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

enum _Tab { today, upcoming, missed }

/// W-15 / C-09: Today / Upcoming / Missed follow-ups. Lime is used only here
/// and on follow-up notes (D-51).
class FollowUpsScreen extends ConsumerStatefulWidget {
  const FollowUpsScreen(this.clinicId, {super.key});
  final String clinicId;

  @override
  ConsumerState<FollowUpsScreen> createState() => _FollowUpsScreenState();
}

class _FollowUpsScreenState extends ConsumerState<FollowUpsScreen> {
  _Tab _tab = _Tab.today;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider)!;
    final today = ref.watch(todayProvider).value ?? dayKey(pktNow());
    final all = ref.watch(followUpsProvider(widget.clinicId));
    final doctors = ref.watch(allDoctorsProvider(widget.clinicId));
    final repo = ref.watch(repositoryProvider);

    bool inTab(FollowUp f, _Tab t) => switch (t) {
          _Tab.today => f.dueDate == today,
          _Tab.upcoming => f.dueDate.compareTo(today) > 0,
          _Tab.missed => effectiveFollowUpStatus(f, today) == FollowUpStatus.missed,
        };
    int count(_Tab t) => all.where((f) => inTab(f, t)).length;
    final weekEnd = dayKey(parseDayKey(today).add(const Duration(days: 7)));
    final week = all.where((f) => f.dueDate.compareTo(today) > 0 && f.dueDate.compareTo(weekEnd) <= 0).length;
    final shown = all.where((f) => inTab(f, _tab)).toList();
    if (_tab == _Tab.missed) shown.sort((a, b) => b.dueDate.compareTo(a.dueDate));

    return ClinicPage(
      title: 'Follow-ups',
      subtitle: 'Patients get an app reminder the day before and on the day. Use the Missed list to call patients back.',
      leading: const IconTile(Icons.event_repeat_rounded, size: 48, bg: ClinicColors.lime, fg: ClinicColors.limeInk),
      children: [
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _kpi('Due today', count(_Tab.today), bg: ClinicColors.limeTint, line: ClinicColors.limeSoft, fg: ClinicColors.limeText),
            const SizedBox(width: 12),
            _kpi('Upcoming 7 days', week),
            const SizedBox(width: 12),
            _kpi('Missed', count(_Tab.missed), bg: AppColors.dangerContainer, line: AppColors.dangerContainer, fg: AppColors.dangerText),
          ]),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedPill<_Tab>(
            values: _Tab.values,
            selected: _tab,
            activeBg: ClinicColors.lime,
            activeFg: ClinicColors.limeInk,
            label: (t) => switch (t) {
              _Tab.today => 'Today · ${count(t)}',
              _Tab.upcoming => 'Upcoming · ${count(t)}',
              _Tab.missed => 'Missed · ${count(t)}',
            },
            onChanged: (t) => setState(() => _tab = t),
          ),
        ),
        const SizedBox(height: 18),
        Panel(
          radius: 16,
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ColoredBox(color: ClinicColors.lime, child: SizedBox(height: 4)),
            SimpleTable(
              columns: const [
                TableColumn('Patient', flex: 5),
                TableColumn('Phone', flex: 4),
                TableColumn('Doctor', flex: 4),
                TableColumn('Due', flex: 3),
                TableColumn('Note', flex: 3),
                TableColumn('Status', flex: 3),
              ],
              empty: EmptyState(
                icon: Icons.event_available_rounded,
                title: switch (_tab) { _Tab.today => 'No follow-ups today', _Tab.upcoming => 'Nothing upcoming', _Tab.missed => 'No missed follow-ups' },
                message: 'Set a follow-up from the called token on the queue board.',
              ),
              onTap: user.role.canRunQueue ? (i) => context.go('/patients/${shown[i].patientId}') : null,
              rows: [
                for (final f in shown) _row(f, repo.patient(f.patientId), doctors.where((d) => d.id == f.doctorId).firstOrNull?.name, today),
              ],
            ),
          ]),
        ),
      ],
    );
  }

  List<Widget> _row(FollowUp f, Patient? p, String? doctorName, String today) {
    final status = effectiveFollowUpStatus(f, today);
    final (fg, bg) = switch (status) {
      FollowUpStatus.pending => (AppColors.warningText, AppColors.warningContainer),
      FollowUpStatus.booked => (ClinicColors.limeText, ClinicColors.limeTint),
      FollowUpStatus.done => (AppColors.textSecondary, AppColors.cream),
      FollowUpStatus.missed => (AppColors.dangerText, AppColors.dangerContainer),
    };
    return [
      TwoLine(p?.name ?? '—', p == null ? null : '${p.relation.label} · ${p.age(pktNow()) ?? '—'} ${p.gender.short}'),
      Row(children: [
        Flexible(child: Text(p == null ? '—' : Fmt.phone(p.phone), style: ClinicText.body)),
        if (p != null)
          TextButton(
            onPressed: () async {
              await copyText(p.phone);
              if (mounted) showSnack(context, 'Phone number copied.');
            },
            child: const Text('Copy'),
          ),
      ]),
      Text(doctorName ?? '—', style: ClinicText.body),
      Text(Fmt.relativeDay(f.dueDate), style: AppText.labelMedium),
      Text(f.note ?? '—', style: ClinicText.body),
      CChip(status.label, fg: fg, bg: bg),
    ];
  }

  Widget _kpi(String label, int value, {Color bg = AppColors.surface, Color line = AppColors.border, Color fg = AppColors.textPrimary}) => Expanded(
        child: Panel(
          radius: 16,
          color: bg,
          borderColor: line,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppText.bodyMedium.copyWith(fontSize: 13, color: fg == AppColors.textPrimary ? AppColors.textSecondary : fg)),
            Text('$value', style: ClinicText.big(28, color: fg)),
          ]),
        ),
      );
}
