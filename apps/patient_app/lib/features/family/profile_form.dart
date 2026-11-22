import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import 'package:asani_ui/asani_ui.dart';
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

  void _stepAge(int by) {
    final now = _ageValue ?? 0;
    if (_age.text.isEmpty && by < 0) return;
    setState(() => _age.text = '${(now + by).clamp(0, 120)}');
  }

  @override
  Widget build(BuildContext context) {
    final patients = ref.watch(myPatientsProvider).value ?? const [];
    final dup = _duplicate(patients);
    final name = _name.text.trim();
    final rel = _isSelf ? 'Self' : _relation.label;
    final details = [rel, if (_ageValue != null) '$_ageValue years', if (_gender != null) _gender!.label].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Board P6 S-14: live preview of the profile as you type.
        Semantics(
          label: 'Preview: ${name.isEmpty ? 'no name yet' : name}, $details',
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: AppColors.primaryMid, borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.cream,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.cream.withValues(alpha: 0.18), spreadRadius: 4)],
                ),
                child: name.isEmpty
                    ? const Icon(Icons.person_outline_rounded, color: AppColors.primary)
                    : Text(Fmt.initials(name), style: AppText.titleMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name.isEmpty ? 'Name' : name,
                      style: AppText.titleMedium.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(details, style: AppText.labelSmall.copyWith(color: AppColors.onPrimaryMuted, fontSize: 13)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: AppColors.cream.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(Radii.pill)),
                child: Text('Preview', style: AppText.labelSmall.copyWith(color: AppColors.onPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
        const SizedBox(height: Gap.lg),
        _label('Full name'),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          style: AppText.bodyLarge,
          decoration: const InputDecoration(
            hintText: 'e.g. Shazia Begum',
            prefixIcon: Icon(Icons.person_outline_rounded, color: AppColors.primary),
          ),
          onChanged: (_) => setState(() => _ignoreDuplicate = false),
        ),
        if (dup != null) ...[
          const SizedBox(height: Gap.sm),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
            decoration: BoxDecoration(color: AppColors.warningContainer, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text.rich(
                    TextSpan(style: AppText.labelSmall.copyWith(color: AppColors.warningText), children: [
                      const TextSpan(text: 'A profile named '),
                      TextSpan(text: dup.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const TextSpan(text: ' already exists on this number.'),
                    ]),
                  ),
                ),
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.warningText),
                  onPressed: () => setState(() => _ignoreDuplicate = true),
                  child: const Text('Add anyway'),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.warningText),
                  onPressed: () => widget.onSaved(dup),
                  child: const Text('Use existing'),
                ),
              ]),
            ]),
          ),
        ],
        if (!_isSelf) ...[
          const SizedBox(height: Gap.lg),
          _label('Relation'),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.8 / (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 1.8),
            children: [
              for (final r in _relations)
                Semantics(
                  button: true,
                  selected: _relation == r,
                  label: r.label,
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => setState(() => _relation = r),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: _relation == r ? null : Border.all(color: const Color(0xFFB9D3CA)),
                        gradient: _relation == r
                            ? const LinearGradient(colors: [AppColors.primaryMid, AppColors.primary])
                            : const LinearGradient(
                                begin: Alignment(-0.3, -1), end: Alignment(0.3, 1), colors: [Color(0xFFE8F1EE), Color(0xFFCDE2DA)]),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(_relation == r ? '✓ ${r.label}' : r.label,
                            style: AppText.labelSmall.copyWith(
                                fontWeight: FontWeight.w700, color: _relation == r ? AppColors.onPrimary : AppColors.primary)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: Gap.lg),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          SizedBox(
            width: 132,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _label('Age (years)'),
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  _stepButton(Icons.remove_rounded, 'One year less', false, () => _stepAge(-1)),
                  Expanded(
                    child: TextField(
                      controller: _age,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                      style: AppText.titleMedium.copyWith(fontWeight: FontWeight.w700),
                      decoration: const InputDecoration(
                        hintText: '–',
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  _stepButton(Icons.add_rounded, 'One year more', true, () => _stepAge(1)),
                ]),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _label('Gender'),
              Container(
                height: 48,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  for (final g in Gender.values)
                    Expanded(
                      child: Semantics(
                        selected: _gender == g,
                        button: true,
                        label: g.label,
                        excludeSemantics: true,
                        child: GestureDetector(
                          onTap: () => setState(() => _gender = g),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _gender == g ? AppColors.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(g.label,
                                  style: AppText.labelMedium.copyWith(
                                      fontSize: 13,
                                      color: _gender == g ? AppColors.onPrimary : AppColors.textSecondary,
                                      fontWeight: _gender == g ? FontWeight.w700 : FontWeight.w600)),
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
        ]),
        if (!_isSelf) ...[
          const SizedBox(height: Gap.lg),
          _label('Phone (optional, if they have their own number)'),
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _phoneOk ? AppColors.border : AppColors.danger),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.cream,
                  border: Border(right: BorderSide(color: AppColors.border)),
                ),
                child: Text('+92', style: AppText.labelLarge.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                  style: AppText.bodyLarge,
                  decoration: const InputDecoration(
                    hintText: '3XX XXXXXXX',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
          ),
          if (!_phoneOk)
            Padding(
              padding: const EdgeInsets.only(top: Gap.xs),
              child: Text('Enter 10 digits starting with 3', style: AppText.labelSmall.copyWith(color: AppColors.danger)),
            ),
        ],
        const SizedBox(height: Gap.xl),
        FilledButton(
          onPressed: _valid && !_saving ? _save : null,
          child: _saving ? const ButtonSpinner() : const Text('Save profile'),
        ),
      ],
    );
  }

  Widget _stepButton(IconData icon, String label, bool dark, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: dark ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox.square(dimension: 36, child: Icon(icon, size: 20, color: dark ? AppColors.onPrimary : AppColors.primary)),
          ),
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: Text(text, style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.textSecondary)),
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
