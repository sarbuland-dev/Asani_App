import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/providers.dart';

/// D-52 (PRD-CLINIC-WEB §5.2): opened from the "Set your Asani password" invite email or a password-reset email.
/// The link already signed this browser in; the clinic chooses its password here, then lands on its home page.
/// Styled like the other clinic screens.
class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'The password needs at least 8 characters.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'The two passwords are not the same.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repositoryProvider).setNewPassword(_password.text);
      // The router moves on once needsNewPassword is false.
    } catch (e) {
      if (mounted) setState(() => _error = AppException.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    return ClinicThemed(
      child: Scaffold(
        backgroundColor: ClinicColors.page,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Panel(
                radius: ClinicRadii.dialog,
                padding: const EdgeInsets.all(Gap.xl),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  const Center(child: AsaniLogoTile(size: 64)),
                  const SizedBox(height: Gap.lg),
                  Text('Set your Asani password', style: AppText.titleLarge),
                  const SizedBox(height: Gap.sm),
                  Text(user?.email ?? '', style: AppText.bodyMedium.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: Gap.xl),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'New password (at least 8 characters)',
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: Gap.md),
                  TextField(
                    controller: _confirm,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(labelText: 'Type it again'),
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _save(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Gap.md),
                    Text(_error!, style: AppText.bodyMedium.copyWith(color: AppColors.danger)),
                  ],
                  const SizedBox(height: Gap.xl),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: BusyLabel(busy: _busy, busyText: 'Saving…', color: AppColors.textSecondary, child: const Text('Save password')),
                  ),
                  TextButton(onPressed: _busy ? null : () => ref.read(repositoryProvider).signOut(), child: const Text('Cancel and log out')),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
