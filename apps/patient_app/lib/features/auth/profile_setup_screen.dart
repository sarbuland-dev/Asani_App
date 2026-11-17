import 'package:asani_core/asani_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import 'package:asani_ui/asani_ui.dart';
import '../../core/utils/launch.dart';
import '../../data/providers.dart';

/// S-04 first login ("sign up"): name, age, gender + consent (PRD F-01, D-15).
/// Creates the account and the "Self" patient profile; the router then
/// moves to Home.
///
/// Design "A · Live slip preview": a token-slip card at the top fills in as
/// the user types, so they see exactly how clinics will see them.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  static const _maxName = 60;

  final _name = TextEditingController();
  final _age = TextEditingController();
  Gender? _gender;
  bool _agreed = false;
  bool _saving = false;
  String? _error;
  late final _termsTap = TapGestureRecognizer()..onTap = () => openUrl(context, AppLinks.terms);
  late final _privacyTap = TapGestureRecognizer()..onTap = () => openUrl(context, AppLinks.privacy);

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  String get _cleanName => _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');

  int? get _ageValue {
    final a = int.tryParse(_age.text.trim());
    return (a == null || a < 0 || a > 120) ? null : a;
  }

  bool get _valid =>
      _cleanName.length >= 2 && _cleanName.length <= _maxName && _ageValue != null && _gender != null && _agreed;

  Future<void> _continue() async {
    if (!_valid || _saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).completeProfile(name: _cleanName, age: _ageValue!, gender: _gender!);
    } catch (e) {
      if (mounted) setState(() => _error = AppException.messageOf(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _useAnotherNumber() => ref.read(authRepositoryProvider).signOut();

  /// − / + next to the age field. Empty counts as 0, so + gives 1.
  void _stepAge(int by) {
    if (_age.text.isEmpty && by < 0) return;
    final now = int.tryParse(_age.text.trim()) ?? 0;
    setState(() => _age.text = '${(now + by).clamp(0, 120)}');
  }

  @override
  Widget build(BuildContext context) {
    final link = AppText.bodyLarge.copyWith(
        color: AppColors.primary, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: AppColors.primary);
    final ageInvalid = _age.text.isNotEmpty && _ageValue == null;

    return StatusBarScrim(
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    // The slip preview overlaps the header's bottom edge.
                    Transform.translate(
                      offset: const Offset(0, -Gap.xxxl - Gap.sm),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                        child: _SlipPreview(name: _cleanName, age: _ageValue, gender: _gender),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _label('Full name'),
                          TextField(
                            controller: _name,
                            enabled: !_saving,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                            inputFormatters: [LengthLimitingTextInputFormatter(_maxName)],
                            style: AppText.bodyLarge,
                            decoration: const InputDecoration(
                              hintText: 'Ali Khan',
                              prefixIcon: Icon(Icons.person_outline_rounded, color: AppColors.primary),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: Gap.lg),
                          _label('Age'),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _RoundStep(icon: Icons.remove_rounded, label: 'One year less', onTap: _saving ? null : () => _stepAge(-1)),
                              const SizedBox(width: Gap.sm),
                              Expanded(
                                child: TextField(
                                  controller: _age,
                                  enabled: !_saving,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                                  style: AppText.titleMedium,
                                  decoration: InputDecoration(
                                    hintText: '28',
                                    suffixText: 'years',
                                    errorText: ageInvalid ? 'Enter an age from 0 to 120' : null,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: Gap.sm),
                              _RoundStep(icon: Icons.add_rounded, label: 'One year more', onTap: _saving ? null : () => _stepAge(1)),
                            ],
                          ),
                          const SizedBox(height: Gap.lg),
                          _label('Gender'),
                          Row(children: [
                            for (final g in Gender.values) ...[
                              Expanded(
                                child: _GenderTile(
                                  gender: g,
                                  selected: _gender == g,
                                  onTap: _saving ? null : () => setState(() => _gender = g),
                                ),
                              ),
                              if (g != Gender.values.last) const SizedBox(width: Gap.sm),
                            ],
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Consent and Continue stay on screen; the form scrolls above them.
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xs, Gap.xl, Gap.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The whole row is the tap target (48 dp+); the box lines up with the fields' left edge.
                    InkWell(
                      onTap: _saving ? null : () => setState(() => _agreed = !_agreed),
                      borderRadius: BorderRadius.circular(Radii.button),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: Gap.md),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _agreed,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              onChanged: _saving ? null : (v) => setState(() => _agreed = v ?? false),
                            ),
                            const SizedBox(width: Gap.sm),
                            Expanded(
                              child: Text.rich(TextSpan(style: AppText.bodyLarge, children: [
                                const TextSpan(text: 'I agree to the '),
                                TextSpan(text: 'Terms', style: link, recognizer: _termsTap),
                                const TextSpan(text: ' and '),
                                TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacyTap),
                              ])),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      Text(_error!, style: AppText.bodyMedium.copyWith(color: AppColors.danger)),
                      const SizedBox(height: Gap.sm),
                    ],
                    FilledButton(
                      onPressed: _valid && !_saving ? _continue : null,
                      child: _saving ? const ButtonSpinner() : const Text('Continue'),
                    ),
                    Center(
                      child: TextButton(onPressed: _saving ? null : _useAnotherNumber, child: const Text('Use another number')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Container(
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.xxxl + Gap.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  HeaderBackButton(onPressed: _saving ? () {} : _useAnotherNumber),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs + 2),
                    decoration: BoxDecoration(color: AppColors.headerChip, borderRadius: BorderRadius.circular(Radii.pill)),
                    child: Text('Last step', style: AppText.labelMedium.copyWith(color: AppColors.onPrimary)),
                  ),
                ]),
                const SizedBox(height: Gap.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Tell us about you', style: AppText.headline.copyWith(color: AppColors.onPrimary)),
                    const SizedBox(height: Gap.xs),
                    Text('This is how clinics will see you.', style: AppText.bodyLarge.copyWith(color: AppColors.primaryContainer)),
                  ]),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: Text(text, style: AppText.labelMedium),
      );
}

/// Live preview of how the user appears on their token slip.
class _SlipPreview extends StatelessWidget {
  const _SlipPreview({required this.name, required this.age, required this.gender});
  final String name;
  final int? age;
  final Gender? gender;

  @override
  Widget build(BuildContext context) {
    final details = ['Self', age == null ? 'Age' : '$age', gender?.label ?? 'Gender'].join(' · ');
    return Semantics(
      label: 'Token slip preview: ${name.isEmpty ? 'no name yet' : name}, $details',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.card + 4),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.sm),
              child: Row(children: [
                const Icon(Icons.confirmation_number_outlined, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: Gap.xs),
                Expanded(child: Text('Your token slip', style: AppText.labelSmall)),
                Text('Preview', style: AppText.labelSmall),
              ]),
            ),
            const DashedLine(),
            Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Row(children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: name.isEmpty
                      ? Container(
                          key: const ValueKey('empty'),
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(color: AppColors.muted, shape: BoxShape.circle),
                          child: const Icon(Icons.person_outline_rounded, color: AppColors.textSecondary),
                        )
                      : InitialsAvatar(key: ValueKey(Fmt.initials(name)), name: name, size: 48),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      name.isEmpty ? 'Your name' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.titleMedium.copyWith(color: name.isEmpty ? AppColors.textSecondary : AppColors.textPrimary),
                    ),
                    Text(details, style: AppText.bodyMedium),
                  ]),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round − / + button next to the age field (56 dp, above the 48 dp minimum).
class _RoundStep extends StatelessWidget {
  const _RoundStep({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Material(
          color: AppColors.surface,
          shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(dimension: 56, child: Icon(icon, color: AppColors.primary)),
          ),
        ),
      );
}

/// Big tappable gender tile: icon + label; selected = green outline and fill.
class _GenderTile extends StatelessWidget {
  const _GenderTile({required this.gender, required this.selected, required this.onTap});
  final Gender gender;
  final bool selected;
  final VoidCallback? onTap;

  IconData get _icon => switch (gender) {
        Gender.male => Icons.male_rounded,
        Gender.female => Icons.female_rounded,
        _ => Icons.person_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.primary : AppColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: gender.label,
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.muted : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.6 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.card),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.md),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(_icon, color: fg, size: 26),
              const SizedBox(height: Gap.xs),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(gender.label, maxLines: 1, style: AppText.labelMedium.copyWith(color: fg)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
