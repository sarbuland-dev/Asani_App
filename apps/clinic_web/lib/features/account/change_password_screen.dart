import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../core/widgets/pin_gate.dart';
import '../../data/providers.dart';

/// W-18 / C-12: the clinic has one login (D-18), so there is no staff
/// management, only Change password. Changing it signs the clinic out on
/// every other computer (useful when a receptionist leaves). A card on the
/// Settings page (board W-18/19).
class ChangePasswordCard extends ConsumerStatefulWidget {
  const ChangePasswordCard({super.key});

  @override
  ConsumerState<ChangePasswordCard> createState() => _ChangePasswordCardState();
}

class _ChangePasswordCardState extends ConsumerState<ChangePasswordCard> {
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

  Widget _password(String label, TextEditingController c, {String? help, required FormFieldValidator<String> validator, ValueChanged<String>? onSubmitted}) => Expanded(
        child: LabeledField(
          label,
          help: help,
          child: TextFormField(controller: c, obscureText: !_show, validator: validator, onFieldSubmitted: onSubmitted),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final changed = user.passwordChangedAt;

    return Panel(
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Change password', style: ClinicText.cardTitle)),
            TextButton.icon(
              onPressed: () => setState(() => _show = !_show),
              icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
              label: Text(_show ? 'Hide passwords' : 'Show passwords'),
            ),
          ]),
          const SizedBox(height: 8),
          LabeledField(
            'Clinic email (login)',
            help: 'Changed only by Asani. Everyone at this clinic uses this one login.',
            child: TextFormField(
              initialValue: user.email,
              enabled: false,
              style: AppText.bodyLarge.copyWith(color: AppColors.textSecondary),
              decoration: const InputDecoration(fillColor: ClinicColors.quiet),
            ),
          ),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _password('Current password', _current, validator: (v) => (v ?? '').isEmpty ? 'Enter your current password' : null),
            const SizedBox(width: 14),
            _password('New password', _next, help: 'At least 8 characters', validator: (v) {
              if ((v ?? '').length < 8) return 'At least 8 characters';
              if (v == _current.text) return 'Use a different password';
              return null;
            }),
            const SizedBox(width: 14),
            _password('Confirm new password', _confirm, validator: (v) => v != _next.text ? "Passwords don't match" : null, onSubmitted: (_) => _save()),
          ]),
          const SizedBox(height: 14),
          const NoteBox('Changing the password signs the clinic out on all other computers. When a receptionist leaves, change it.'),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: changed == null ? const SizedBox.shrink() : Text('Last changed ${WebFmt.ago(changed)}', style: ClinicText.small)),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('Update password')),
          ]),
        ]),
      ),
    );
  }
}
