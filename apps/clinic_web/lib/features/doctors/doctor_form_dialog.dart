import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/desktop.dart';

const _dayNames = {'mon': 'Monday', 'tue': 'Tuesday', 'wed': 'Wednesday', 'thu': 'Thursday', 'fri': 'Friday', 'sat': 'Saturday', 'sun': 'Sunday'};

/// Times in 30-minute steps for the schedule dropdowns.
final _times = [for (var m = 6 * 60; m <= 23 * 60 + 30; m += 30) minutesToHhmm(m)];

/// W-17 doctor form (C-11). Returns the edited doctor; the caller saves it.
/// The clinic adds and edits its own doctors (D-19).
Future<Doctor?> showDoctorForm(BuildContext context, {Doctor? initial, required String clinicId}) =>
    showDialog<Doctor>(context: context, builder: (_) => _DoctorForm(initial: initial, clinicId: clinicId));

class _DoctorForm extends StatefulWidget {
  const _DoctorForm({this.initial, required this.clinicId});
  final Doctor? initial;
  final String clinicId;

  @override
  State<_DoctorForm> createState() => _DoctorFormState();
}

class _DoctorFormState extends State<_DoctorForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name ?? 'Dr. ');
  late final _qual = TextEditingController(text: widget.initial?.qualification ?? '');
  late final _spec = TextEditingController(text: widget.initial?.speciality ?? '');
  late final _avg = TextEditingController(text: '${widget.initial?.avgConsultMinutes ?? 10}');
  late final _max = TextEditingController(text: '${widget.initial?.maxTokensPerDay ?? 40}');
  late final _window = TextEditingController(text: '${widget.initial?.bookingWindowDays ?? 7}');
  late final Map<String, DaySchedule?> _schedule = {
    for (final k in weekdayKeys) k: widget.initial == null ? (k == 'sun' ? null : const DaySchedule('17:00', '21:00')) : widget.initial!.schedule[k],
  };

  @override
  void dispose() {
    for (final c in [_name, _qual, _spec, _avg, _max, _window]) {
      c.dispose();
    }
    super.dispose();
  }

  /// First working day (Mon → Sun), the source for "Copy … to all days".
  String? get _firstOn => weekdayKeys.where((k) => _schedule[k] != null).firstOrNull;

  void _copyFirstToAll() => setState(() {
        final src = _schedule[_firstOn];
        for (final k in weekdayKeys) {
          if (_schedule[k] != null) _schedule[k] = src;
        }
      });

  String? _num(String? v, int min, int max) {
    final n = int.tryParse(v ?? '');
    if (n == null || n < min || n > max) return '$min–$max';
    return null;
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final bad = _schedule.values.whereType<DaySchedule>().any((s) => s.endMinutes <= s.startMinutes);
    if (bad) {
      showSnack(context, 'End time must be after start time.');
      return;
    }
    final i = widget.initial;
    Navigator.pop(
      context,
      Doctor(
        id: i?.id ?? 'new',
        clinicId: widget.clinicId,
        name: _name.text.trim(),
        speciality: _spec.text.trim(),
        qualification: _qual.text.trim().isEmpty ? null : _qual.text.trim(),
        tokenPrefix: i?.tokenPrefix ?? '?',
        avgConsultMinutes: int.parse(_avg.text),
        maxTokensPerDay: int.parse(_max.text),
        bookingWindowDays: int.parse(_window.text),
        schedule: Map.of(_schedule),
        onLeaveDates: i?.onLeaveDates ?? const [],
        active: i?.active ?? true,
        sortOrder: i?.sortOrder ?? 0,
      ),
    );
  }

  Widget _numField(String label, TextEditingController c, int min, int max, String suffix) => Expanded(
        child: FieldLabel(
          label,
          child: TextFormField(
            controller: c,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
            decoration: InputDecoration(suffixText: suffix),
            validator: (v) => _num(v, min, max),
          ),
        ),
      );

  DropdownButton<String> _timeDrop(String value, ValueChanged<String> onChanged) => DropdownButton<String>(
        value: _times.contains(value) ? value : null,
        hint: Text(Fmt.time(value)),
        underline: const SizedBox.shrink(),
        borderRadius: BorderRadius.circular(Radii.button),
        items: [for (final t in _times) DropdownMenuItem(value: t, child: Text(Fmt.time(t)))],
        onChanged: (v) => v == null ? null : onChanged(v),
      );

  @override
  Widget build(BuildContext context) {
    final isNew = widget.initial == null;
    return AppDialog(
      title: isNew ? 'Add doctor' : 'Edit ${widget.initial!.name}',
      subtitle: isNew
          ? 'The token letter (A, B, C…) is assigned automatically.'
          : 'Token letter ${widget.initial!.tokenPrefix} (never changes).',
      width: 680,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: Text(isNew ? 'Add doctor' : 'Save changes')),
      ],
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FieldLabel(
            'Full name',
            child: TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v ?? '').replaceAll('Dr.', '').trim().length < 2 ? 'Enter the doctor\'s name' : null,
            ),
          ),
          Row(children: [
            Expanded(
              child: FieldLabel(
                'Speciality',
                child: TextFormField(controller: _spec, decoration: const InputDecoration(hintText: 'General Physician'), validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(child: FieldLabel('Qualification (optional)', child: TextFormField(controller: _qual, decoration: const InputDecoration(hintText: 'MBBS, FCPS')))),
          ]),
          Row(children: [
            _numField('Avg consultation', _avg, 2, 120, 'min'),
            const SizedBox(width: Gap.md),
            _numField('Max tokens per day', _max, 1, 300, 'tokens'),
            const SizedBox(width: Gap.md),
            _numField('Booking window', _window, 0, 60, 'days'),
          ]),
          Row(children: [
            Expanded(child: Text('Weekly schedule', style: AppText.labelMedium.copyWith(color: AppColors.textSecondary))),
            // One button: the first working day's timing goes to every working day.
            TextButton.icon(
              onPressed: _schedule.values.whereType<DaySchedule>().length < 2 ? null : _copyFirstToAll,
              icon: const Icon(Icons.content_copy_rounded, size: 18),
              label: Text(_firstOn == null ? 'Copy to all days' : 'Copy ${_dayNames[_firstOn]} timing to all days'),
            ),
          ]),
          const SizedBox(height: Gap.sm),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
            child: Column(children: [
              for (final k in weekdayKeys)
                SizedBox(
                  height: 52,
                  child: Row(children: [
                    SizedBox(width: 120, child: Text(_dayNames[k]!, style: AppText.labelMedium)),
                    Switch(
                      value: _schedule[k] != null,
                      onChanged: (on) => setState(() => _schedule[k] = on ? const DaySchedule('17:00', '21:00') : null),
                    ),
                    const SizedBox(width: Gap.md),
                    if (_schedule[k] == null)
                      Text('Off', style: AppText.bodyMedium)
                    else ...[
                      _timeDrop(_schedule[k]!.start, (v) => setState(() => _schedule[k] = DaySchedule(v, _schedule[k]!.end))),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: Gap.md), child: Text('to', style: AppText.bodyMedium)),
                      _timeDrop(_schedule[k]!.end, (v) => setState(() => _schedule[k] = DaySchedule(_schedule[k]!.start, v))),
                    ],
                  ]),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
