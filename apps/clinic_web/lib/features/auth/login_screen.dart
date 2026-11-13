import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/firebase_setup.dart';
import '../../core/errors/app_exception.dart';
import '../../core/widgets/desktop.dart';
import '../../data/demo_clinic_repository.dart';
import '../../data/providers.dart';

/// W-01 Login: email + password, forgot password (§5.3).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Release the text field first; on web the next click would otherwise
      // only blur the hidden input and get lost.
      FocusManager.instance.primaryFocus?.unfocus();
      await ref.read(repositoryProvider).signIn(_email.text, _password.text);
      // The router sends each role to its home page.
    } catch (e) {
      if (mounted) setState(() => _error = AppException.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final c = TextEditingController(text: _email.text);
    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Reset password',
        subtitle: "We'll email you a link to set a new password.",
        width: 440,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await ref.read(repositoryProvider).sendPasswordReset(c.text.trim());
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Send link'),
          ),
        ],
        child: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'Email')),
      ),
    );
    c.dispose();
    if (sent == true && mounted) showSnack(context, "If this email is registered, you'll get a link.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(children: [
        Expanded(flex: 5, child: _brandPanel()),
        Expanded(
          flex: 6,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Gap.xxl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _form,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('Log in', style: AppText.displaySmall),
                    const SizedBox(height: Gap.xs),
                    Text("Use your clinic's email. Everyone at the clinic uses this one login.", style: AppText.bodyMedium.copyWith(fontSize: 15)),
                    const SizedBox(height: Gap.xl),
                    FieldLabel(
                      'Email',
                      child: TextFormField(
                        controller: _email,
                        autofocus: true,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(hintText: 'name@clinic.com', prefixIcon: Icon(Icons.mail_outline_rounded)),
                        validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                        onFieldSubmitted: (_) => _login(),
                      ),
                    ),
                    FieldLabel(
                      'Password',
                      child: TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          hintText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Show password' : 'Hide password',
                            onPressed: () => setState(() => _obscure = !_obscure),
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                        onFieldSubmitted: (_) => _login(),
                      ),
                    ),
                    if (_error != null) ...[
                      Banner2(text: _error!, icon: Icons.error_outline_rounded, fg: AppColors.danger, bg: AppColors.dangerContainer),
                      const SizedBox(height: Gap.lg),
                    ],
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _busy ? null : _login,
                        child: _busy
                            ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary))
                            : const Text('Log in'),
                      ),
                    ),
                    const SizedBox(height: Gap.sm),
                    Align(alignment: Alignment.center, child: TextButton(onPressed: _forgot, child: const Text('Forgot password?'))),
                    const SizedBox(height: Gap.xl),
                    if (!Env.useFirebase) _demoAccounts(),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _brandPanel() => GradientHeader(
        radius: 0,
        padding: const EdgeInsets.all(Gap.xxxl),
        child: SizedBox.expand(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const AsaniLogoTile(size: 56),
              const SizedBox(width: Gap.md),
              Text('asani', style: AppText.displaySmall.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w800)),
              const SizedBox(width: Gap.sm),
              Pill(label: 'Clinic', fg: AppColors.onPrimary, bg: AppColors.onPrimary.withValues(alpha: 0.18)),
            ]),
            const Spacer(),
            Text('Run your clinic queue\nwithout the register.',
                style: AppText.displaySmall.copyWith(color: AppColors.onPrimary, fontSize: 36, height: 1.15)),
            const SizedBox(height: Gap.lg),
            Text('Check patients in by token code, add walk-ins, call the next patient and print the clinic form, live with the Asani app.',
                style: AppText.bodyLarge.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.9))),
            const SizedBox(height: Gap.xl),
            Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
              for (final f in ['Live queue', 'Check-in in seconds', 'Walk-ins', 'Follow-ups'])
                Pill(label: f, fg: AppColors.onPrimary, bg: AppColors.onPrimary.withValues(alpha: 0.16), icon: Icons.check_rounded),
            ]),
            const Spacer(),
            Text('Smart clinic token & live queue', style: AppText.labelSmall.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.75))),
          ]),
        ),
      );

  /// Demo mode only: one-click fill for the seeded test accounts.
  Widget _demoAccounts() {
    const accounts = [
      ('Super Admin', 'admin@asani.app'),
      ('Al-Shifa Clinic', 'clinic@alshifa.pk'),
      ('DHA Family Clinic', 'clinic@dhafamily.pk'),
      ('Rehman Clinic (suspended)', 'clinic@rehmanclinic.pk'),
    ];
    return AppCard(
      color: AppColors.muted,
      borderColor: AppColors.muted,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.science_outlined, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: Gap.sm),
          Text('Demo mode: pick an account', style: AppText.labelMedium),
        ]),
        const SizedBox(height: Gap.md),
        Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
          for (final (role, email) in accounts)
            ActionChip(
              label: Text(role),
              onPressed: () {
                _email.text = email;
                _password.text = DemoClinicRepository.demoPassword;
                _login();
              },
            ),
        ]),
      ]),
    );
  }
}
