import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/env.dart';
import '../../core/errors/app_exception.dart';
import 'package:asani_ui/asani_ui.dart';
import 'package:asani_core/asani_core.dart';
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
  static const _maxResends = 3;
  int _secondsLeft = 60;
  int _resendCount = 0;
  bool _verifying = false;
  bool _resending = false;
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
    if (phone == null || _resending || _resendCount >= _maxResends) return;
    setState(() => _resending = true);
    try {
      await ref.read(authRepositoryProvider).sendCode(phone);
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _resendCount++;
        _error = null;
      });
      showSnack(context, 'A new code has been sent.');
      _startTimer();
    } catch (e) {
      if (mounted) setState(() => _error = AppException.messageOf(e));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _changeNumber() {
    ref.read(authRepositoryProvider).cancelLogin();
    context.go('/login/phone');
  }

  @override
  Widget build(BuildContext context) {
    final phone = ref.watch(authStateProvider).value?.pendingPhone;
    final code = _controller.text;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kStatusBarLight,
      child: Scaffold(
      backgroundColor: AppColors.surface,
      body: FillScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Board P1 S-03: green header with back, "Verify number" and the number.
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Gap.xl - 4, Gap.sm, Gap.xl - 4, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          HeaderBackButton(onPressed: _changeNumber),
                          Expanded(
                            child: Text('Verify number',
                                textAlign: TextAlign.center,
                                style: AppText.labelLarge.copyWith(color: AppColors.onPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 44),
                        ]),
                        const SizedBox(height: Gap.xl + 2),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Enter the code',
                                style: AppText.headline.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                            const SizedBox(height: Gap.sm),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text('Sent to ', style: AppText.bodyLarge.copyWith(color: AppColors.onPrimaryMuted)),
                                Text(phone == null ? '' : Fmt.phone(phone),
                                    style: AppText.labelLarge.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700)),
                                Text('. ', style: AppText.bodyLarge.copyWith(color: AppColors.onPrimaryMuted)),
                                InkWell(
                                  onTap: _changeNumber,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                                    child: Text('Change',
                                        style: AppText.labelLarge.copyWith(
                                            color: AppColors.onPrimary, decoration: TextDecoration.underline, decorationColor: AppColors.onPrimary)),
                                  ),
                                ),
                              ],
                            ),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.xl, 28, Gap.xl, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                        enabled: !_verifying,
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
              const SizedBox(height: Gap.xl - 2),
              Align(
                alignment: Alignment.centerLeft,
                child: _secondsLeft > 0
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule_rounded, size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: Gap.sm),
                          Flexible(child: Text('Resend code in ', style: AppText.bodyLarge.copyWith(fontSize: 15, color: AppColors.textSecondary))),
                          Text('0:${_secondsLeft.toString().padLeft(2, '0')}', style: AppText.labelLarge.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
                        ],
                      )
                    : _resendCount >= _maxResends
                        ? Text('Resend limit reached. Please try again later.', style: AppText.bodyMedium)
                        : TextButton.icon(
                            onPressed: _resending || _verifying ? null : _resend,
                            icon: _resending ? const AsaniLoader(size: 20) : const Icon(Icons.refresh_rounded, size: 20),
                            label: const Text('Resend code'),
                          ),
              ),
              const SizedBox(height: Gap.lg),
              if (Env.isDemo) const DemoNote(text: 'Demo mode: the code is ${DemoBackend.demoOtp}.'),
                ]),
              ),
              const Spacer(),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, Gap.xl + 4),
                  child: FilledButton(
                    onPressed: code.length == 6 && !_verifying ? _verify : null,
                    child: _verifying
                        ? const ButtonSpinner()
                        : const Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('Verify'),
                            SizedBox(width: Gap.xs),
                            Icon(Icons.chevron_right_rounded),
                          ]),
                  ),
                ),
              ),
            ],
          ),
      ),
    ));
  }

  /// Board S-03: filled and empty boxes are cream; the next box is white
  /// with a green edge; red edges after a wrong code.
  Widget _box(String digit, bool active) {
    final error = _error != null;
    return SizedBox(
      height: 58,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.surface : AppColors.muted,
          borderRadius: BorderRadius.circular(14),
          border: error
              ? Border.all(color: AppColors.danger, width: 1.5)
              : (active ? Border.all(color: AppColors.primary, width: 2) : null),
        ),
        child: Text(digit, style: AppText.titleLarge.copyWith(fontSize: 24)),
      ),
    );
  }
}
