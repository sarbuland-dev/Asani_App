import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/env.dart';
import '../../core/errors/app_exception.dart';
import 'package:asani_ui/asani_ui.dart';
import 'package:asani_core/asani_core.dart';
import '../../data/providers.dart';

/// S-02: "Continue with email" (PRD F-01, D-52). A 6-digit code is emailed; no password, no link.
class EmailScreen extends ConsumerStatefulWidget {
  const EmailScreen({super.key});

  @override
  ConsumerState<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends ConsumerState<EmailScreen> {
  final _controller = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => EmailUtils.isValid(_controller.text);

  Future<void> _send() async {
    if (!_valid || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendEmailOtp(_controller.text);
      if (mounted) context.go('/login/otp');
    } catch (e) {
      if (mounted) setState(() => _error = AppException.messageOf(e));
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
                              Text("Enter your email. We'll send you a 6-digit code.",
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
                          Text('Email', style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.textSecondary)),
                          const SizedBox(height: Gap.sm),
                          TextField(
                            controller: _controller,
                            enabled: !_sending,
                            autofocus: true,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.done,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: const [AutofillHints.email],
                            style: AppText.titleMedium.copyWith(fontSize: 17),
                            decoration: InputDecoration(
                              hintText: 'name@example.com',
                              prefixIcon: const Icon(Icons.mail_outline_rounded, color: AppColors.primary),
                              errorText: _error,
                            ),
                            onChanged: (_) => setState(() => _error = null),
                            onSubmitted: (_) => _send(),
                          ),
                          if (Env.isDemo) ...[
                            const SizedBox(height: Gap.lg),
                            const DemoNote(text: 'Demo mode: any email works and the code is 123456. Use phone 300 1234567 in your profile to see a sample family.'),
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
                                  Flexible(child: Text('Continue with email', overflow: TextOverflow.ellipsis)),
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

/// Demo builds only. Cream, not blue: blue is kept for "Your turn" (D-43).
class DemoNote extends StatelessWidget {
  const DemoNote({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Gap.md),
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
