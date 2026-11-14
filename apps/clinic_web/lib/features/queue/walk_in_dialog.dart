import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/connectivity.dart';
import '../../core/widgets/desktop.dart';
import '../../data/clinic_repository.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'queue_actions.dart';

/// W-13 / C-06: phone → profiles at this clinic → doctor → Create & Print.
Future<QueueToken?> showWalkInDialog(BuildContext context, String clinicId, {String? doctorId, String? phone, String? patientId}) =>
    showDialog<QueueToken>(
      context: context,
      builder: (_) => _WalkInDialog(clinicId: clinicId, doctorId: doctorId, phone: phone, patientId: patientId),
    );

class _WalkInDialog extends ConsumerStatefulWidget {
  const _WalkInDialog({required this.clinicId, this.doctorId, this.phone, this.patientId});
  final String clinicId;
  final String? doctorId;
  final String? phone;
  final String? patientId;

  @override
  ConsumerState<_WalkInDialog> createState() => _WalkInDialogState();
}

class _WalkInDialogState extends ConsumerState<_WalkInDialog> {
  late final _phone = TextEditingController(text: widget.phone == null ? '' : PhoneUtils.formatLocal(PhoneUtils.normalizeLocal(widget.phone!)));
  final _name = TextEditingController();
  final _age = TextEditingController();
  Gender? _gender;
  Relation _relation = Relation.other;
  late String? _patientId = widget.patientId;
  bool _newPatient = false;
  late String? _doctorId = widget.doctorId;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    _age.dispose();
    super.dispose();
  }

  bool get _phoneOk => PhoneUtils.isValidLocal(_phone.text);

  List<ClinicPatient> _profiles() {
    if (!_phoneOk) return const [];
    final e164 = PhoneUtils.toE164(_phone.text);
    return ref.read(repositoryProvider).searchPatients(widget.clinicId, e164).where((p) => p.patient.phone == e164).toList();
  }

  /// D-22: the same number's profiles from the Asani app / other clinics
  /// (name, relation, age, gender only), minus the ones already listed above.
  PhoneLookup? _lookup() => _phoneOk ? ref.read(repositoryProvider).lookupPhone(widget.clinicId, PhoneUtils.toE164(_phone.text)) : null;

  bool _similarName(List<String> names) {
    final n = _name.text.trim().toLowerCase();
    if (n.length < 3) return false;
    return names.any((name) {
      final o = name.toLowerCase();
      return o == n || o.split(' ').first == n.split(' ').first;
    });
  }

  Future<void> _create() async {
    final doctorId = _doctorId;
    if (doctorId == null) return;
    setState(() => _busy = true);
    final repo = ref.read(repositoryProvider);
    QueueToken? token;
    final ok = await runAction(context, () async {
      token = await repo.createWalkIn(
        widget.clinicId,
        doctorId,
        patientId: _newPatient ? null : _patientId,
        phone: _newPatient ? null : PhoneUtils.toE164(_phone.text),
        newPatient: _newPatient
            ? NewPatient(
                phone: PhoneUtils.toE164(_phone.text),
                name: _name.text,
                age: int.tryParse(_age.text),
                gender: _gender!,
                relation: _relation,
              )
            : null,
      );
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok && token != null) {
      QueueActions.printForm(ref, token!, context: context);
      showSnack(context, 'Walk-in ${token!.label} created. Printing the clinic form…');
      Navigator.pop(context, token);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(repoTickProvider);
    final doctors = ref.watch(doctorsProvider(widget.clinicId));
    _doctorId ??= doctors.firstOrNull?.id;
    final profiles = _profiles();
    final lookup = _lookup();
    final here = {for (final p in profiles) p.patient.id};
    final others = [for (final p in lookup?.profiles ?? const <PhoneProfile>[]) if (!here.contains(p.id) && !p.atThisClinic) p];
    final age = int.tryParse(_age.text);
    final newOk = _name.text.trim().length >= 2 && _gender != null && (_age.text.isEmpty || (age != null && age >= 0 && age <= 120));
    final ready = _phoneOk && _doctorId != null && (_newPatient ? newOk : _patientId != null) && ref.watch(isOnlineProvider);
    final doctor = doctors.where((d) => d.id == _doctorId).firstOrNull;
    final day = doctor == null ? null : ref.watch(queueDayProvider((widget.clinicId, doctor.id)));

    return AppDialog(
      title: 'New walk-in token',
      subtitle: 'Same number sequence as app bookings.',
      width: 620,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: ready && !_busy ? _create : null,
          icon: const Icon(Icons.print_rounded),
          label: Text(doctor == null || day == null ? 'Create & Print' : 'Create ${doctor.tokenPrefix}-${day.lastTokenNumber + 1} & Print'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FieldLabel(
          '1. Phone number',
          child: TextField(
            controller: _phone,
            autofocus: widget.phone == null,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]')), LengthLimitingTextInputFormatter(15)],
            decoration: InputDecoration(
              hintText: '300 1234567',
              prefixIcon: const Icon(Icons.phone_rounded),
              prefixText: '+92  ',
              suffixIcon: _phoneOk ? const Icon(Icons.check_circle_rounded, color: AppColors.success) : null,
            ),
            onChanged: (_) => setState(() {
              _patientId = null;
              _newPatient = false;
            }),
          ),
        ),
        if (_phoneOk) ...[
          Text('2. Patient', style: AppText.labelMedium.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          if (profiles.isEmpty && others.isEmpty && !_newPatient && !(lookup?.loading ?? false))
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: Text('No patients on this number yet.', style: AppText.bodyMedium),
            ),
          for (final p in profiles) _profileTile(p),
          if (lookup != null && lookup.loading)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: Text('Checking the Asani app for this number…', style: AppText.labelSmall),
            ),
          if (lookup?.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: Banner2(text: lookup!.error!, icon: Icons.info_outline_rounded),
            ),
          if (others.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: Gap.xs, bottom: 6),
              child: Text('On the Asani app, new to this clinic', style: AppText.labelSmall.copyWith(color: AppColors.textSecondary)),
            ),
            for (final p in others) _otherTile(p),
          ],
          _newPatientTile(),
          if (_newPatient) ...[
            const SizedBox(height: Gap.md),
            _newPatientForm([for (final p in profiles) p.patient.name, for (final p in others) p.name]),
          ],
          const SizedBox(height: Gap.lg),
          FieldLabel(
            '3. Doctor',
            child: Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
              for (final d in doctors)
                ChoiceChip(
                  avatar: LetterBadge(d.tokenPrefix, size: 22),
                  label: Text(d.name),
                  selected: d.id == _doctorId,
                  onSelected: (_) => setState(() => _doctorId = d.id),
                ),
            ]),
          ),
          if (day != null && day.sessionStatus == SessionStatus.ended)
            const Banner2(text: "This doctor's session has ended today.", icon: Icons.info_outline_rounded),
        ],
      ]),
    );
  }

  Widget _profileTile(ClinicPatient p) {
    final selected = !_newPatient && _patientId == p.patient.id;
    final age = p.patient.age(pktNow());
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
        borderColor: selected ? AppColors.primary : AppColors.border,
        color: selected ? AppColors.primaryContainer.withValues(alpha: 0.5) : AppColors.surface,
        onTap: () => setState(() {
          _patientId = p.patient.id;
          _newPatient = false;
        }),
        child: Row(children: [
          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? AppColors.primary : AppColors.textMuted),
          const SizedBox(width: Gap.md),
          InitialsAvatar(name: p.patient.name, size: 36, bg: InitialsAvatar.colorsFor(p.patient.relation).$1, fg: InitialsAvatar.colorsFor(p.patient.relation).$2),
          const SizedBox(width: Gap.md),
          Expanded(child: TwoLine(p.patient.name, '${p.patient.relation.label} · ${age ?? '—'} / ${p.patient.gender.short}')),
          Text(p.visitCount == 0 ? 'No visits yet' : '${p.visitCount} visits here', style: AppText.labelSmall),
        ]),
      ),
    );
  }

  /// D-22 profile from another clinic / the app: only name, relation, age, gender.
  Widget _otherTile(PhoneProfile p) {
    final selected = !_newPatient && _patientId == p.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
        borderColor: selected ? AppColors.primary : AppColors.border,
        color: selected ? AppColors.primaryContainer.withValues(alpha: 0.5) : AppColors.surface,
        onTap: () => setState(() {
          _patientId = p.id;
          _newPatient = false;
        }),
        child: Row(children: [
          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? AppColors.primary : AppColors.textMuted),
          const SizedBox(width: Gap.md),
          InitialsAvatar(name: p.name, size: 36, bg: InitialsAvatar.colorsFor(p.relation).$1, fg: InitialsAvatar.colorsFor(p.relation).$2),
          const SizedBox(width: Gap.md),
          Expanded(child: TwoLine(p.name, '${p.relation.label} · ${p.age ?? '—'} / ${p.gender.short}')),
          Text('New to this clinic', style: AppText.labelSmall),
        ]),
      ),
    );
  }

  Widget _newPatientTile() => AppCard(
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
        borderColor: _newPatient ? AppColors.primary : AppColors.border,
        onTap: () => setState(() {
          _newPatient = true;
          _patientId = null;
        }),
        child: Row(children: [
          Icon(_newPatient ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: _newPatient ? AppColors.primary : AppColors.textMuted),
          const SizedBox(width: Gap.md),
          const IconBox(icon: Icons.person_add_alt_1_rounded, size: 36),
          const SizedBox(width: Gap.md),
          Text('New patient', style: AppText.labelLarge.copyWith(color: AppColors.primary)),
        ]),
      );

  Widget _newPatientForm(List<String> existing) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: FieldLabel('Full name', child: TextField(controller: _name, autofocus: true, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'Patient name'), onChanged: (_) => setState(() {}))),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: FieldLabel(
              'Age',
              child: TextField(
                controller: _age,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                decoration: const InputDecoration(hintText: 'Years'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
        ]),
        if (_similarName(existing))
          const Padding(
            padding: EdgeInsets.only(bottom: Gap.md),
            child: Banner2(text: 'A patient with a similar name is already on this phone. Pick them above if it is the same person.', icon: Icons.content_copy_rounded),
          ),
        FieldLabel(
          'Gender',
          child: Wrap(spacing: Gap.sm, children: [
            for (final g in Gender.values) ChoiceChip(label: Text(g.label), selected: _gender == g, onSelected: (_) => setState(() => _gender = g)),
          ]),
        ),
        FieldLabel(
          'Relation to phone owner (optional)',
          child: Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
            for (final r in Relation.values) ChoiceChip(label: Text(r.label), selected: _relation == r, onSelected: (_) => setState(() => _relation = r)),
          ]),
        ),
        Text('If this person installs the Asani app with this number, these visits show up in their account.', style: AppText.labelSmall),
      ]);
}

/// Pretty "+92 300 1234567" for display in lists.
String phoneLabel(String e164) => Fmt.phone(e164);
