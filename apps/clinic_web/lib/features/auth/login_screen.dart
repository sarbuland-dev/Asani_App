import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/errors/app_exception.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/demo_clinic_repository.dart';
import '../../data/providers.dart';
import 'login_art.dart';

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
      builder: (ctx) => ClinicThemed(
        child: AppDialog(
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
      ),
    );
    c.dispose();
    if (sent == true && mounted) showSnack(context, "If this email is registered, you'll get a link.");
  }

  /// Below this width only the card is shown.
  static const _wide = 1180.0;

  @override
  Widget build(BuildContext context) => ClinicThemed(
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: LayoutBuilder(builder: (context, c) {
            if (c.maxWidth < _wide) {
              return Stack(children: [
                const Positioned(left: 0, right: 0, top: 0, height: 320, child: DecoratedBox(decoration: BoxDecoration(gradient: ClinicColors.heroGradient))),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 470), child: _card()),
                  ),
                ),
              ]);
            }
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: Stack(children: [
                  const Positioned(left: 0, right: 0, top: 0, height: 470, child: HeroBlock(radius: 0, padding: EdgeInsets.zero, child: SizedBox.expand())),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(80, 44, 80, 32),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(
                            height: 466,
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(child: _copy()),
                              if (c.maxWidth >= 1360) const Padding(padding: EdgeInsets.only(top: 16), child: LoginArt()),
                            ]),
                          ),
                          _features(),
                        ]),
                      ),
                      const SizedBox(width: 40),
                      SizedBox(width: 440, child: _card()),
                    ]),
                  ),
                ]),
              ),
            );
          }),
        ),
      );

  Widget _copy() => Padding(
        padding: const EdgeInsets.only(top: 20, right: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const AsaniMark(size: 76, color: AppColors.cream),
          Row(children: [
            Text('asani', style: AppText.displaySmall.copyWith(fontSize: 34, fontWeight: FontWeight.w800, color: AppColors.onPrimary)),
            const SizedBox(width: 10),
            const CChip('for clinics', fg: AppColors.onPrimaryMuted, bg: AppColors.primaryMid),
          ]),
          const SizedBox(height: 28),
          Text.rich(
            const TextSpan(text: 'Run your queue calmly.\n', children: [TextSpan(text: 'Patients wait at home.', style: TextStyle(color: AppColors.primarySoft))]),
            style: AppText.displaySmall.copyWith(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.onPrimary, height: 1.2),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Text('App bookings and walk-ins in one list. Press Next, and Asani tells the right patients when their turn is near.',
                style: AppText.bodyLarge.copyWith(fontSize: 15, color: AppColors.onPrimaryMuted, height: 1.6)),
          ),
        ]),
      );

  Widget _card() => Container(
        padding: const EdgeInsets.fromLTRB(40, 36, 40, 30),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [BoxShadow(color: AppColors.primaryDeep.withValues(alpha: 0.22), blurRadius: 60, offset: const Offset(0, 26))],
        ),
        child: Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text.rich(
              const TextSpan(text: 'Welcome to ', children: [TextSpan(text: 'asani', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800))]),
              style: AppText.titleMedium.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text('Log in', style: AppText.displayLarge.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Text('Use the clinic email and password you set from the invite email.', style: AppText.bodyMedium),
            const SizedBox(height: 22),
            LabeledField(
              'Clinic email',
              child: TextFormField(
                controller: _email,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(hintText: 'name@clinic.com', prefixIcon: Icon(Icons.mail_outline_rounded, color: AppColors.primary, size: 20)),
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                onFieldSubmitted: (_) => _login(),
              ),
            ),
            const SizedBox(height: 16),
            LabeledField(
              'Password',
              child: TextFormField(
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  hintText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary, size: 20),
                  suffixIcon: TextButton(onPressed: () => setState(() => _obscure = !_obscure), child: Text(_obscure ? 'Show' : 'Hide')),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                onFieldSubmitted: (_) => _login(),
              ),
            ),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _forgot, child: const Text('Forgot password?'))),
            const SizedBox(height: 10),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _busy ? null : _login,
                style: FilledButton.styleFrom(
                  textStyle: AppText.labelLarge.copyWith(fontWeight: FontWeight.w700),
                  disabledBackgroundColor: AppColors.primary,
                  disabledForegroundColor: AppColors.onPrimary,
                ),
                child: BusyLabel(busy: _busy, busyText: 'Logging in…', child: const Text('Log in')),
              ),
            ),
            if (_error != null) ...[const SizedBox(height: 14), NoteBox.error(_error!, icon: Icons.error_outline_rounded)],
            const SizedBox(height: 18),
            const Divider(color: AppColors.cream),
            const SizedBox(height: 14),
            Text('New clinic? The Asani team sets up your clinic and sends the invite email.\nStays logged in on this browser until you log out.',
                style: AppText.bodyMedium.copyWith(fontSize: 13)),
            if (!Env.useSupabase) ...[const SizedBox(height: 14), _demoAccounts()],
          ]),
        ),
      );

  Widget _features() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, children: [
          Text('What you can do here', style: ClinicText.cardTitle),
          Text('Everything the reception needs, on one screen.', style: AppText.bodyMedium.copyWith(fontSize: 13)),
        ]),
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _feature('1', 'Queue board', 'Press Next. Patients get told when their turn is near.', Icons.confirmation_number_outlined),
            const SizedBox(width: 16),
            _feature('2', 'Check in by code', 'Type A-11 and see the same slip the patient has.', Icons.how_to_reg_outlined),
            const SizedBox(width: 16),
            _feature('3', 'Follow-ups', 'Patients get a reminder the day before and on the day.', Icons.event_repeat_rounded, lime: true),
          ]),
        ),
      ]);

  Widget _feature(String number, String title, String text, IconData icon, {bool lime = false}) => Expanded(
        child: Panel(
          padding: EdgeInsets.zero,
          radius: ClinicRadii.hero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 100,
              color: lime ? ClinicColors.limeTint : (number == '1' ? AppColors.navy : AppColors.cream),
              child: Icon(icon, size: 40, color: lime ? ClinicColors.limeText : (number == '1' ? AppColors.cream : AppColors.primary)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: lime ? ClinicColors.lime : AppColors.primary, borderRadius: BorderRadius.circular(7)),
                    child: Text(number,
                        style: AppText.labelSmall.copyWith(fontSize: 11, fontWeight: FontWeight.w800, color: lime ? ClinicColors.limeInk : AppColors.onPrimary)),
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: Text(title, style: AppText.titleSmall.copyWith(fontWeight: FontWeight.w800))),
                ]),
                const SizedBox(height: 6),
                Text(text, style: AppText.bodyMedium.copyWith(fontSize: 13)),
              ]),
            ),
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
