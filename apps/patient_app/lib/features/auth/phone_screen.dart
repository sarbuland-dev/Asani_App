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
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Green header: logo, then the promise. The sign-in card overlaps its bottom edge.
            Container(
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header)),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, Gap.xxxl + Gap.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const AsaniMark(size: 34, color: AppColors.onPrimary),
                        const SizedBox(width: Gap.xs),
                        Text('asani', style: AppText.titleLarge.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w800)),
                      ]),
                      const SizedBox(height: Gap.xxl),
                      Text('Skip the waiting room.', style: AppText.headline.copyWith(color: AppColors.onPrimary)),
                      const SizedBox(height: Gap.sm),
                      Text('Book a token, watch the queue, arrive on time.',
                          style: AppText.bodyLarge.copyWith(color: AppColors.primaryContainer)),
                    ],
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -Gap.xxxl),
              child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                  padding: const EdgeInsets.all(Gap.xl),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(Radii.card + 4),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  Text('Welcome', style: AppText.titleLarge),
                  const SizedBox(height: Gap.xs),
                  Text('Sign in with your mobile number.', style: AppText.bodyLarge.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: Gap.xl),
                  Text('Mobile number', style: AppText.labelMedium),
                  const SizedBox(height: Gap.sm),
                  Row(
                    children: [
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
                          controller: _controller,
                          enabled: !_sending,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.done,
                          autofocus: true,
                          autofillHints: const [AutofillHints.telephoneNumberNational],
                          style: AppText.titleMedium.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.5),
                          inputFormatters: [_PkPhoneFormatter()],
                          decoration: const InputDecoration(hintText: '300 1234567'),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.xl),
                  FilledButton(
                    onPressed: _valid && !_sending ? _send : null,
                    child: _sending
                        ? const ButtonSpinner()
                        : const Text('Send code'),
                  ),
                  const SizedBox(height: Gap.md),
                  Text("We'll send a 6-digit code by SMS.", textAlign: TextAlign.center, style: AppText.bodyMedium),
                  ],
                  ),
                  ),
                  const SizedBox(height: Gap.lg),
                  if (Env.isDemo)
                    const _DemoNote(text: 'Demo mode: use 300 1234567 to see a sample family and visit history. Any 3XX number works.'),
                ],
              ),
            ),
            ),
          ],
        ),
      ),
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
        decoration: BoxDecoration(color: AppColors.infoContainer, borderRadius: BorderRadius.circular(Radii.button)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.info),
            const SizedBox(width: Gap.sm),
            Expanded(child: Text(text, style: AppText.bodyMedium.copyWith(color: AppColors.infoDark))),
          ],
        ),
      );
}

class DemoNote extends _DemoNote {
  const DemoNote({super.key, required super.text});
}
