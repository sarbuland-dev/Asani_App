import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/net/connectivity.dart';
import '../../core/widgets/clinic_kit.dart';
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
    final QueueToken token;
    try {
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
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, AppException.messageOf(e));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    QueueActions.printForm(ref, token, context: context);
    showSnack(context, 'Walk-in ${token.label} created. Printing the clinic form…');
    Navigator.pop(context, token);
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
    final patientOk = _newPatient ? newOk : _patientId != null;
    final ready = _phoneOk && _doctorId != null && patientOk && ref.watch(isOnlineProvider);
    final doctor = doctors.where((d) => d.id == _doctorId).firstOrNull;
    final day = doctor == null ? null : ref.watch(queueDayProvider((widget.clinicId, doctor.id)));
    final label = doctor == null || day == null ? null : '${doctor.tokenPrefix}-${day.lastTokenNumber + 1}';

    return Dialog(
      backgroundColor: ClinicColors.page,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 820, maxHeight: MediaQuery.sizeOf(context).height - 48),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('New walk-in token', style: AppText.titleLarge.copyWith(fontSize: 24))),
              IconButton(
                tooltip: 'Close (Esc)',
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(backgroundColor: AppColors.surface, side: const BorderSide(color: AppColors.border)),
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 18, runSpacing: 8, children: [
              _step(1, 'Phone', done: _phoneOk, active: true),
              _step(2, 'Patient', done: _phoneOk && patientOk, active: _phoneOk),
              _step(3, 'Doctor', done: _phoneOk && patientOk && _doctorId != null, active: _phoneOk && patientOk),
            ]),
            const SizedBox(height: 18),
            Flexible(
              child: SingleChildScrollView(
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    flex: 6,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('Phone number', style: AppText.labelMedium),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _phone,
                        autofocus: widget.phone == null,
                        keyboardType: TextInputType.phone,
                        style: AppText.labelLarge,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]')), LengthLimitingTextInputFormatter(15)],
                        decoration: InputDecoration(
                          hintText: '300 1234567',
                          prefixIcon: const Icon(Icons.phone_rounded, size: 18),
                          prefixText: '+92  ',
                          suffixIcon: _phoneOk ? const Icon(Icons.check_circle_rounded, color: AppColors.success) : null,
                        ),
                        onChanged: (_) => setState(() {
                          _patientId = null;
                          _newPatient = false;
                        }),
                      ),
                      if (_phoneOk) ...[
                        const SizedBox(height: 14),
                        Text('Profiles on this phone', style: AppText.labelMedium),
                        const SizedBox(height: 8),
                        if (profiles.isEmpty && others.isEmpty && !(lookup?.loading ?? false))
                          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('No patients on this number yet.', style: AppText.bodyMedium)),
                        for (final p in profiles) _profileTile(p),
                        if (lookup != null && lookup.loading)
                          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Checking the Asani app for this number…', style: ClinicText.small)),
                        if (lookup?.error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: NoteBox(lookup!.error!, icon: Icons.info_outline_rounded)),
                        if (others.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 6),
                            child: Text('On the Asani app, new to this clinic', style: ClinicText.small.copyWith(fontWeight: FontWeight.w700)),
                          ),
                          for (final p in others) _otherTile(p),
                        ],
                        _newPatientTile(),
                        if (_newPatient) ...[
                          const SizedBox(height: 14),
                          _newPatientForm([for (final p in profiles) p.patient.name, for (final p in others) p.name]),
                        ],
                      ],
                    ]),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 4,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('Doctor', style: AppText.labelMedium),
                      const SizedBox(height: 8),
                      for (final d in doctors) _doctorTile(d),
                      if (day != null && day.sessionStatus == SessionStatus.ended)
                        const Padding(padding: EdgeInsets.only(bottom: 8), child: NoteBox("This doctor's session has ended today.", icon: Icons.info_outline_rounded)),
                      const SizedBox(height: 4),
                      const NoteBox.tint('Walk-in tokens share the same number line as app bookings. The token starts as Arrived and the clinic form prints.'),
                    ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: ready && !_busy ? _create : null,
                  style: _busy ? FilledButton.styleFrom(disabledBackgroundColor: AppColors.primary, disabledForegroundColor: AppColors.onPrimary) : null,
                  child: BusyLabel(
                    busy: _busy,
                    busyText: 'Creating the token…',
                    child: Text(label == null ? 'Create & Print' : 'Create & Print · $label'),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _step(int number, String text, {required bool done, required bool active}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: done || active ? AppColors.primary : AppColors.cream, shape: BoxShape.circle),
          child: done
              ? const Icon(Icons.check_rounded, size: 16, color: AppColors.onPrimary)
              : Text('$number', style: AppText.labelMedium.copyWith(fontSize: 13, color: active ? AppColors.onPrimary : AppColors.textSecondary)),
        ),
        const SizedBox(width: 8),
        Text(text, style: AppText.labelMedium.copyWith(color: active ? AppColors.textPrimary : AppColors.textSecondary)),
      ]);

  /// A selectable white card with a trailing radio mark.
  Widget _choice({required bool selected, required VoidCallback onTap, required Widget leading, required String title, required String subtitle, bool radio = true}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(
          selected: selected,
          button: true,
          child: Panel(
            radius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            color: selected ? ClinicColors.tint : AppColors.surface,
            borderColor: selected ? AppColors.primary : AppColors.border,
            borderWidth: selected ? 2 : 1,
            onTap: onTap,
            child: Row(children: [
              leading,
              const SizedBox(width: 12),
              Expanded(child: TwoLine(title, subtitle)),
              if (radio)
                Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: selected ? AppColors.primary : AppColors.textMuted),
            ]),
          ),
        ),
      );

  Widget _profileTile(ClinicPatient p) {
    final selected = !_newPatient && _patientId == p.patient.id;
    final age = p.patient.age(pktNow());
    final visits = p.visitCount == 0 ? 'no visits yet' : '${p.visitCount} visits here';
    return _choice(
      selected: selected,
      onTap: () => setState(() {
        _patientId = p.patient.id;
        _newPatient = false;
      }),
      leading: selected ? Av.solid(p.patient.name) : Av(p.patient.name),
      title: p.patient.name,
      subtitle: '${p.patient.relation.label} · ${age ?? '—'} ${p.patient.gender.short} · $visits',
    );
  }

  /// D-22 profile from another clinic / the app: only name, relation, age, gender.
  Widget _otherTile(PhoneProfile p) {
    final selected = !_newPatient && _patientId == p.id;
    // D-52 (S-3): the app account's phone is not verified.
    final from = p.appAccount ? 'App account (number not verified)' : 'New to this clinic';
    return _choice(
      selected: selected,
      onTap: () => setState(() {
        _patientId = p.id;
        _newPatient = false;
      }),
      leading: selected ? Av.solid(p.name) : Av(p.name),
      title: p.name,
      subtitle: '${p.relation.label} · ${p.age ?? '—'} ${p.gender.short} · $from',
    );
  }

  Widget _newPatientTile() => Material(
        color: _newPatient ? ClinicColors.tint : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: _newPatient ? AppColors.primary : AppColors.primarySoft, width: _newPatient ? 2 : 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() {
            _newPatient = true;
            _patientId = null;
          }),
          child: SizedBox(height: 48, child: Center(child: Text('+ New patient', style: AppText.labelMedium.copyWith(color: AppColors.primary)))),
        ),
      );

  Widget _doctorTile(Doctor d) {
    final day = ref.watch(queueDayProvider((widget.clinicId, d.id)));
    final selected = d.id == _doctorId;
    final next = '${d.tokenPrefix}-${day.lastTokenNumber + 1}';
    return _choice(
      selected: selected,
      radio: false,
      onTap: () => setState(() => _doctorId = d.id),
      leading: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: selected ? AppColors.primary : ClinicColors.tint, borderRadius: BorderRadius.circular(9)),
        child: Text(d.tokenPrefix, style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w800, color: selected ? AppColors.onPrimary : AppColors.primary)),
      ),
      title: d.name,
      subtitle: day.sessionStatus == SessionStatus.notStarted ? 'Not started · next $next' : 'Next token $next',
    );
  }

  Widget _newPatientForm(List<String> existing) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: LabeledField(
              'Full name',
              child: TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'Patient name'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LabeledField(
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
            padding: EdgeInsets.only(top: 10),
            child: NoteBox('A patient with a similar name is already on this phone. Pick them above if it is the same person.'),
          ),
        const SizedBox(height: 12),
        LabeledField(
          'Gender',
          child: Wrap(spacing: 8, children: [
            for (final g in Gender.values) FilterPill(g.label, selected: _gender == g, onTap: () => setState(() => _gender = g)),
          ]),
        ),
        const SizedBox(height: 12),
        LabeledField(
          'Relation to phone owner (optional)',
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in Relation.values) FilterPill(r.label, selected: _relation == r, onTap: () => setState(() => _relation = r)),
          ]),
        ),
        const SizedBox(height: 10),
        Text("These visits don't appear in the Asani app automatically. To add them, use Patients → Link to app account.",
            style: ClinicText.small),
      ]);
}

/// Pretty "+92 300 1234567" for display in lists.
String phoneLabel(String e164) => Fmt.phone(e164);
