import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'doctors_screen.dart';
import 'week_schedule.dart';

/// This week's visits of the clinic, for "seen in 7 days" and "avg wait".
final _lastWeekProvider = FutureProvider.autoDispose.family<List<QueueToken>, String>((ref, clinicId) {
  ref.watch(repoTickProvider);
  final today = parseDayKey(dayKey(pktNow()));
  return ref.watch(repositoryProvider).loadTokens(clinicId, dayKey(today.subtract(const Duration(days: 6))), dayKey(today));
});

/// W-17 / C-11 (D-19): the clinic adds, edits and deactivates its own doctors
/// and sets leave. Cards on the left, the picked doctor's form on the right.
class ClinicDoctorsScreen extends ConsumerStatefulWidget {
  const ClinicDoctorsScreen(this.clinicId, {super.key});
  final String clinicId;

  @override
  ConsumerState<ClinicDoctorsScreen> createState() => _ClinicDoctorsScreenState();
}

class _ClinicDoctorsScreenState extends ConsumerState<ClinicDoctorsScreen> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final doctors = ref.watch(allDoctorsProvider(widget.clinicId));
    final selected = doctors.where((d) => d.id == _selectedId).firstOrNull ?? doctors.firstOrNull;
    void add() => addDoctor(context, ref, widget.clinicId);

    return ClinicPage(
      title: 'Doctors',
      subtitle: '${doctors.length} doctor${doctors.length == 1 ? '' : 's'} · a doctor can be booked as soon as you save. '
          'Letters (A, B, C…) are given automatically and never reused.',
      actions: [FilledButton.icon(onPressed: add, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add doctor'))],
      children: [
        if (selected == null)
          EmptyState(
            icon: Icons.medical_services_outlined,
            title: 'Add your first doctor',
            message: 'Patients can book once a doctor with a weekly schedule is added.',
            actionLabel: 'Add doctor',
            onAction: add,
          )
        else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 340,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final d in doctors)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _DoctorTile(doctor: d, selected: d.id == selected.id, onTap: () => setState(() => _selectedId = d.id)),
                  ),
                const _Legend(),
              ]),
            ),
            const SizedBox(width: 18),
            Expanded(child: _DoctorEditor(key: ValueKey(_editorKey(selected)), clinicId: widget.clinicId, doctor: selected)),
          ]),
      ],
    );
  }

  /// A new form when another doctor is picked or the saved values change.
  static String _editorKey(Doctor d) => [
        d.id,
        d.name,
        d.qualification,
        d.speciality,
        d.avgConsultMinutes,
        d.maxTokensPerDay,
        d.bookingWindowDays,
        for (final k in weekdayKeys) '${d.schedule[k]?.start}-${d.schedule[k]?.end}',
      ].join('|');
}

enum _DayKind { today, works, leave, off }

(Color, Color) _dayColors(_DayKind kind) => switch (kind) {
      _DayKind.today => (AppColors.primary, AppColors.onPrimary),
      _DayKind.works => (ClinicColors.tint, AppColors.primary),
      _DayKind.leave => (AppColors.dangerContainer, AppColors.dangerText),
      _DayKind.off => (AppColors.cream, AppColors.textSecondary),
    };

class _DoctorTile extends ConsumerWidget {
  const _DoctorTile({required this.doctor, required this.selected, required this.onTap});
  final Doctor doctor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = doctor;
    final today = parseDayKey(dayKey(pktNow()));
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final schedule = d.scheduleOn(today);
    final addedAt = ref.watch(doctorAddedAtProvider)[d.id];

    return Opacity(
      opacity: d.active ? 1 : 0.65,
      child: Semantics(
        selected: selected,
        button: true,
        child: Panel(
          radius: 18,
          borderColor: selected ? AppColors.primary : AppColors.border,
          borderWidth: selected ? 2 : 1,
          padding: const EdgeInsets.all(14),
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              _LetterAvatar(doctor: d, size: 50, solid: selected),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.titleSmall.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
                  if (d.specialityFlagged)
                    const CChip.amber('Please pick a speciality', dot: false, fontSize: 11)
                  else
                    Text([d.specialityEnum.display, ?d.qualification].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: ClinicText.small),
                ]),
              ),
              const SizedBox(width: 6),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                d.active ? const CChip.green('Active', fontSize: 11) : const CChip('Inactive', fontSize: 11),
                if (isNewDoctor(addedAt)) ...[const SizedBox(height: 4), const CChip('New', bg: AppColors.primaryLight, fg: AppColors.onPrimary, fontSize: 10)],
              ]),
            ]),
            if (d.active) ...[
              const SizedBox(height: 12),
              Row(children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(child: _day(d, monday.add(Duration(days: i)), today, weekdayKeys[i])),
                ],
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: Text(
                    'Today ${d.onLeave(today) ? 'on leave' : schedule == null ? 'off' : Fmt.timeRange(schedule)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ClinicText.small.copyWith(color: d.onLeave(today) ? AppColors.dangerText : AppColors.textSecondary),
                  ),
                ),
                Text('${d.maxTokensPerDay} tokens / day', style: ClinicText.small),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _day(Doctor d, DateTime date, DateTime today, String key) {
    final kind = d.onLeave(date)
        ? _DayKind.leave
        : d.schedule[key] == null
            ? _DayKind.off
            : date == today
                ? _DayKind.today
                : _DayKind.works;
    final (bg, fg) = _dayColors(kind);
    return Tooltip(
      message: '${dayNames[key]}: ${switch (kind) { _DayKind.leave => 'leave', _DayKind.off => 'off', _ => Fmt.timeRange(d.schedule[key]!) }}',
      child: Container(
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7)),
        child: Text(dayNames[key]![0], style: ClinicText.small.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) => Wrap(spacing: 14, runSpacing: 6, children: [
        for (final (label, kind) in const [('Today', _DayKind.today), ('Works', _DayKind.works), ('Leave', _DayKind.leave), ('Off', _DayKind.off)])
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: _dayColors(kind).$1, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 5),
            Text(label, style: ClinicText.small.copyWith(fontSize: 11)),
          ]),
      ]);
}

/// Initials with the token letter in the corner.
class _LetterAvatar extends StatelessWidget {
  const _LetterAvatar({required this.doctor, required this.size, this.solid = false, this.onDark = false});
  final Doctor doctor;
  final double size;
  final bool solid;
  final bool onDark;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: Stack(clipBehavior: Clip.none, children: [
          onDark ? Av(doctor.name, size: size, bg: AppColors.cream) : (solid ? Av.solid(doctor.name, size: size) : Av(doctor.name, size: size)),
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: onDark || !solid ? AppColors.primary : AppColors.cream,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: onDark ? AppColors.navy : AppColors.surface, width: 2),
              ),
              child: Text(doctor.tokenPrefix,
                  style: ClinicText.small.copyWith(fontSize: 11, height: 1, fontWeight: FontWeight.w800, color: onDark || !solid ? AppColors.onPrimary : AppColors.primary)),
            ),
          ),
        ]),
      );
}

class _DoctorEditor extends ConsumerStatefulWidget {
  const _DoctorEditor({super.key, required this.clinicId, required this.doctor});
  final String clinicId;
  final Doctor doctor;

  @override
  ConsumerState<_DoctorEditor> createState() => _DoctorEditorState();
}

class _DoctorEditorState extends ConsumerState<_DoctorEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.doctor.name);
  late final _qual = TextEditingController(text: widget.doctor.qualification ?? '');
  final _pmdc = TextEditingController();
  late final _avg = TextEditingController(text: '${widget.doctor.avgConsultMinutes}');
  late final _max = TextEditingController(text: '${widget.doctor.maxTokensPerDay}');
  late final _window = TextEditingController(text: '${widget.doctor.bookingWindowDays}');
  // D-31: one key from the fixed list. Unknown old text stays empty so the clinic picks.
  late Speciality? _spec =
      widget.doctor.specialityFlagged ? null : Speciality.fromKey(widget.doctor.speciality) ?? Speciality.fromLegacy(widget.doctor.speciality);
  late Map<String, DaySchedule?> _schedule = {for (final k in weekdayKeys) k: widget.doctor.schedule[k]};
  bool _editPmdc = false;

  @override
  void dispose() {
    for (final c in [_name, _qual, _pmdc, _avg, _max, _window]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final d = widget.doctor; // live: leave dates may have changed since the form opened
    final doctor = Doctor(
      id: d.id,
      clinicId: widget.clinicId,
      name: _name.text.trim(),
      speciality: _spec!.key,
      qualification: _qual.text.trim().isEmpty ? null : _qual.text.trim(),
      tokenPrefix: d.tokenPrefix,
      avgConsultMinutes: int.parse(_avg.text),
      maxTokensPerDay: int.parse(_max.text),
      bookingWindowDays: int.parse(_window.text),
      schedule: Map.of(_schedule),
      onLeaveDates: d.onLeaveDates,
      active: d.active,
      sortOrder: d.sortOrder,
      doctorGroupId: d.doctorGroupId,
    );
    final pmdc = _pmdc.text.trim();
    final ok = await runAction(context, () => ref.read(repositoryProvider).saveDoctor(widget.clinicId, doctor, pmdcNumber: pmdc.isEmpty ? null : pmdc),
        success: 'Changes saved.');
    if (ok && mounted) {
      setState(() {
        _pmdc.clear();
        _editPmdc = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Panel(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _section(Icons.person_outline_rounded, 'Details'),
                const SizedBox(height: 14),
                ..._details(),
                const SizedBox(height: 20),
                _section(Icons.calendar_today_outlined, 'Weekly schedule', trailing: Text('Click a day to change it', style: ClinicText.small)),
                const SizedBox(height: 14),
                WeekSchedule(schedule: _schedule, onChanged: (v) => setState(() => _schedule = v)),
                const SizedBox(height: 20),
                _section(Icons.event_busy_outlined, 'Leave dates', danger: true),
                const SizedBox(height: 12),
                ..._leave(),
                const SizedBox(height: 20),
                const Divider(color: AppColors.cream),
                const SizedBox(height: 16),
                Row(children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: widget.doctor.active ? AppColors.danger : AppColors.primary),
                    onPressed: () => toggleDoctorActive(context, ref, widget.doctor),
                    child: Text(widget.doctor.active ? 'Deactivate doctor' : 'Reactivate doctor'),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32)),
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ]),
              ]),
            ),
          ),
        ]),
      );

  Widget _header() {
    final d = widget.doctor;
    final week = ref.watch(_lastWeekProvider(widget.clinicId)).value?.where((t) => t.token.doctorId == d.id).toList();
    final seen = week?.where((t) => t.status == TokenStatus.completed).length;
    final waits = week?.map((t) => t.waitMinutes).whereType<int>().toList() ?? const <int>[];
    final avg = waits.isEmpty ? null : waits.reduce((a, b) => a + b) / waits.length;
    final addedAt = ref.watch(doctorAddedAtProvider)[d.id];
    final last = ref.watch(activityProvider(widget.clinicId)).where((a) => a.target.startsWith(d.name)).firstOrNull;
    final changes = [
      if (addedAt != null) 'Added ${WebFmt.ago(addedAt, now: pktNow())}',
      if (last != null) 'Last change: ${last.action} ${WebFmt.ago(last.at, now: pktNow())}',
    ].join(' · ');

    Widget stat(String value, String label) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.onPrimary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.onPrimary.withValues(alpha: 0.12)),
          ),
          child: Column(children: [
            Text(value, style: AppText.titleMedium.copyWith(fontWeight: FontWeight.w800, color: AppColors.onPrimary)),
            Text(label, style: ClinicText.small.copyWith(fontSize: 11, color: AppColors.primarySoft)),
          ]),
        );

    return HeroBlock(
      radius: 0,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      child: Row(children: [
        _LetterAvatar(doctor: d, size: 62, onDark: true),
        const SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.titleMedium.copyWith(fontSize: 20, color: AppColors.onPrimary)),
            Text('Token letter ${d.tokenPrefix} · given automatically', style: AppText.bodyMedium.copyWith(fontSize: 13, color: AppColors.onPrimaryMuted)),
            if (changes.isNotEmpty) Text(changes, maxLines: 1, overflow: TextOverflow.ellipsis, style: ClinicText.small.copyWith(color: AppColors.primarySoft)),
          ]),
        ),
        const SizedBox(width: 10),
        stat(seen == null ? '—' : '$seen', 'seen in 7 days'),
        const SizedBox(width: 8),
        stat(WebFmt.minutes(avg), 'avg wait'),
      ]),
    );
  }

  Widget _section(IconData icon, String title, {bool danger = false, Widget? trailing}) => Row(children: [
        IconTile(icon, size: 30, bg: danger ? AppColors.dangerContainer : ClinicColors.tint, fg: danger ? AppColors.dangerText : AppColors.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: AppText.titleSmall.copyWith(fontSize: 15, fontWeight: FontWeight.w800))),
        ?trailing,
      ]);

  String? _range(String? v, int min, int max) {
    final n = int.tryParse(v ?? '');
    return n == null || n < min || n > max ? '$min–$max' : null;
  }

  Widget _number(String label, TextEditingController c, int min, int max, String suffix) => Expanded(
        child: LabeledField(
          label,
          child: TextFormField(
            controller: c,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
            decoration: InputDecoration(suffixText: suffix),
            validator: (v) => _range(v, min, max),
          ),
        ),
      );

  List<Widget> _details() {
    final onFile = ref.watch(repositoryProvider).hasPmdc(widget.doctor.id);
    const gap = SizedBox(width: 12);
    return [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 2,
          child: LabeledField(
            'Name',
            child: TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v ?? '').replaceAll('Dr.', '').trim().length < 2 ? "Enter the doctor's name" : null,
            ),
          ),
        ),
        gap,
        Expanded(child: LabeledField('Qualification', child: TextFormField(controller: _qual, decoration: const InputDecoration(hintText: 'MBBS, FCPS')))),
      ]),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: LabeledField(
            'Speciality',
            child: DropdownButtonFormField<Speciality>(
              initialValue: _spec,
              isExpanded: true,
              hint: const Text('Pick a speciality'),
              items: [for (final s in Speciality.values) DropdownMenuItem(value: s, child: SpecialityOption(s, color: AppColors.primary))],
              onChanged: (v) => setState(() => _spec = v),
              validator: (v) => v == null ? 'Required' : null,
            ),
          ),
        ),
        gap,
        // D-32 / D-33: optional, stored admin-only; the clinic never sees it again.
        Expanded(
          child: LabeledField(
            'PMDC number (optional)',
            help: 'Helps patients find this doctor at all their clinics.',
            child: onFile && !_editPmdc
                ? Container(
                    height: 48,
                    padding: const EdgeInsets.only(left: 14, right: 4),
                    decoration: BoxDecoration(
                        color: ClinicColors.quiet, borderRadius: BorderRadius.circular(ClinicRadii.control), border: Border.all(color: AppColors.border)),
                    child: Row(children: [
                      Expanded(child: Text('On file', style: AppText.bodyMedium.copyWith(color: AppColors.textPrimary))),
                      TextButton(onPressed: () => setState(() => _editPmdc = true), child: const Text('Change')),
                    ]),
                  )
                : TextFormField(
                    controller: _pmdc,
                    decoration: const InputDecoration(hintText: '12345-P'),
                    validator: (v) => (v ?? '').trim().isEmpty || isValidPmdc(v!) ? null : 'Not a valid PMDC number',
                  ),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _number('Avg consultation', _avg, 2, 120, 'min'),
        gap,
        _number('Max tokens a day', _max, 1, 300, 'tokens'),
        gap,
        _number('Booking window', _window, 0, 60, 'days'),
      ]),
    ];
  }

  List<Widget> _leave() {
    final d = widget.doctor;
    final repo = ref.read(repositoryProvider);
    final today = dayKey(pktNow());
    final leaves = d.onLeaveDates.where((x) => x.compareTo(today) >= 0).toList()..sort();
    return [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final l in leaves)
          InputChip(
            label: Text(Fmt.shortDay(l)),
            labelStyle: AppText.labelSmall.copyWith(color: AppColors.dangerText, fontWeight: FontWeight.w700),
            backgroundColor: AppColors.dangerContainer,
            side: BorderSide.none,
            deleteIconColor: AppColors.dangerText,
            deleteButtonTooltipMessage: 'Remove leave',
            onDeleted: () => runAction(context, () => repo.removeLeave(d.id, l), success: 'Leave removed.'),
          ),
        TextButton.icon(
          onPressed: d.active ? () => addDoctorLeave(context, ref, d) : null,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add leave'),
        ),
      ]),
      // Tokens still booked on a leave day.
      for (final l in leaves) _bookedWarning(l),
    ];
  }

  Widget _bookedWarning(String date) {
    final d = widget.doctor;
    final booked = ref
        .watch(tokensOnProvider((widget.clinicId, date)))
        .where((t) => t.token.doctorId == d.id && t.status.isActive) // what cancelTokensOn cancels
        .length;
    if (booked == 0) return const SizedBox.shrink();
    final noun = 'token${booked == 1 ? '' : 's'}';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: NoteBox(
        '$booked $noun ${booked == 1 ? 'is' : 'are'} booked on ${Fmt.shortDay(date)}.',
        action: TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.warningText),
          onPressed: () async {
            final reason = await askReason(
              context,
              title: 'Cancel $booked $noun on ${Fmt.shortDay(date)}?',
              options: const ['Doctor on leave', 'Clinic closed', 'Other'],
              confirmLabel: 'Cancel $booked $noun',
              note: 'Patients who use the Asani app get a notification with this reason.', // D-23
            );
            if (reason == null || !mounted) return;
            await runAction(context, () => ref.read(repositoryProvider).cancelTokensOn(d.id, date, reason), success: '$booked $noun cancelled.');
          },
          child: const Text('Cancel them with a reason'),
        ),
      ),
    );
  }
}
