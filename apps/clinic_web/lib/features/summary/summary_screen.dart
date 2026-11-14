import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/web/download.dart';
import '../../core/widgets/desktop.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// W-16 / C-10 daily summary, plus C-14 export.
class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen(this.clinicId, {super.key});
  final String clinicId;

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  late DateTime _date = parseDayKey(dayKey(pktNow()));
  String? _doctorId;

  String _hour(int h) => '${(h + 11) % 12 + 1} ${h < 12 ? 'AM' : 'PM'}';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider)!;
    final doctors = ref.watch(allDoctorsProvider(widget.clinicId));
    final doctorId = _doctorId;
    final key = dayKey(_date);
    final all = ref.watch(tokensOnProvider((widget.clinicId, key)));
    final tokens = doctorId == null ? all : all.where((t) => t.token.doctorId == doctorId).toList();
    final s = DaySummary.of(tokens);
    final today = parseDayKey(dayKey(pktNow()));
    final maxHour = s.byHour.values.fold<int>(0, (a, b) => b > a ? b : a);

    return PageScaffold(
      title: 'Daily summary',
      subtitle: 'Per day and per doctor, last 30 days.',
      actions: [
        IconButton(
          tooltip: 'Previous day',
          onPressed: _date.isAfter(today.subtract(const Duration(days: 30))) ? () => setState(() => _date = _date.subtract(const Duration(days: 1))) : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final d = await showDatePicker(context: context, firstDate: today.subtract(const Duration(days: 30)), lastDate: today, initialDate: _date);
            if (d != null) setState(() => _date = d);
          },
          icon: const Icon(Icons.calendar_month_rounded, size: 18),
          label: Text(Fmt.relativeDay(key)),
        ),
        IconButton(
          tooltip: 'Next day',
          onPressed: _date.isBefore(today) ? () => setState(() => _date = _date.add(const Duration(days: 1))) : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ...[
          Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
            ChoiceChip(label: const Text('All doctors'), selected: _doctorId == null, onSelected: (_) => setState(() => _doctorId = null)),
            for (final d in doctors)
              ChoiceChip(
                avatar: LetterBadge(d.tokenPrefix, size: 22),
                label: Text(d.name),
                selected: _doctorId == d.id,
                onSelected: (_) => setState(() => _doctorId = d.id),
              ),
          ]),
          const SizedBox(height: Gap.lg),
        ],
        CardGrid(minWidth: 200, children: [
          KpiCard(label: 'Tokens issued', value: '${s.issued}', icon: Icons.confirmation_number_outlined, hint: 'App ${s.app} · Walk-in ${s.walkIn}'),
          KpiCard(label: 'Completed', value: '${s.completed}', icon: Icons.task_alt_rounded, fg: AppColors.success, bg: AppColors.successContainer),
          KpiCard(label: 'Cancelled', value: '${s.cancelled}', icon: Icons.cancel_outlined, fg: AppColors.danger, bg: AppColors.dangerContainer),
          KpiCard(label: 'No-show', value: '${s.noShow}', icon: Icons.person_off_outlined, fg: AppColors.warning, bg: AppColors.warningContainer),
          KpiCard(label: 'Average wait', value: WebFmt.minutes(s.avgWait), icon: Icons.timer_outlined, fg: AppColors.info, bg: AppColors.infoContainer),
          KpiCard(label: 'Busiest hour', value: s.busiestHour == null ? '—' : _hour(s.busiestHour!), icon: Icons.schedule_rounded, fg: AppColors.secondary, bg: AppColors.avatarCool),
        ]),
        const SectionTitle('Patients by hour'),
        AppCard(
          padding: const EdgeInsets.all(Gap.xl),
          child: s.byHour.isEmpty
              ? Text('No tokens on this day.', style: AppText.bodyMedium)
              : SizedBox(
                  height: 180,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (final h in (s.byHour.keys.toList()..sort()))
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Tooltip(
                            message: '${_hour(h)}: ${s.byHour[h]} patients',
                            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                              Text('${s.byHour[h]}', style: AppText.labelSmall),
                              const SizedBox(height: 4),
                              Container(
                                height: 120 * s.byHour[h]! / maxHour,
                                decoration: BoxDecoration(
                                  color: h == s.busiestHour ? AppColors.primary : AppColors.primaryLight.withValues(alpha: 0.45),
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(_hour(h), style: AppText.labelSmall),
                            ]),
                          ),
                        ),
                      ),
                  ]),
                ),
        ),
        if (_doctorId == null) ...[
          const SectionTitle('By doctor'),
          AppTable(
            columns: const [
              TableColumn('Doctor', flex: 4),
              TableColumn('Issued', flex: 2),
              TableColumn('App / Walk-in', flex: 2),
              TableColumn('Completed', flex: 2),
              TableColumn('Cancelled', flex: 2),
              TableColumn('No-show', flex: 2),
              TableColumn('Avg wait', flex: 2),
            ],
            rows: [
              for (final d in doctors)
                () {
                  final ds = DaySummary.of(all.where((t) => t.token.doctorId == d.id));
                  return <Widget>[
                    Row(children: [LetterBadge(d.tokenPrefix, size: 30), const SizedBox(width: Gap.md), Expanded(child: Text(d.name, style: AppText.labelMedium))]),
                    Text('${ds.issued}', style: AppText.labelMedium),
                    Text('${ds.app} / ${ds.walkIn}', style: AppText.bodyMedium),
                    Text('${ds.completed}', style: AppText.bodyMedium),
                    Text('${ds.cancelled}', style: AppText.bodyMedium),
                    Text('${ds.noShow}', style: AppText.bodyMedium),
                    Text(WebFmt.minutes(ds.avgWait), style: AppText.bodyMedium),
                  ];
                }(),
            ],
          ),
        ],
        if (user.role.canRunQueue) ...[
          const SectionTitle('Export visits'),
          _ExportCard(clinicId: widget.clinicId),
        ],
      ]),
    );
  }
}

/// C-14: export a date range of visits to CSV (opens in Excel).
class _ExportCard extends ConsumerStatefulWidget {
  const _ExportCard({required this.clinicId});
  final String clinicId;

  @override
  ConsumerState<_ExportCard> createState() => _ExportCardState();
}

class _ExportCardState extends ConsumerState<_ExportCard> {
  late final DateTime _today = parseDayKey(dayKey(pktNow()));
  late DateTimeRange _range = DateTimeRange(start: _today.subtract(const Duration(days: 6)), end: _today);

  Future<void> _export() async {
    final repo = ref.read(repositoryProvider);
    final doctors = {for (final d in repo.doctors(widget.clinicId, includeInactive: true)) d.id: d.name};
    final lines = <String>[csvRow(['Date', 'Token', 'Doctor', 'Patient', 'Age', 'Sex', 'Phone', 'Source', 'Status', 'Wait (min)'])];
    var n = 0;
    final list = await showBusyWhile(context, () => repo.loadTokens(widget.clinicId, dayKey(_range.start), dayKey(_range.end)), message: 'Preparing the export…')
      ..sort((a, b) {
        final c = a.token.date.compareTo(b.token.date);
        return c != 0 ? c : a.label.compareTo(b.label);
      });
    for (final t in list) {
      final s = t.token.patientSnapshot;
      lines.add(csvRow([t.token.date, t.label, doctors[t.token.doctorId], s.name, s.age(parseDayKey(t.token.date)), s.gender.short, s.phone, t.source.label, t.status.label, t.waitMinutes]));
      n++;
    }
    final label = '${dayKey(_range.start)}_to_${dayKey(_range.end)}';
    downloadText('asani-visits-$label.csv', lines.join('\n'));
    await repo.logExport(widget.clinicId, '${Fmt.shortDay(dayKey(_range.start))} – ${Fmt.shortDay(dayKey(_range.end))}');
    if (mounted) showSnack(context, 'Exported $n visits.');
  }

  @override
  Widget build(BuildContext context) => AppCard(
        child: Row(children: [
          const IconBox(icon: Icons.download_rounded),
          const SizedBox(width: Gap.lg),
          Expanded(
            child: TwoLine('Visits from ${Fmt.shortDay(dayKey(_range.start))} to ${Fmt.shortDay(dayKey(_range.end))}',
                'Date, token, doctor, patient, age/sex, phone, status, wait time. CSV opens in Excel.'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final r = await showDateRangePicker(context: context, firstDate: _today.subtract(const Duration(days: 365)), lastDate: _today, initialDateRange: _range);
              if (r != null) setState(() => _range = r);
            },
            icon: const Icon(Icons.date_range_rounded, size: 18),
            label: const Text('Change dates'),
          ),
          const SizedBox(width: Gap.sm),
          FilledButton.icon(onPressed: _export, icon: const Icon(Icons.file_download_outlined), label: const Text('Export CSV')),
        ]),
      );
}
