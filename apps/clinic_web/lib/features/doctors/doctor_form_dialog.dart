import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/clinic_kit.dart';
import 'week_schedule.dart';

/// What the form returns: the doctor, plus a PMDC number typed now (null = keep the saved one, D-33).
typedef DoctorFormResult = ({Doctor doctor, String? pmdc});

/// W-17 doctor form (C-11). Returns the edited doctor; the caller saves it.
/// The clinic adds and edits its own doctors (D-19).
Future<DoctorFormResult?> showDoctorForm(BuildContext context, {Doctor? initial, required String clinicId, bool hasPmdc = false}) =>
    showDialog<DoctorFormResult>(context: context, builder: (_) => _DoctorForm(initial: initial, clinicId: clinicId, hasPmdc: hasPmdc));

class _DoctorForm extends StatefulWidget {
  const _DoctorForm({this.initial, required this.clinicId, this.hasPmdc = false});
  final Doctor? initial;
  final String clinicId;
  final bool hasPmdc;

  @override
  State<_DoctorForm> createState() => _DoctorFormState();
}

class _DoctorFormState extends State<_DoctorForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name ?? 'Dr. ');
  late final _qual = TextEditingController(text: widget.initial?.qualification ?? '');
  // D-31: one key from the fixed list. Old free text is mapped; unknown stays empty so the clinic picks.
  late Speciality? _spec = widget.initial == null || widget.initial!.specialityFlagged
      ? null
      : Speciality.fromKey(widget.initial!.speciality) ?? Speciality.fromLegacy(widget.initial!.speciality);
  final _pmdc = TextEditingController();
  late final _avg = TextEditingController(text: '${widget.initial?.avgConsultMinutes ?? 10}');
  late final _max = TextEditingController(text: '${widget.initial?.maxTokensPerDay ?? 40}');
  late final _window = TextEditingController(text: '${widget.initial?.bookingWindowDays ?? 7}');
  late Map<String, DaySchedule?> _schedule = {
    for (final k in weekdayKeys) k: widget.initial == null ? (k == 'sun' ? null : const DaySchedule('17:00', '21:00')) : widget.initial!.schedule[k],
  };

  @override
  void dispose() {
    for (final c in [_name, _qual, _pmdc, _avg, _max, _window]) {
      c.dispose();
    }
    super.dispose();
  }

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
    Navigator.pop(context, (
      pmdc: _pmdc.text.trim().isEmpty ? null : _pmdc.text.trim(),
      doctor: Doctor(
        id: i?.id ?? 'new',
        clinicId: widget.clinicId,
        name: _name.text.trim(),
        speciality: _spec!.key,
        qualification: _qual.text.trim().isEmpty ? null : _qual.text.trim(),
        tokenPrefix: i?.tokenPrefix ?? '?',
        avgConsultMinutes: int.parse(_avg.text),
        maxTokensPerDay: int.parse(_max.text),
        bookingWindowDays: int.parse(_window.text),
        schedule: Map.of(_schedule),
        onLeaveDates: i?.onLeaveDates ?? const [],
        active: i?.active ?? true,
        sortOrder: i?.sortOrder ?? 0,
        doctorGroupId: i?.doctorGroupId,
      ),
    ));
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
                child: DropdownButtonFormField<Speciality>(
                  initialValue: _spec,
                  hint: const Text('Pick a speciality'),
                  items: [for (final s in Speciality.values) DropdownMenuItem(value: s, child: Text(s.display))],
                  onChanged: (v) => setState(() => _spec = v),
                  validator: (v) => v == null ? 'Required' : null,
                ),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(child: FieldLabel('Qualification (optional)', child: TextFormField(controller: _qual, decoration: const InputDecoration(hintText: 'MBBS, FCPS')))),
          ]),
          // D-32 / D-33: optional, stored admin-only; the clinic never sees it again.
          FieldLabel(
            'PMDC number (optional)',
            child: TextFormField(
              controller: _pmdc,
              decoration: InputDecoration(
                hintText: '12345-P',
                helperText: widget.hasPmdc
                    ? 'PMDC number on file. Type a new one to change it.'
                    : 'Helps patients find this doctor at all their clinics.',
              ),
              validator: (v) => (v ?? '').trim().isEmpty || isValidPmdc(v!) ? null : 'Not a valid PMDC number',
            ),
          ),
          Row(children: [
            _numField('Avg consultation', _avg, 2, 120, 'min'),
            const SizedBox(width: Gap.md),
            _numField('Max tokens per day', _max, 1, 300, 'tokens'),
            const SizedBox(width: Gap.md),
            _numField('Booking window', _window, 0, 60, 'days'),
          ]),
          Text('Weekly schedule', style: AppText.labelMedium.copyWith(color: AppColors.textSecondary)),
          Text('Click a day to change it.', style: ClinicText.small),
          const SizedBox(height: Gap.sm),
          WeekSchedule(schedule: _schedule, onChanged: (v) => setState(() => _schedule = v)),
        ]),
      ),
    );
  }
}
