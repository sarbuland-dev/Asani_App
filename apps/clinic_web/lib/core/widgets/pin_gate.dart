import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../errors/app_exception.dart';
import 'clinic_kit.dart';

/// Manager PIN (PRD D-41, board W-23).
/// Protected: Billing, Export, Add / Deactivate doctor, Change password.
/// Never: queue work, leave, timings. A correct PIN unlocks for 15 minutes,
/// except Billing, which asks on every visit (D-54).
DateTime? _unlockedUntil;

/// The server locks the PIN for 15 minutes after 5 wrong tries. It does not
/// tell the UI the end time, so the countdown starts when this browser first
/// hears of the lock. The server stays in charge of the lock itself.
const _lockTime = Duration(minutes: 15);
final _lockedUntil = <String, DateTime>{}; // clinicId -> end of the countdown

Duration _lockLeft(String clinicId) {
  final left = _lockedUntil[clinicId]?.difference(DateTime.now()) ?? Duration.zero;
  return left.isNegative ? Duration.zero : left;
}

void _rememberLock(String clinicId) {
  if (_lockLeft(clinicId) == Duration.zero) _lockedUntil[clinicId] = DateTime.now().add(_lockTime);
}

bool _pinSet(WidgetRef ref, String clinicId) => ref.read(repositoryProvider).clinicLogin(clinicId)?.pinSet ?? false;

/// True when the action may go ahead: no PIN set yet, still unlocked, or the
/// manager typed the right PIN now. [always] asks even while still unlocked.
Future<bool> requireManagerPin(BuildContext context, WidgetRef ref, String clinicId, {bool always = false}) async {
  if (!_pinSet(ref, clinicId)) return true;
  if (!always && _unlockedUntil != null && DateTime.now().isBefore(_unlockedUntil!)) return true;
  final ok = await showDialog<bool>(context: context, builder: (_) => _PinDialog(clinicId: clinicId)) ?? false;
  if (ok) _unlockedUntil = DateTime.now().add(const Duration(minutes: 15));
  return ok;
}

/// Four boxes for the PIN. A transparent text field on top takes the typing.
class PinBoxes extends StatefulWidget {
  const PinBoxes({
    super.key,
    required this.controller,
    required this.label,
    this.focusNode,
    this.autofocus = false,
    this.error = false,
    this.centered = true,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool error;
  final bool centered;
  final VoidCallback? onChanged;
  final VoidCallback? onSubmitted;

  @override
  State<PinBoxes> createState() => _PinBoxesState();
}

class _PinBoxesState extends State<PinBoxes> {
  late final _focus = widget.focusNode ?? FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_refresh);
    widget.controller.removeListener(_refresh);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final length = widget.controller.text.length;
    Widget box(int i) {
      final filled = i < length;
      final cursor = _focus.hasFocus && i == length;
      final line = widget.error ? AppColors.danger : (filled || cursor ? AppColors.primary : AppColors.border);
      return Container(
        width: 50,
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.error ? AppColors.dangerContainer : (filled || cursor ? AppColors.surface : AppColors.background),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: line, width: cursor ? 2 : 1.5),
          boxShadow: cursor ? const [BoxShadow(color: ClinicColors.tint, spreadRadius: 4)] : null,
        ),
        child: filled || widget.error ? Text('•', style: ClinicText.big(28, color: widget.error ? AppColors.danger : AppColors.primary)) : null,
      );
    }

    final boxes = Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < 4; i++) ...[if (i > 0) const SizedBox(width: 10), box(i)],
    ]);

    return Align(
      alignment: widget.centered ? Alignment.center : Alignment.centerLeft,
      child: Stack(children: [
        boxes,
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            alwaysIncludeSemantics: true,
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              expands: true,
              maxLines: null,
              showCursor: false,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              decoration: InputDecoration(labelText: widget.label),
              onChanged: (_) => widget.onChanged?.call(),
              onSubmitted: (_) => widget.onSubmitted?.call(),
            ),
          ),
        ),
      ]),
    );
  }
}

class _PinDialog extends ConsumerStatefulWidget {
  const _PinDialog({required this.clinicId});
  final String clinicId;

  @override
  ConsumerState<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends ConsumerState<_PinDialog> {
  final _pin = TextEditingController();
  final _focus = FocusNode();
  String? _error;
  bool _locked = false;
  bool _busy = false;
  bool _showBusy = false;
  Timer? _busyTimer;
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    // Reopened while locked: straight to the countdown.
    if (_lockLeft(widget.clinicId) > Duration.zero) _showLocked();
  }

  void _showLocked() {
    _locked = true;
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_lockLeft(widget.clinicId) == Duration.zero) {
          // Time is up: the PIN can be typed again.
          timer.cancel();
          _locked = false;
          _error = null;
        }
      });
    });
  }

  /// After a wrong PIN: clear the red boxes and start typing again.
  void _tryAgain() {
    _pin.clear();
    setState(() => _error = null);
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _busyTimer?.cancel();
    _pin.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_busy) return;
    if (_pin.text.length != 4) {
      _focus.requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    _busyTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _showBusy = true);
    });
    try {
      await ref.read(repositoryProvider).verifyPin(_pin.text);
      if (mounted) Navigator.pop(context, true);
    } on AppException catch (e) {
      if (!mounted) return;
      _pin.clear();
      setState(() {
        _error = e.message;
        if (e.code == 'pin-locked') {
          _rememberLock(widget.clinicId);
          _showLocked();
        }
      });
      if (!_locked) _focus.requestFocus();
    } catch (e) {
      if (!mounted) return;
      _pin.clear();
      setState(() => _error = AppException.messageOf(e));
    } finally {
      _busyTimer?.cancel();
      if (mounted) {
        setState(() {
          _busy = false;
          _showBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bad = _error != null;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 350),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: _locked
                  ? _LockCountdown(left: _lockLeft(widget.clinicId))
                  : IconTile(Icons.lock_outline_rounded,
                      size: 52, bg: bad ? AppColors.dangerContainer : ClinicColors.tint, fg: bad ? AppColors.danger : AppColors.primary),
            ),
            const SizedBox(height: 12),
            Text(_locked ? 'PIN locked' : 'Manager PIN', textAlign: TextAlign.center, style: AppText.titleMedium.copyWith(fontWeight: FontWeight.w700)),
            if (_locked) ...[
              const SizedBox(height: 12),
              const NoteBox.error('Too many wrong PINs. Try again in 15 minutes.'),
              const SizedBox(height: 10),
              Text('Forgot the PIN? Ask Asani to reset it from the admin panel.', textAlign: TextAlign.center, style: ClinicText.small),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
            ] else ...[
              const SizedBox(height: 4),
              Text('This page is for the manager. Enter the 4-digit PIN.', textAlign: TextAlign.center, style: AppText.bodyMedium.copyWith(fontSize: 13)),
              const SizedBox(height: 16),
              PinBoxes(
                controller: _pin,
                focusNode: _focus,
                label: 'PIN',
                autofocus: true,
                error: bad && _pin.text.isEmpty,
                onChanged: () => setState(() => _error = null),
                onSubmitted: _check,
              ),
              if (bad) ...[const SizedBox(height: 12), NoteBox.error(_error!)],
              const SizedBox(height: 14),
              SizedBox(
                height: 46,
                child: FilledButton(
                  onPressed: _busy ? null : (bad && _pin.text.isEmpty ? _tryAgain : _check),
                  style: FilledButton.styleFrom(disabledBackgroundColor: AppColors.primary, disabledForegroundColor: AppColors.onPrimary),
                  child: BusyLabel(busy: _showBusy, busyText: 'Checking PIN…', child: Text(bad ? 'Try again' : 'Unlock')),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// W-23 "PIN locked": a red ring that empties over the 15 minutes, with the
/// time left in the middle.
class _LockCountdown extends StatelessWidget {
  const _LockCountdown({required this.left});
  final Duration left;

  @override
  Widget build(BuildContext context) {
    final seconds = (left.inMilliseconds / 1000).ceil();
    final text = '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Semantics(
      label: '$text minutes left',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: 92,
          child: Stack(fit: StackFit.expand, children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: CircularProgressIndicator(
                value: (seconds / _lockTime.inSeconds).clamp(0.0, 1.0),
                strokeWidth: 8,
                strokeCap: StrokeCap.round,
                color: AppColors.danger,
                backgroundColor: AppColors.dangerContainer,
              ),
            ),
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(text, style: ClinicText.big(20, color: AppColors.danger)),
              Text('min left', style: ClinicText.small.copyWith(fontSize: 10, color: AppColors.dangerText)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Wraps a whole page (Billing). It asks for the PIN on every visit, and asks
/// to create one first when the clinic has none (D-54).
class PinGuard extends ConsumerStatefulWidget {
  const PinGuard({super.key, required this.clinicId, required this.child, this.title = 'Billing'});
  final String clinicId;
  final Widget child;
  final String title;

  @override
  ConsumerState<PinGuard> createState() => _PinGuardState();
}

class _PinGuardState extends ConsumerState<PinGuard> {
  final _new = TextEditingController();
  final _repeat = TextEditingController();
  bool _open = false;
  bool _asked = false;

  /// Keeps the create form on screen while the new PIN is being saved.
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _new.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final ok = await requireManagerPin(context, ref, widget.clinicId, always: true);
    if (ok && mounted) setState(() => _open = true);
  }

  Future<void> _create() async {
    if (_creating) return;
    if (_new.text.length != 4) {
      setState(() => _error = 'The PIN must be 4 digits.');
      return;
    }
    if (_repeat.text != _new.text) {
      setState(() => _error = 'The two PINs are not the same.');
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      await ref.read(repositoryProvider).setPin(_new.text);
      if (mounted) setState(() => _open = true);
    } catch (e) {
      if (mounted) setState(() => _error = AppException.messageOf(e));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentUserProvider); // rebuild when the login (pinSet) changes
    ref.watch(repoTickProvider);
    if (_open) return widget.child;
    final login = ref.read(repositoryProvider).clinicLogin(widget.clinicId);
    // Not loaded yet: never show the page, or the create form, on a guess.
    if (login == null) return const Center(child: AsaniLoader());
    if (!login.pinSet || _creating) return _createForm();

    // Coming to the page opens the PIN dialog; if it is closed the page stays covered.
    if (!_asked) {
      _asked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _unlock();
      });
    }
    return _cover('This page needs the manager PIN.', [FilledButton(onPressed: _unlock, child: const Text('Enter PIN'))]);
  }

  Widget _createForm() => _cover('Create a manager PIN to open this page.', [
        SizedBox(
          width: 260,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            LabeledField('New PIN', child: PinBoxes(controller: _new, label: 'New PIN', autofocus: true)),
            const SizedBox(height: 12),
            LabeledField('Type it again', child: PinBoxes(controller: _repeat, label: 'Repeat PIN', onSubmitted: _create)),
            if (_error != null) ...[const SizedBox(height: 12), NoteBox.error(_error!)],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _creating ? null : _create,
              child: BusyLabel(busy: _creating, busyText: 'Saving…', color: AppColors.textSecondary, child: const Text('Create PIN and open')),
            ),
            const SizedBox(height: 10),
            Text(
              'The same PIN protects Export, Add / Deactivate doctor and Change password. If it is forgotten, only Asani can reset it.',
              textAlign: TextAlign.center,
              style: ClinicText.small,
            ),
          ]),
        ),
      ]);

  Widget _cover(String message, List<Widget> children) {
    Widget circle(double size, Color color, [Widget? child]) =>
        Container(width: size, height: size, alignment: Alignment.center, decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: child);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          circle(
            96,
            ClinicColors.tint,
            circle(68, AppColors.onPrimaryMuted, circle(40, AppColors.primary, const Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.onPrimary))),
          ),
          const SizedBox(height: 12),
          Text(widget.title, style: AppText.titleMedium.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(message, style: AppText.bodyMedium),
          const SizedBox(height: 14),
          ...children,
        ]),
      ),
    );
  }
}

/// Set / change the PIN (Settings page).
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
  bool _ok = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  void _show(String message, {required bool ok}) {
    if (!mounted) return;
    setState(() {
      _msg = message;
      _ok = ok;
    });
  }

  Future<void> _save(bool has) async {
    if (!RegExp(r'^\d{4}$').hasMatch(_next.text)) {
      _show('The new PIN must be 4 digits.', ok: false);
      return;
    }
    try {
      await ref.read(repositoryProvider).setPin(_next.text, currentPin: has ? _current.text : null);
      _unlockedUntil = DateTime.now().add(const Duration(minutes: 15));
      _current.clear();
      _next.clear();
      _show(has ? 'PIN changed.' : 'PIN set.', ok: true);
    } on AppException catch (e) {
      if (e.code == 'pin-locked') _rememberLock(widget.clinicId);
      _show(e.message, ok: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentUserProvider);
    final has = _pinSet(ref, widget.clinicId);
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const IconTile(Icons.lock_outline_rounded, size: 38),
          const SizedBox(width: 10),
          Expanded(child: Text('Manager PIN', style: ClinicText.cardTitle)),
          has ? const CChip.green('Set', dot: false) : const CChip.amber('Not set', dot: false),
        ]),
        const SizedBox(height: 12),
        Text(
          has
              ? 'Protects Billing, Export, Add / Deactivate doctor and Change password. Billing asks every time; the others stay unlocked for 15 minutes. Forgot it? Ask Asani to reset it.'
              : 'Set a 4-digit PIN so the reception cannot open Billing, Export, Add / Deactivate doctor or Change password.',
          style: AppText.bodyMedium.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 14),
        if (has) ...[
          LabeledField('Current PIN', child: PinBoxes(controller: _current, label: 'Current PIN', centered: false)),
          const SizedBox(height: 12),
        ],
        LabeledField('New PIN', child: PinBoxes(controller: _next, label: 'New PIN', centered: false, onSubmitted: () => _save(has))),
        const SizedBox(height: 14),
        FilledButton(onPressed: () => _save(has), child: Text(has ? 'Change PIN' : 'Set PIN')),
        if (_msg != null) ...[
          const SizedBox(height: 10),
          _ok ? NoteBox.tint(_msg!) : NoteBox.error(_msg!),
        ],
        const SizedBox(height: 10),
        Text('The PIN is stored scrambled (hashed). Nobody at Asani can read it.', style: ClinicText.small),
      ]),
    );
  }
}
