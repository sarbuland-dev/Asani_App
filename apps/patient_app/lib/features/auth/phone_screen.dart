import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
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
      backgroundColor: AppColors.surface,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GradientHeader(
              radius: 36,
              padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xxxl, Gap.xl, Gap.xxxl),
              child: Column(
                children: [
                  const AsaniLogoTile(size: 84),
                  const SizedBox(height: Gap.md),
                  Text('asani',
                      style: AppText.displaySmall.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w800)),
                  const SizedBox(height: Gap.lg),
                  Text('Book your clinic token without the long wait.',
                      textAlign: TextAlign.center,
                      style: AppText.titleMedium.copyWith(color: AppColors.onPrimary)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Gap.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Welcome', style: AppText.titleLarge),
                  const SizedBox(height: Gap.xs),
                  Text('Sign in with your mobile number.', style: AppText.bodyMedium.copyWith(fontSize: 15)),
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
                          keyboardType: TextInputType.phone,
                          autofocus: false,
                          autofillHints: const [AutofillHints.telephoneNumberNational],
                          style: AppText.bodyLarge.copyWith(fontSize: 18, letterSpacing: 0.5),
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10), _PkPhoneFormatter()],
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
                        ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onPrimary))
                        : const Text('Send code'),
                  ),
                  const SizedBox(height: Gap.md),
                  Text("We'll send a 6-digit code by SMS.", textAlign: TextAlign.center, style: AppText.bodyMedium),
                  const SizedBox(height: Gap.xl),
                  const _DemoNote(text: 'Demo mode: use 300 1234567 to see a sample family and visit history. Any 3XX number works.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formats as "3XX XXXXXXX" while typing.
class _PkPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = PhoneUtils.digits(newValue.text);
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
            Expanded(child: Text(text, style: AppText.bodyMedium.copyWith(color: AppColors.infoDark, fontSize: 13))),
          ],
        ),
      );
}

class DemoNote extends _DemoNote {
  const DemoNote({super.key, required super.text});
}
