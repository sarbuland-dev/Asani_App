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

  @override
  Widget build(BuildContext context) {
    final link = AppText.bodyLarge.copyWith(
        color: AppColors.primary, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: AppColors.primary);
    final ageInvalid = _age.text.isNotEmpty && _ageValue == null;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kStatusBarDark,
      child: Scaffold(
      body: SafeArea(
        child: FillScrollView(
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                HeaderBackButton(dark: true, onPressed: _saving ? () {} : _useAnotherNumber),
                const Spacer(),
                Text('Last step', style: AppText.labelMedium.copyWith(color: AppColors.textSecondary)),
              ]),
              const SizedBox(height: Gap.xl),
              Text('Tell us about you', style: AppText.headline),
              const SizedBox(height: Gap.sm),
              Text('Clinics see this name on your token. You can add family members later.',
                  style: AppText.bodyLarge.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: Gap.xl),
              _label('Full name'),
              TextField(
                controller: _name,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                inputFormatters: [LengthLimitingTextInputFormatter(_maxName)],
                style: AppText.bodyLarge,
                decoration: const InputDecoration(hintText: 'Ali Khan'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: Gap.lg),
              // Age and gender side by side when there is room; stacked on
              // narrow phones or large text so "Female" never gets squeezed.
              Builder(builder: (context) {
                final age = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _label('Age (years)'),
                  TextField(
                    controller: _age,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                    style: AppText.bodyLarge,
                    decoration: InputDecoration(hintText: '28', errorText: ageInvalid ? 'Enter an age from 0 to 120' : null),
                    onChanged: (_) => setState(() {}),
                  ),
                ]);
                final gender = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _label('Gender'),
                  _GenderPicker(value: _gender, enabled: !_saving, onChanged: (g) => setState(() => _gender = g)),
                ]);
                // (Screen width, not LayoutBuilder: FillScrollView measures intrinsic height.)
                final width = MediaQuery.sizeOf(context).width - Gap.xl * 2;
                final roomy = width >= 340 && MediaQuery.textScalerOf(context).scale(14) <= 15.5;
                return roomy
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: age),
                        const SizedBox(width: Gap.md),
                        Expanded(flex: 2, child: gender),
                      ])
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [age, const SizedBox(height: Gap.lg), gender]);
              }),
              const SizedBox(height: Gap.lg),
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
                const SizedBox(height: Gap.sm),
                Text(_error!, style: AppText.bodyMedium.copyWith(color: AppColors.danger)),
              ],
              const Spacer(),
              const SizedBox(height: Gap.xl),
              FilledButton(
                onPressed: _valid && !_saving ? _continue : null,
                child: _saving
                    ? const ButtonSpinner()
                    : const Text('Continue'),
              ),
              const SizedBox(height: Gap.sm),
              Center(
                child: TextButton(onPressed: _saving ? null : _useAnotherNumber, child: const Text('Use another number')),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: Text(text, style: AppText.labelMedium),
      );
}

class _GenderPicker extends StatelessWidget {
  const _GenderPicker({required this.value, required this.enabled, required this.onChanged});
  final Gender? value;
  final bool enabled;
  final ValueChanged<Gender> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.muted, borderRadius: BorderRadius.circular(Radii.pill)),
      child: Row(children: [
        for (final g in Gender.values)
          Expanded(
            child: Semantics(
              selected: value == g,
              button: true,
              child: GestureDetector(
                onTap: enabled ? () => onChanged(g) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == g ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text(g.label,
                      style: AppText.labelMedium.copyWith(color: value == g ? AppColors.onPrimary : AppColors.textSecondary)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
