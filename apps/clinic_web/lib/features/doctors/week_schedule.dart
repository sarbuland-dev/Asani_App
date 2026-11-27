import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/clinic_kit.dart';

const dayNames = {'mon': 'Monday', 'tue': 'Tuesday', 'wed': 'Wednesday', 'thu': 'Thursday', 'fri': 'Friday', 'sat': 'Saturday', 'sun': 'Sunday'};

/// Times in 30-minute steps for the schedule dropdowns.
final _times = [for (var m = 6 * 60; m <= 23 * 60 + 30; m += 30) minutesToHhmm(m)];

/// W-17: the week as time blocks. Clicking a day opens a small popup to turn
/// it on or off and set its start and end time.
class WeekSchedule extends StatelessWidget {
  const WeekSchedule({super.key, required this.schedule, required this.onChanged});
  final Map<String, DaySchedule?> schedule;
  final ValueChanged<Map<String, DaySchedule?>> onChanged;

  static const _height = 150.0;

  Future<void> _edit(BuildContext context, String day) async {
    final result = await showDialog<Map<String, DaySchedule?>>(
      context: context,
      builder: (_) => _DayDialog(day: day, schedule: schedule),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    // The time axis covers every shift, and at least 10 AM – 10 PM.
    var from = 10 * 60, to = 22 * 60;
    for (final s in schedule.values.whereType<DaySchedule>()) {
      if (s.startMinutes < from) from = s.startMinutes ~/ 60 * 60;
      if (s.endMinutes > to) to = (s.endMinutes + 59) ~/ 60 * 60;
    }
    final span = (to - from).toDouble();
    final ticks = [for (var i = 0; i < 4; i++) from + (span * i / 3).round()];

    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      SizedBox(
        width: 46,
        height: _height,
        child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final t in ticks) Text(_hourLabel(t), style: ClinicText.small.copyWith(fontSize: 11)),
        ]),
      ),
      for (final k in weekdayKeys) ...[
        const SizedBox(width: 6),
        Expanded(
          child: Column(children: [
            Text(dayNames[k]!.substring(0, 3), style: ClinicText.small.copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Semantics(
              button: true,
              label: '${dayNames[k]}: ${schedule[k] == null ? 'off' : Fmt.timeRange(schedule[k]!)}. Change',
              child: Material(
                color: ClinicColors.quiet,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _edit(context, k),
                  child: SizedBox(height: _height, width: double.infinity, child: _column(schedule[k], from, span)),
                ),
              ),
            ),
          ]),
        ),
      ],
    ]);
  }

  static String _hourLabel(int minutes) {
    final h = (minutes ~/ 60) % 24;
    return '${(h + 11) % 12 + 1} ${h < 12 ? 'AM' : 'PM'}';
  }

  Widget _column(DaySchedule? s, int from, double span) {
    if (s == null) return Center(child: Text('Off', style: ClinicText.small.copyWith(fontSize: 11, fontWeight: FontWeight.w700)));
    final top = ((s.startMinutes - from) / span * _height).clamp(0.0, _height - 36);
    final height = ((s.endMinutes - s.startMinutes) / span * _height).clamp(36.0, _height - top);
    return Stack(children: [
      Positioned(
        top: top,
        left: 4,
        right: 4,
        height: height,
        child: Container(
          padding: const EdgeInsets.all(4),
          alignment: Alignment.topLeft,
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.primaryMid, AppColors.primary]),
            borderRadius: BorderRadius.circular(9),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: Text(Fmt.timeRangeShort(s), style: ClinicText.small.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.onPrimary)),
          ),
        ),
      ),
    ]);
  }
}

class _DayDialog extends StatefulWidget {
  const _DayDialog({required this.day, required this.schedule});
  final String day;
  final Map<String, DaySchedule?> schedule;

  @override
  State<_DayDialog> createState() => _DayDialogState();
}

class _DayDialogState extends State<_DayDialog> {
  late bool _on = widget.schedule[widget.day] != null;
  late String _start = widget.schedule[widget.day]?.start ?? '17:00';
  late String _end = widget.schedule[widget.day]?.end ?? '21:00';
  bool _copy = false;

  bool get _valid => !_on || DaySchedule(_start, _end).endMinutes > DaySchedule(_start, _end).startMinutes;

  void _done() {
    final value = _on ? DaySchedule(_start, _end) : null;
    final next = Map<String, DaySchedule?>.of(widget.schedule)..[widget.day] = value;
    if (_copy && value != null) {
      // Only the other working days get this timing; days off stay off.
      for (final k in weekdayKeys) {
        if (next[k] != null) next[k] = value;
      }
    }
    Navigator.pop(context, next);
  }

  Widget _time(String label, String value, ValueChanged<String> onChanged) => Expanded(
        child: LabeledField(
          label,
          child: DropdownButtonFormField<String>(
            initialValue: _times.contains(value) ? value : null,
            isExpanded: true,
            hint: Text(Fmt.time(value)),
            items: [for (final t in _times) DropdownMenuItem(value: t, child: Text(Fmt.time(t)))],
            onChanged: (v) {
              if (v != null) setState(() => onChanged(v));
            },
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => AppDialog(
        title: dayNames[widget.day]!,
        width: 400,
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _valid ? _done : null, child: const Text('Done')),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(_on ? 'Working this day' : 'Day off', style: AppText.labelMedium)),
            Switch(value: _on, onChanged: (v) => setState(() => _on = v)),
          ]),
          if (_on) ...[
            const SizedBox(height: 12),
            Row(children: [
              _time('Start', _start, (v) => _start = v),
              const SizedBox(width: 12),
              _time('End', _end, (v) => _end = v),
            ]),
            if (!_valid) ...[const SizedBox(height: 10), const NoteBox.error('End time must be after start time.')],
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _copy,
              onChanged: (v) => setState(() => _copy = v ?? false),
              title: Text('Copy this timing to all working days', style: AppText.bodyMedium.copyWith(color: AppColors.textPrimary)),
            ),
          ],
        ]),
      );
}
