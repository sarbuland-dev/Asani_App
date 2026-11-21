import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../errors/app_exception.dart';

/// Manager PIN (PRD D-41). Plain placeholder UI.
/// Protected: Billing, Export, Add / Deactivate doctor, Change password.
/// Never: queue work, leave, timings. A correct PIN unlocks for 15 minutes.
DateTime? _unlockedUntil;

bool _pinSet(WidgetRef ref, String clinicId) => ref.read(repositoryProvider).clinicLogin(clinicId)?.pinSet ?? false;

/// True when the action may go ahead: no PIN set yet, still unlocked, or the
/// manager typed the right PIN now.
Future<bool> requireManagerPin(BuildContext context, WidgetRef ref, String clinicId) async {
  if (!_pinSet(ref, clinicId)) return true;
  if (_unlockedUntil != null && DateTime.now().isBefore(_unlockedUntil!)) return true;
  final ok = await showDialog<bool>(context: context, builder: (_) => const _PinDialog()) ?? false;
  if (ok) _unlockedUntil = DateTime.now().add(const Duration(minutes: 15));
  return ok;
}

class _PinDialog extends ConsumerStatefulWidget {
  const _PinDialog();

  @override
  ConsumerState<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends ConsumerState<_PinDialog> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repositoryProvider).verifyPin(_pin.text);
      if (mounted) Navigator.pop(context, true);
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manager PIN'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('This page is for the manager. Enter the 4-digit PIN.'),
        TextField(
          controller: _pin,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          decoration: InputDecoration(labelText: 'PIN', errorText: _error),
          onSubmitted: (_) => _check(),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _check, child: const Text('Unlock')),
      ],
    );
  }
}

/// Wraps a whole page (Billing): shows an Unlock button until the PIN is entered.
class PinGuard extends ConsumerStatefulWidget {
  const PinGuard({super.key, required this.clinicId, required this.child});
  final String clinicId;
  final Widget child;

  @override
  ConsumerState<PinGuard> createState() => _PinGuardState();
}

class _PinGuardState extends ConsumerState<PinGuard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    ref.watch(currentUserProvider); // rebuild when the login (pinSet) changes
    final free = !_pinSet(ref, widget.clinicId) || (_unlockedUntil != null && DateTime.now().isBefore(_unlockedUntil!));
    if (_open || free) return widget.child;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('This page needs the manager PIN.'),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async {
            final ok = await requireManagerPin(context, ref, widget.clinicId);
            if (ok && mounted) setState(() => _open = true);
          },
          child: const Text('Enter PIN'),
        ),
      ]),
    );
  }
}

/// Set / change the PIN (Change password page).
class ManagerPinCard extends ConsumerStatefulWidget {
  const ManagerPinCard({super.key, required this.clinicId});
  final String clinicId;

  @override
  ConsumerState<ManagerPinCard> createState() => _ManagerPinCardState();
}

class _ManagerPinCardState extends ConsumerState<ManagerPinCard> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  String? _msg;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _save(bool has) async {
    if (!RegExp(r'^\d{4}$').hasMatch(_next.text)) {
      setState(() => _msg = 'The new PIN must be 4 digits.');
      return;
    }
    try {
      await ref.read(repositoryProvider).setPin(_next.text, currentPin: has ? _current.text : null);
      _unlockedUntil = DateTime.now().add(const Duration(minutes: 15));
      _current.clear();
      _next.clear();
      setState(() => _msg = has ? 'PIN changed.' : 'PIN set.');
    } on AppException catch (e) {
      setState(() => _msg = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentUserProvider);
    final has = _pinSet(ref, widget.clinicId);
    final digits = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Manager PIN', style: Theme.of(context).textTheme.titleMedium),
          Text(has
              ? 'Protects Billing, Export, Add / Deactivate doctor and Change password. Forgot it? Ask Asani to reset it.'
              : 'Not set. Set a 4-digit PIN so the reception cannot open Billing, Export, Add / Deactivate doctor or Change password.'),
          if (has)
            TextField(controller: _current, obscureText: true, inputFormatters: digits, decoration: const InputDecoration(labelText: 'Current PIN')),
          TextField(controller: _next, obscureText: true, inputFormatters: digits, decoration: const InputDecoration(labelText: 'New PIN')),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton(onPressed: () => _save(has), child: Text(has ? 'Change PIN' : 'Set PIN')),
            const SizedBox(width: 12),
            if (_msg != null) Expanded(child: Text(_msg!)),
          ]),
        ]),
      ),
    );
  }
}
