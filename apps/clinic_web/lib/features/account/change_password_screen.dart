import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/desktop.dart';
import '../../data/providers.dart';
import '../../core/widgets/pin_gate.dart';

/// W-18 / C-12: the clinic has one login (D-18), so there is no staff
/// management, only Change password. Changing it signs the clinic out on
/// every other computer (useful when a receptionist leaves).
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _show = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final clinicId = ref.read(currentUserProvider)?.clinicId;
    if (clinicId != null && (!await requireManagerPin(context, ref, clinicId) || !mounted)) return; // D-41
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref.read(repositoryProvider).changePassword(_current.text, _next.text),
      success: 'Password changed. Other computers are signed out.',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _current.clear();
      _next.clear();
      _confirm.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider)!;
    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(
            tooltip: _show ? 'Hide passwords' : 'Show passwords',
            onPressed: () => setState(() => _show = !_show),
            icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          ),
        );

    return PageScaffold(
      title: 'Change password',
      subtitle: 'Everyone at this clinic uses this one login.',
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 3,
          child: AppCard(
            padding: const EdgeInsets.all(Gap.xl),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FieldLabel(
                  'Clinic email (changed only by Asani)',
                  child: TextFormField(
                    initialValue: user.email,
                    enabled: false,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.mail_outline_rounded), suffixIcon: Icon(Icons.lock_outline_rounded)),
                  ),
                ),
                FieldLabel(
                  'Current password',
                  child: TextFormField(
                    controller: _current,
                    obscureText: !_show,
                    decoration: deco('Current password'),
                    validator: (v) => (v ?? '').isEmpty ? 'Enter your current password' : null,
                  ),
                ),
                FieldLabel(
                  'New password',
                  child: TextFormField(
                    controller: _next,
                    obscureText: !_show,
                    decoration: deco('At least 8 characters'),
                    validator: (v) {
                      if ((v ?? '').length < 8) return 'At least 8 characters';
                      if (v == _current.text) return 'Use a different password';
                      return null;
                    },
                  ),
                ),
                FieldLabel(
                  'Confirm new password',
                  child: TextFormField(
                    controller: _confirm,
                    obscureText: !_show,
                    decoration: deco('Type it again'),
                    validator: (v) => v != _next.text ? "Passwords don't match" : null,
                    onFieldSubmitted: (_) => _save(),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.check_rounded), label: const Text('Change password')),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: Gap.xl),
        Expanded(
          flex: 2,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // D-41: set / change the manager PIN.
            if (ref.watch(currentUserProvider)?.clinicId case final id?) ManagerPinCard(clinicId: id),
            const Banner2(
              icon: Icons.devices_rounded,
              fg: AppColors.info,
              bg: AppColors.infoContainer,
              text: 'After a change, every other computer using this login is signed out and needs the new password.',
            ),
            const SizedBox(height: Gap.md),
            const Banner2(
              icon: Icons.badge_outlined,
              text: 'When a receptionist leaves, change the password so they can no longer log in.',
            ),
            const SizedBox(height: Gap.md),
            if (user.passwordChangedAt != null)
              Text('Last changed ${WebFmt.ago(user.passwordChangedAt!)}', style: AppText.labelSmall),
          ]),
        ),
      ]),
    );
  }
}
