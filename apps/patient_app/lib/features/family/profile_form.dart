import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/providers.dart';

/// S-14 profile form (PRD F-07). Used as a full screen and in a bottom sheet.
/// Calls [onSaved] with the saved (or chosen existing) profile.
class ProfileForm extends ConsumerStatefulWidget {
  const ProfileForm({super.key, this.existing, required this.onSaved});
  final Patient? existing;
  final void Function(Patient patient) onSaved;

  @override
  ConsumerState<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<ProfileForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _age = TextEditingController(text: widget.existing?.age()?.toString() ?? '');
  late final _phone = TextEditingController(
      text: widget.existing?.patientPhone == null ? '' : PhoneUtils.formatLocal(widget.existing!.patientPhone!.substring(3)));
  late Gender? _gender = widget.existing?.gender == Gender.other && widget.existing?.birthYear == null ? null : widget.existing?.gender;
  late Relation _relation = widget.existing?.relation ?? Relation.mother;
  bool _saving = false;
  bool _ignoreDuplicate = false;

  static const _relations = [
    Relation.mother,
    Relation.father,
    Relation.spouse,
    Relation.son,
    Relation.daughter,
    Relation.brother,
    Relation.sister,
    Relation.other,
  ];

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.existing != null;
  bool get _isSelf => widget.existing?.isSelf ?? false;

  /// Duplicate warning: a close name match on the same account.
  Patient? _duplicate(List<Patient> patients) {
    if (_ignoreDuplicate) return null;
    final n = _name.text.trim().toLowerCase();
    if (n.length < 3) return null;
    for (final p in patients) {
      if (p.id == widget.existing?.id) continue;
      final o = p.nameLower;
      if (o == n || o.startsWith(n) || n.startsWith(o) || _distance(o, n) <= 2) return p;
    }
    return null;
  }

  static int _distance(String a, String b) {
    if ((a.length - b.length).abs() > 2) return 3;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = [i, ...List.filled(b.length, 0)];
      for (var j = 1; j <= b.length; j++) {
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)].reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  int? get _ageValue => int.tryParse(_age.text.trim());
  bool get _phoneOk => _phone.text.trim().isEmpty || PhoneUtils.isValidLocal(_phone.text);
  bool get _valid =>
      _name.text.trim().length >= 2 && _ageValue != null && _ageValue! <= 120 && _gender != null && _phoneOk;

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    final repo = ref.read(patientRepositoryProvider);
    final phone = _phone.text.trim().isEmpty ? null : PhoneUtils.toE164(_phone.text);
    try {
      if (_isEdit) {
        final updated = widget.existing!.copyWith(
          name: _name.text.trim(),
          gender: _gender,
          relation: _isSelf ? Relation.self : _relation,
          patientPhone: phone,
        );
        await repo.updatePatient(updated, age: _ageValue);
        widget.onSaved(updated);
      } else {
        final p = await repo.addPatient(name: _name.text, age: _ageValue, gender: _gender!, relation: _relation, patientPhone: phone);
        widget.onSaved(p);
      }
    } catch (e) {
      if (mounted) showSnack(context, AppException.messageOf(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final patients = ref.watch(myPatientsProvider).value ?? const [];
    final dup = _duplicate(patients);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('Full name'),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          style: AppText.bodyLarge,
          decoration: const InputDecoration(hintText: 'e.g. Shazia Begum'),
          onChanged: (_) => setState(() => _ignoreDuplicate = false),
        ),
        if (dup != null) ...[
          const SizedBox(height: Gap.sm),
          Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              color: AppColors.warningContainer,
              borderRadius: BorderRadius.circular(Radii.button),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text.rich(
                    TextSpan(style: AppText.bodyMedium.copyWith(color: AppColors.textPrimary), children: [
                      const TextSpan(text: 'Looks like '),
                      TextSpan(text: dup.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const TextSpan(text: ' already exists. Use that instead?'),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: Gap.sm),
              Row(children: [
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.warning, minimumSize: const Size(0, 40)),
                  onPressed: () => widget.onSaved(dup),
                  child: const Text('Use existing'),
                ),
                const SizedBox(width: Gap.sm),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.warning),
                  onPressed: () => setState(() => _ignoreDuplicate = true),
                  child: const Text('Add anyway'),
                ),
              ]),
            ]),
          ),
        ],
        const SizedBox(height: Gap.lg),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _label('Age (years)'),
              TextField(
                controller: _age,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                style: AppText.bodyLarge,
                decoration: const InputDecoration(hintText: 'e.g. 55'),
                onChanged: (_) => setState(() {}),
              ),
            ]),
          ),
          if (!_isSelf) ...[
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _label('Relation'),
                DropdownButtonFormField<Relation>(
                  initialValue: _relation,
                  isExpanded: true,
                  style: AppText.bodyLarge,
                  borderRadius: BorderRadius.circular(Radii.button),
                  items: [for (final r in _relations) DropdownMenuItem(value: r, child: Text(r.label))],
                  onChanged: (r) => setState(() => _relation = r ?? _relation),
                ),
              ]),
            ),
          ],
        ]),
        const SizedBox(height: Gap.lg),
        _label('Gender'),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: AppColors.muted, borderRadius: BorderRadius.circular(Radii.pill)),
          child: Row(children: [
            for (final g in Gender.values)
              Expanded(
                child: Semantics(
                  selected: _gender == g,
                  button: true,
                  child: GestureDetector(
                    onTap: () => setState(() => _gender = g),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _gender == g ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                      child: Text(g.label,
                          style: AppText.labelMedium.copyWith(color: _gender == g ? AppColors.onPrimary : AppColors.textSecondary)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        if (!_isSelf) ...[
          const SizedBox(height: Gap.lg),
          _label('Phone (optional)'),
          Row(children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.muted,
                borderRadius: BorderRadius.circular(Radii.button),
                border: Border.all(color: AppColors.border),
              ),
              child: Text('+92', style: AppText.labelLarge),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                style: AppText.bodyLarge,
                decoration: InputDecoration(
                  hintText: '300 1234567',
                  errorText: _phoneOk ? null : 'Enter 10 digits starting with 3',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
          const SizedBox(height: Gap.xs),
          Text('If they have their own number.', style: AppText.labelSmall),
        ],
        const SizedBox(height: Gap.xl),
        FilledButton(
          onPressed: _valid && !_saving ? _save : null,
          child: _saving
              ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onPrimary))
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: Text(text, style: AppText.labelMedium),
      );
}

/// Opens the form in a bottom sheet; returns the saved/selected profile.
Future<Patient?> showAddFamilySheet(BuildContext context) {
  return showModalBottomSheet<Patient>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: Text('Add family member', style: AppText.titleLarge)),
              IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: Gap.md),
            ProfileForm(onSaved: (p) => Navigator.pop(ctx, p)),
          ],
        ),
      ),
    ),
  );
}

/// "Mother · 55 · Female"
String patientSubtitle(Patient p, {bool shortGender = false}) => [
      p.relation.label,
      if (p.age() != null) '${p.age()}',
      if (!(p.isSelf && p.birthYear == null)) shortGender ? p.gender.short : p.gender.label,
    ].join(' · ');
