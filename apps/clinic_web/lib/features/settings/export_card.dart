import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/web/download.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../core/widgets/pin_gate.dart';
import '../../data/providers.dart';

/// C-14: export a date range of visits to CSV (opens in Excel). On Settings
/// since the board's W-19.
class ExportCard extends ConsumerStatefulWidget {
  const ExportCard({super.key, required this.clinicId});
  final String clinicId;

  @override
  ConsumerState<ExportCard> createState() => _ExportCardState();
}

class _ExportCardState extends ConsumerState<ExportCard> {
  late final DateTime _today = parseDayKey(dayKey(pktNow()));
  late DateTimeRange _range = DateTimeRange(start: _today.subtract(const Duration(days: 6)), end: _today);

  Future<void> _export() async {
    if (!await requireManagerPin(context, ref, widget.clinicId) || !mounted) return; // D-41
    final repo = ref.read(repositoryProvider);
    final doctors = {for (final d in repo.doctors(widget.clinicId, includeInactive: true)) d.id: d.name};
    final lines = <String>[csvRow(['Date', 'Token', 'Doctor', 'Patient', 'Age', 'Sex', 'Phone', 'Source', 'Status', 'Wait (min)'])];
    var n = 0;
    try {
      final list = await showBusyWhile(context, () => repo.loadTokens(widget.clinicId, dayKey(_range.start), dayKey(_range.end)), message: 'Preparing the export…')
        ..sort((a, b) {
          final c = a.token.date.compareTo(b.token.date);
          return c != 0 ? c : a.label.compareTo(b.label);
        });
      for (final t in list) {
        final s = t.token.patientSnapshot;
        lines.add(csvRow(
            [t.token.date, t.label, doctors[t.token.doctorId], s.name, s.age(parseDayKey(t.token.date)), s.gender.short, s.phone, t.source.label, t.status.label, t.waitMinutes]));
        n++;
      }
      final label = '${dayKey(_range.start)}_to_${dayKey(_range.end)}';
      downloadText('asani-visits-$label.csv', lines.join('\n'));
      await repo.logExport(widget.clinicId, '${Fmt.shortDay(dayKey(_range.start))} – ${Fmt.shortDay(dayKey(_range.end))}');
    } catch (e) {
      if (mounted) showSnack(context, AppException.messageOf(e));
      return;
    }
    if (mounted) showSnack(context, 'Exported $n visits.');
  }

  @override
  Widget build(BuildContext context) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('Export data', style: ClinicText.cardTitle),
            const SizedBox(width: 8),
            const CChip('PIN', icon: Icons.lock_outline_rounded, fontSize: 11),
          ]),
          const SizedBox(height: 8),
          Text('Visits for a date range: date, token, doctor, patient, age/sex, phone, status and wait time.',
              style: AppText.bodyMedium.copyWith(fontSize: 13)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final r = await showDateRangePicker(context: context, firstDate: _today.subtract(const Duration(days: 365)), lastDate: _today, initialDateRange: _range);
              if (r != null) setState(() => _range = r);
            },
            icon: const Icon(Icons.date_range_rounded, size: 18),
            label: Text('${Fmt.shortDay(dayKey(_range.start))} – ${Fmt.shortDay(dayKey(_range.end))}', overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _export, icon: const Icon(Icons.file_download_outlined, size: 18), label: const Text('Export CSV')),
          const SizedBox(height: 8),
          Text('CSV opens in Excel.', style: ClinicText.small),
        ]),
      );
}
