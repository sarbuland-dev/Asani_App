import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/demo/demo_backend.dart';
import '../../data/providers.dart';
import 'phone_screen.dart';

/// S-03: 6-digit code, resend after 60 s (PRD F-01).
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  int _secondsLeft = 60;
  bool _verifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) t.cancel();
      if (mounted) setState(() => _secondsLeft--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String? get _phone => ref.read(authStateProvider).value?.pendingPhone;

  Future<void> _verify() async {
    if (_controller.text.length != 6 || _verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).verifyCode(_controller.text);
    } catch (e) {
      if (mounted) {
        setState(() => _error = AppException.messageOf(e));
        _controller.clear();
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    final phone = _phone;
    if (phone == null) return;
    await ref.read(authRepositoryProvider).sendCode(phone);
    if (!mounted) return;
    showSnack(context, 'A new code has been sent.');
    _startTimer();
  }

  void _changeNumber() {
    ref.read(authRepositoryProvider).cancelLogin();
    context.go('/login/phone');
  }

  @override
  Widget build(BuildContext context) {
    final phone = ref.watch(authStateProvider).value?.pendingPhone;
    final code = _controller.text;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HeaderBackButton(dark: true, onPressed: _changeNumber),
              const SizedBox(height: Gap.xl),
              const IconBox(icon: Icons.smartphone_rounded, size: 52),
              const SizedBox(height: Gap.lg),
              Text('Enter the code', style: AppText.displaySmall.copyWith(fontSize: 28)),
              const SizedBox(height: Gap.sm),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Sent to ', style: AppText.bodyMedium.copyWith(fontSize: 15)),
                  Text(phone == null ? '' : Fmt.phone(phone), style: AppText.labelMedium),
                  Text(' · ', style: AppText.bodyMedium),
                  InkWell(
                    onTap: _changeNumber,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                      child: Text('Change', style: AppText.labelMedium.copyWith(color: AppColors.primary)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.xl),
              Text('6-digit code', style: AppText.labelMedium),
              const SizedBox(height: Gap.sm),
              // One hidden field drives six boxes; supports SMS autofill.
              Stack(
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < 6; i++) ...[
                        Expanded(child: _box(i < code.length ? code[i] : '', i == code.length && _focus.hasFocus)),
                        if (i < 5) const SizedBox(width: Gap.sm),
                      ],
                    ],
                  ),
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.01,
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                        showCursor: false,
                        decoration: const InputDecoration(border: InputBorder.none, filled: false),
                        onChanged: (v) {
                          setState(() => _error = null);
                          if (v.length == 6) _verify();
                        },
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: Gap.md),
                Text(_error!, style: AppText.bodyMedium.copyWith(color: AppColors.danger)),
              ],
              const SizedBox(height: Gap.xl),
              Center(
                child: _secondsLeft > 0
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule_rounded, size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Text('Resend code in ', style: AppText.bodyMedium),
                          Text('0:${_secondsLeft.toString().padLeft(2, '0')}', style: AppText.labelMedium),
                        ],
                      )
                    : TextButton(onPressed: _resend, child: const Text('Resend code')),
              ),
              const SizedBox(height: Gap.lg),
              const DemoNote(text: 'Demo mode: the code is ${DemoBackend.demoOtp}.'),
              const Spacer(),
              FilledButton(
                onPressed: code.length == 6 && !_verifying ? _verify : null,
                child: _verifying
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onPrimary))
                    : const Text('Verify'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _box(String digit, bool active) {
    return AspectRatio(
      aspectRatio: 0.82,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: digit.isNotEmpty ? AppColors.primaryContainer.withValues(alpha: 0.5) : AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.button),
          border: Border.all(
            color: _error != null ? AppColors.danger : (active || digit.isNotEmpty ? AppColors.primary : AppColors.border),
            width: active ? 2 : 1.2,
          ),
        ),
        child: Text(digit, style: AppText.titleLarge.copyWith(fontSize: 24)),
      ),
    );
  }
}
