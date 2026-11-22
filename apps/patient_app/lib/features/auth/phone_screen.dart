import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/env.dart';
import '../../core/errors/app_exception.dart';
import 'package:asani_ui/asani_ui.dart';
import 'package:asani_core/asani_core.dart';
import '../../data/providers.dart';

/// S-02: phone entry (PRD F-01).
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => PhoneUtils.isValidLocal(_controller.text);

  Future<void> _send() async {
    if (!_valid || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(authRepositoryProvider).sendCode(PhoneUtils.toE164(_controller.text));
      if (mounted) context.go('/login/otp');
    } catch (e) {
      if (mounted) showSnack(context, AppException.messageOf(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kStatusBarLight,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Board P1 S-02: green header with the logo tile and the promise.
                    Container(
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, Gap.xxl),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const AsaniLogoTile(size: 56),
                              const SizedBox(height: Gap.xl),
                              Text('Welcome to Asani',
                                  style: AppText.headline.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                              const SizedBox(height: Gap.sm),
                              Text("Enter your mobile number. We'll send a 6-digit code by SMS.",
                                  style: AppText.bodyLarge.copyWith(color: AppColors.onPrimaryMuted, height: 1.5)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Gap.xl, 28, Gap.xl, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Mobile number', style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.textSecondary)),
                          const SizedBox(height: Gap.sm),
                          _PhoneField(
                            controller: _controller,
                            enabled: !_sending,
                            valid: _valid,
                            onChanged: () => setState(() {}),
                            onSubmitted: _send,
                          ),
                          if (Env.isDemo) ...[
                            const SizedBox(height: Gap.lg),
                            const _DemoNote(text: 'Demo mode: use 300 1234567 to see a sample family and visit history. Any 3XX number works.'),
                          ],
                        ],
                      ),
                    ),
                    const Spacer(),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, Gap.xl + 4),
                        child: FilledButton(
                          onPressed: _valid && !_sending ? _send : null,
                          child: _sending
                              ? const ButtonSpinner()
                              : const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Text('Send code'),
                                  SizedBox(width: Gap.xs),
                                  Icon(Icons.chevron_right_rounded),
                                ]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "+92 | 300 1234567 ✓" in one cream field with a green edge (board S-02).
class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.controller,
    required this.enabled,
    required this.valid,
    required this.onChanged,
    required this.onSubmitted,
  });
  final TextEditingController controller;
  final bool enabled;
  final bool valid;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary, width: 1.5),
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
            autofocus: true,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            style: AppText.titleMedium.copyWith(fontSize: 17, letterSpacing: 0.6),
            inputFormatters: [_PkPhoneFormatter()],
            decoration: const InputDecoration(
              hintText: '300 1234567',
              filled: false,
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (_) => onChanged(),
            onSubmitted: (_) => onSubmitted(),
          ),
        ),
        if (valid)
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

/// Formats as "3XX XXXXXXX" while typing. Typed or pasted "0300…",
/// "92300…" and "+92 300…" are cleaned to the 10 local digits.
class _PkPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = PhoneUtils.normalizeLocal(newValue.text);
    final text = PhoneUtils.formatLocal(digits);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

class _DemoNote extends StatelessWidget {
  const _DemoNote({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Gap.md),
        // Demo builds only. Cream, not blue: blue is kept for "Your turn" (D-43).
        decoration: BoxDecoration(color: AppColors.muted, borderRadius: BorderRadius.circular(Radii.button)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.primary),
            const SizedBox(width: Gap.sm),
            Expanded(child: Text(text, style: AppText.bodyMedium.copyWith(color: AppColors.textPrimary))),
          ],
        ),
      );
}

class DemoNote extends _DemoNote {
  const DemoNote({super.key, required super.text});
}
