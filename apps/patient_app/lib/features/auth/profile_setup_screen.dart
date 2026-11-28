import 'package:asani_core/asani_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import 'package:asani_ui/asani_ui.dart';
import '../../core/utils/launch.dart';
import '../../data/providers.dart';
import 'phone_field.dart';

/// S-04 first login ("sign up"): name, age, gender, phone + consent (PRD F-01, D-15, D-52).
/// The phone is required but not verified; one phone = one app account (`phone-taken`).
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
  final _phone = TextEditingController();
  Gender? _gender;
  bool _agreed = false;
  bool _saving = false;
  String? _error;
  String? _phoneError;
  late final _termsTap = TapGestureRecognizer()..onTap = () => openUrl(context, AppLinks.terms);
  late final _privacyTap = TapGestureRecognizer()..onTap = () => openUrl(context, AppLinks.privacy);

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _phone.dispose();
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
      _cleanName.length >= 2 &&
      _cleanName.length <= _maxName &&
      _ageValue != null &&
      _gender != null &&
      PhoneUtils.isValidLocal(_phone.text) &&
      _agreed;

  Future<void> _continue() async {
    if (!_valid || _saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
      _phoneError = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .createProfile(name: _cleanName, age: _ageValue!, gender: _gender!, phone: _phone.text);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'phone-taken' || e.code == 'invalid-phone') {
          _phoneError = e.message;
        } else {
          _error = e.message;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = AppException.messageOf(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _useAnotherEmail() => ref.read(authRepositoryProvider).signOut();

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
                      offset: const Offset(0, -54),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _SlipPreview(name: _cleanName, age: _ageValue, gender: _gender),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
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
                          // Board: one box, minus on cream, the age, plus on green.
                          Container(
                            height: 56,
                            padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(Radii.card),
                              border: Border.all(color: ageInvalid ? AppColors.danger : AppColors.border),
                            ),
                            child: Row(children: [
                              _RoundStep(icon: Icons.remove_rounded, label: 'One year less', onTap: _saving ? null : () => _stepAge(-1)),
                              Expanded(
                                child: TextField(
                                  controller: _age,
                                  enabled: !_saving,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                                  style: AppText.titleMedium.copyWith(fontWeight: FontWeight.w700),
                                  decoration: const InputDecoration(
                                    hintText: '28',
                                    suffixText: 'years',
                                    filled: false,
                                    isDense: true,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              _RoundStep(icon: Icons.add_rounded, label: 'One year more', dark: true, onTap: _saving ? null : () => _stepAge(1)),
                            ]),
                          ),
                          if (ageInvalid)
                            Padding(
                              padding: const EdgeInsets.only(top: Gap.xs, left: Gap.xs),
                              child: Text('Enter an age from 0 to 120', style: AppText.labelSmall.copyWith(color: AppColors.danger)),
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
                              if (g != Gender.values.last) const SizedBox(width: 10),
                            ],
                          ]),
                          const SizedBox(height: Gap.lg),
                          _label('Mobile number'),
                          PkPhoneField(
                            controller: _phone,
                            enabled: !_saving,
                            error: _phoneError != null,
                            onChanged: () => setState(() => _phoneError = null),
                          ),
                          if (_phoneError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: Gap.xs, left: Gap.xs),
                              child: Text(_phoneError!, style: AppText.labelSmall.copyWith(color: AppColors.danger)),
                            ),
                          const SizedBox(height: Gap.sm),
                          const PhoneNote(),
                          const SizedBox(height: Gap.lg),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Consent and Continue stay on screen; the form scrolls above them.
            Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
              child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, Gap.xs, 20, Gap.xs),
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
                      child: _saving
                          ? const ButtonSpinner()
                          : const Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('Continue'),
                              SizedBox(width: Gap.xs),
                              Icon(Icons.chevron_right_rounded),
                            ]),
                    ),
                    const SizedBox(height: Gap.sm),
                  ],
                ),
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }

  /// Board P2 S-04: back, "Your profile", and the last-step line.
  Widget _header() => Container(
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 70),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  HeaderBackButton(onPressed: _saving ? () {} : _useAnotherEmail),
                  Expanded(
                    child: Text('Your profile',
                        textAlign: TextAlign.center,
                        style: AppText.labelLarge.copyWith(color: AppColors.onPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 44),
                ]),
                const SizedBox(height: Gap.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('Last step · this is how clinics will see you.',
                      style: AppText.bodyMedium.copyWith(color: AppColors.onPrimaryMuted)),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: Text(text, style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.textSecondary)),
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
      label: 'Profile preview: ${name.isEmpty ? 'no name yet' : name}, $details',
      excludeSemantics: true,
      // Board P2 S-04: cream card with the green initials circle.
      child: Container(
        padding: const EdgeInsets.all(Gap.lg),
        decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Container(
              key: ValueKey(name.isEmpty ? '' : Fmt.initials(name)),
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: name.isEmpty ? AppColors.border : AppColors.primary, shape: BoxShape.circle),
              child: name.isEmpty
                  ? const Icon(Icons.person_outline_rounded, color: AppColors.textSecondary)
                  : Text(Fmt.initials(name),
                      style: AppText.titleMedium.copyWith(color: AppColors.onPrimary, fontSize: 19, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                name.isEmpty ? 'Your name' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.titleMedium.copyWith(
                    fontWeight: FontWeight.w700, color: name.isEmpty ? AppColors.textSecondary : AppColors.textPrimary),
              ),
              Text(details, style: AppText.labelSmall.copyWith(fontSize: 13)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Minus / plus inside the age box (board: 40 dp squares; the whole box is 56 high).
class _RoundStep extends StatelessWidget {
  const _RoundStep({required this.icon, required this.label, required this.onTap, this.dark = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: dark ? AppColors.primary : AppColors.cream,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox.square(dimension: 40, child: Icon(icon, color: dark ? AppColors.onPrimary : AppColors.primary)),
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
    // Board P2 S-04: selected = solid green with cream text; others cream.
    final fg = selected ? AppColors.onPrimary : AppColors.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: gender.label,
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.primary : AppColors.cream,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 56,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(_icon, color: fg, size: 20),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(gender.label, maxLines: 1, style: AppText.labelMedium.copyWith(color: fg, fontSize: 15)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
