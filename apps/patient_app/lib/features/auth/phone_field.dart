import 'package:asani_core/asani_core.dart';
import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// "+92 | 300 1234567 ✓" in one cream field with a green edge (board S-02). Used by profile setup
/// and Account → Phone (D-52: the phone is required but not verified). Red edge when [error].
class PkPhoneField extends StatelessWidget {
  const PkPhoneField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.error = false,
  });
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback? onSubmitted;
  final bool autofocus;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final valid = PhoneUtils.isValidLocal(controller.text);
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: error ? AppColors.danger : AppColors.primary, width: 1.5),
      ),
      child: Row(children: [
        Text('+92', style: AppText.labelLarge.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(width: Gap.md),
        Container(width: 1, height: 24, color: AppColors.border),
        const SizedBox(width: Gap.md),
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autofocus: autofocus,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            style: AppText.titleMedium.copyWith(fontSize: 17, letterSpacing: 0.6),
            inputFormatters: [PkPhoneFormatter()],
            decoration: const InputDecoration(
              hintText: '3XX XXXXXXX',
              filled: false,
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (_) => onChanged(),
            onSubmitted: (_) => onSubmitted?.call(),
          ),
        ),
        if (valid && !error)
          Semantics(
            label: 'Number looks right',
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, size: 15, color: AppColors.onPrimary),
            ),
          ),
      ]),
    );
  }
}

/// Amber info note under the phone field (profile setup and Account → Mobile number, D-52).
class PhoneNote extends StatelessWidget {
  const PhoneNote({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(color: AppColors.warningContainer, borderRadius: BorderRadius.circular(Radii.button)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.warningText),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              'Please enter your correct mobile number. Your clinic uses it to find your visits and contact you.',
              style: AppText.bodyMedium.copyWith(color: AppColors.warningText, height: 1.4),
            ),
          ),
        ]),
      );
}

/// Formats as "3XX XXXXXXX" while typing. Typed or pasted "0300…", "92300…" and "+92 300…" are
/// cleaned to the 10 local digits.
class PkPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = PhoneUtils.normalizeLocal(newValue.text);
    final text = PhoneUtils.formatLocal(digits);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
