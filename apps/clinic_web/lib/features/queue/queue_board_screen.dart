import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/net/connectivity.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/desktop.dart';
import '../../data/clinic_repository.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../doctors/doctors_screen.dart';
import 'check_in_dialog.dart';
import 'queue_actions.dart';
import 'token_panel.dart';
import 'walk_in_dialog.dart';

enum _NotArrivedChoice { skip, callAnyway }

enum _Filter {
  all('All'),
  arrived('Arrived only'),
  app('App bookings'),
  walkIn('Walk-ins');

  const _Filter(this.label);
  final String label;
}

/// W-10 / C-01: the main screen. Doctor tabs, Now serving, Next, session
/// controls, waiting list, token panel. Keyboard: `/` check-in, `W` walk-in,
/// `N` next (selected doctor), `Esc` closes dialogs.
class QueueBoardScreen extends ConsumerStatefulWidget {
  const QueueBoardScreen(this.clinicId, {super.key, this.readOnly = false});
  final String clinicId;

  /// Super admin "View queue" (A-03): look, don't touch.
  final bool readOnly;

  @override
  ConsumerState<QueueBoardScreen> createState() => _QueueBoardScreenState();
}

class _QueueBoardScreenState extends ConsumerState<QueueBoardScreen> {
  final _focus = FocusNode(debugLabel: 'queue-board');
  String? _doctorId;
  String? _selectedTokenId;
  _Filter _filter = _Filter.all;
  bool _showDone = false;
  bool _nextBusy = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _focus.dispose();
    super.dispose();
  }

  UserAccount get _user => ref.read(currentUserProvider)!;

  bool get _writable {
    final c = ref.read(clinicProvider(widget.clinicId));
    return !widget.readOnly && c != null && c.status.acceptsBookings;
  }

  /// Shortcuts only when focus is on the board itself (not a text field
  /// and not a dialog).
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isAltPressed || HardwareKeyboard.instance.isMetaPressed) return false;
    final primary = FocusManager.instance.primaryFocus;
    if (primary?.context?.findAncestorStateOfType<EditableTextState>() != null) return false;
    final onBoard = _focus.hasFocus || primary == null || primary == FocusManager.instance.rootScope;
    if (!onBoard || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final key = e.logicalKey;
    final role = _user.role;
    if ((key == LogicalKeyboardKey.slash || key == LogicalKeyboardKey.numpadDivide) && role.canRunQueue && !widget.readOnly) {
      _openCheckIn();
      return true;
    }
    if (key == LogicalKeyboardKey.keyW && role.canRunQueue && _writable) {
      _openWalkIn();
      return true;
    }
    if (key == LogicalKeyboardKey.keyN && role.canRunQueue && _writable && _doctorId != null) {
      _next(_doctorId!);
      return true;
    }
    return false;
  }

  Future<void> _openCheckIn() async {
    await showCheckInDialog(context, widget.clinicId);
    _focus.requestFocus();
  }

  Future<void> _openWalkIn() async {
    final t = await showWalkInDialog(context, widget.clinicId, doctorId: _doctorId);
    if (t != null && mounted) setState(() => _selectedTokenId = t.id);
    _focus.requestFocus();
  }

  Future<void> _next(String doctorId, {String? callNotArrived}) async {
    if (_nextBusy) return;
    if (!ref.read(isOnlineProvider)) {
      showSnack(context, AppException.offline.message);
      return;
    }
    setState(() => _nextBusy = true);
    final repo = ref.read(repositoryProvider);
    NotArrived? notArrived;
    try {
      final called = await repo.next(widget.clinicId, doctorId, callNotArrived: callNotArrived);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 30),
          content: Text(called == null ? 'Visit completed. No more patients waiting.' : 'Now serving ${called.label}, ${called.name}.'),
          action: SnackBarAction(label: 'Undo', onPressed: () => runAction(context, () => repo.undoNext(doctorId), success: 'Last Next undone.')),
        ));
    } on NotArrived catch (e) {
      notArrived = e;
    } catch (e) {
      if (mounted) showSnack(context, AppException.messageOf(e));
    } finally {
      if (mounted) setState(() => _nextBusy = false);
    }
    if (notArrived != null && mounted) await _askNotArrived(doctorId, notArrived);
  }

  /// D-24: Next reached a token that has not arrived.
  Future<void> _askNotArrived(String doctorId, NotArrived t) async {
    final choice = await showDialog<_NotArrivedChoice>(
      context: context,
      builder: (ctx) => AppDialog(
        title: '${t.label} has not arrived',
        width: 440,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, _NotArrivedChoice.skip), child: const Text('Skip')),
          FilledButton(onPressed: () => Navigator.pop(ctx, _NotArrivedChoice.callAnyway), child: const Text('Call anyway')),
        ],
        child: Text(
          '${t.name.isEmpty ? 'This patient' : t.name} has not checked in yet. '
          'Skip calls the next patient; if they come later, check them in and they are called right after the current patient.',
          style: AppText.bodyMedium,
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final repo = ref.read(repositoryProvider);
    switch (choice) {
      case _NotArrivedChoice.skip:
        final ok = await runAction(context, () => repo.tokenAction(t.tokenId, TokenAction.skip));
        if (ok && mounted) await _next(doctorId); // may ask again for the next one
      case _NotArrivedChoice.callAnyway:
        await _next(doctorId, callNotArrived: t.tokenId);
    }
  }

  Future<void> _session(Doctor d, SessionAction a, List<QueueToken> list) async {
    if (a == SessionAction.end) {
      final booked = list.where((t) => t.status == TokenStatus.booked).length;
      final ok = await confirmDialog(
        context,
        title: "End ${d.name}'s session?",
        message: booked == 0 ? 'Patients will see "Session ended".' : '$booked token${booked == 1 ? '' : 's'} will be marked No-show.',
        confirmLabel: 'End session',
        danger: true,
      );
      if (!ok) return;
    }
    if (!mounted) return;
    await runAction(context, () => ref.read(repositoryProvider).session(widget.clinicId, d.id, a),
        success: switch (a) {
          SessionAction.start => 'Session started. Patients see "Running".',
          SessionAction.pause => 'Session paused. Patients see "Queue is paused".',
          SessionAction.end => 'Session ended.',
        });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider)!;
    final clinic = ref.watch(clinicProvider(widget.clinicId));
    final doctors = ref.watch(doctorsProvider(widget.clinicId));
    final all = ref.watch(todayTokensProvider(widget.clinicId));
    if (clinic == null) return const Center(child: Text('Clinic not found.'));
    if (doctors.isEmpty) {
      return Center(
        // C-11 first-time setup: the clinic adds its own doctors (D-19).
        child: EmptyState(
          icon: Icons.medical_services_outlined,
          title: user.role.canManageDoctors ? 'Add your first doctor' : 'No doctors yet',
          message: user.role.canManageDoctors
              ? 'Add each doctor with a letter, weekly timings and max tokens. Then patients can book and the queue starts here.'
              : 'This clinic has not added any doctors yet.',
          actionLabel: user.role.canManageDoctors ? 'Add doctor' : null,
          onAction: user.role.canManageDoctors ? () => addDoctor(context, ref, widget.clinicId) : null,
        ),
      );
    }
    if (_doctorId == null || !doctors.any((d) => d.id == _doctorId)) _doctorId = doctors.first.id;
    final doctor = doctors.firstWhere((d) => d.id == _doctorId);
    final list = all.where((t) => t.token.doctorId == doctor.id).toList()..sort((a, b) => a.number.compareTo(b.number));
    final readOnly = widget.readOnly || !clinic.status.acceptsBookings;

    return Focus(
      focusNode: _focus,
      autofocus: true,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _focus.requestFocus(),
        // The token panel slides over the list, so the board keeps its width.
        child: Stack(children: [
          Positioned.fill(
            child: ListView(padding: const EdgeInsets.fromLTRB(Gap.xxl, Gap.xl, Gap.xxl, Gap.xxl), children: [
              _toolbar(user, clinic, readOnly),
              const SizedBox(height: Gap.lg),
              if (doctors.length > 1 || widget.readOnly) ...[_doctorTabs(doctors, all), const SizedBox(height: Gap.lg)],
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 320, child: _leftColumn(doctor, list, user, readOnly)),
                const SizedBox(width: Gap.xl),
                Expanded(child: _waitingList(doctor, list, user, readOnly)),
              ]),
            ]),
          ),
          if (_selectedTokenId != null)
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              child: Material(
                elevation: 12,
                shadowColor: AppColors.textPrimary.withValues(alpha: 0.3),
                child: TokenPanel(tokenId: _selectedTokenId!, readOnly: readOnly, onClose: () => setState(() => _selectedTokenId = null)),
              ),
            ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- toolbar

  Widget _toolbar(UserAccount user, ClinicAccount clinic, bool readOnly) {
    return Row(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Queue Board', style: AppText.displaySmall.copyWith(fontSize: 26)),
        Text(widget.readOnly ? '${clinic.clinic.name} · read-only view' : 'Live: updates on patients\' phones within seconds', style: AppText.bodyMedium),
      ]),
      const SizedBox(width: Gap.xl),
      if (user.role.canRunQueue && !widget.readOnly)
        Expanded(
          child: Tooltip(
            message: 'Shortcut: /',
            child: Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.button), side: const BorderSide(color: AppColors.primary, width: 1.4)),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.button),
                onTap: _openCheckIn,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 14),
                  child: Row(children: [
                    const Icon(Icons.confirmation_number_outlined, color: AppColors.primary),
                    const SizedBox(width: Gap.md),
                    Expanded(child: Text('Enter token code to check in…', style: AppText.bodyLarge.copyWith(color: AppColors.textMuted))),
                    const _Kbd('/'),
                  ]),
                ),
              ),
            ),
          ),
        )
      else
        const Spacer(),
      if (user.role.canRunQueue && !widget.readOnly) ...[
        const SizedBox(width: Gap.md),
        Tooltip(
          message: 'Shortcut: W',
          child: FilledButton.icon(
            onPressed: readOnly ? null : _openWalkIn,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Walk-in'),
          ),
        ),
      ],
    ]);
  }

  Widget _doctorTabs(List<Doctor> doctors, List<QueueToken> all) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: doctors.length,
        separatorBuilder: (_, _) => const SizedBox(width: Gap.md),
        itemBuilder: (context, i) {
          final d = doctors[i];
          final day = ref.watch(queueDayProvider((widget.clinicId, d.id)));
          final waiting = all.where((t) => t.token.doctorId == d.id && t.status.isWaiting).length;
          final selected = d.id == _doctorId;
          final onLeave = d.onLeave(pktNow());
          return SizedBox(
            width: 280,
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
              color: selected ? AppColors.primaryContainer.withValues(alpha: 0.55) : AppColors.surface,
              borderColor: selected ? AppColors.primary : AppColors.border,
              onTap: () => setState(() {
                _doctorId = d.id;
                _selectedTokenId = null;
              }),
              child: Row(children: [
                LetterBadge(d.tokenPrefix, size: 40),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(d.name, style: AppText.labelLarge, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(children: [
                      if (onLeave)
                        const Pill(label: 'On leave', fg: AppColors.danger, bg: AppColors.dangerContainer, dot: true)
                      else
                        SessionPill(day.sessionStatus),
                      const SizedBox(width: Gap.sm),
                      Text('$waiting waiting', style: AppText.labelSmall),
                    ]),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------- left column

  Widget _leftColumn(Doctor d, List<QueueToken> list, UserAccount user, bool readOnly) {
    final day = ref.watch(queueDayProvider((widget.clinicId, d.id)));
    final called = list.where((t) => t.status == TokenStatus.called).firstOrNull;
    final schedule = d.scheduleOn(pktNow());
    final online = ref.watch(isOnlineProvider);
    final canAct = !readOnly && online;
    final canUndo = ref.watch(repositoryProvider).canUndoNext(d.id);
    if (canUndo) ref.watch(secondTickerProvider); // re-check the 30 s window
    final completed = list.where((t) => t.status == TokenStatus.completed).toList();
    final waits = completed.map((t) => t.waitMinutes).whereType<int>().toList();
    final avg = waits.isEmpty ? null : waits.reduce((a, b) => a + b) / waits.length;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(Radii.card),
        child: GradientHeader(
          radius: 0,
          gradient: called != null ? AppColors.headerGradient : const LinearGradient(colors: [AppColors.navy, AppColors.primary]),
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              LetterBadge(d.tokenPrefix, inverted: true),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.name, style: AppText.labelLarge.copyWith(color: AppColors.onPrimary), overflow: TextOverflow.ellipsis),
                  Text(schedule == null ? 'Not scheduled today' : '${d.speciality} · ${Fmt.timeRange(schedule)}',
                      style: AppText.labelSmall.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.85)), overflow: TextOverflow.ellipsis),
                ]),
              ),
              SessionPill(day.sessionStatus),
            ]),
            const SizedBox(height: Gap.xl),
            Text('NOW SERVING', style: AppText.overline.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.8))),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(called?.label ?? '—', key: ValueKey(called?.label), style: AppText.tokenDisplay.copyWith(color: AppColors.onPrimary, fontSize: 80)),
            ),
            Text(called?.token.patientSnapshot.name ?? (day.sessionStatus == SessionStatus.running ? 'Press Next to call a patient' : 'No one called yet'),
                style: AppText.titleMedium.copyWith(color: AppColors.onPrimary)),
            const SizedBox(height: Gap.xl),
            if (user.role.canRunQueue)
              SizedBox(
                width: double.infinity,
                height: 60,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.onPrimary,
                    foregroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.onPrimary.withValues(alpha: 0.35),
                    disabledForegroundColor: AppColors.onPrimary,
                    textStyle: AppText.titleMedium.copyWith(fontWeight: FontWeight.w800),
                  ),
                  onPressed: canAct && day.sessionStatus == SessionStatus.running && !_nextBusy ? () => _next(d.id) : null,
                  icon: const Icon(Icons.skip_next_rounded, size: 28),
                  label: const Text('Next  (N)'),
                ),
              ),
            if (canUndo && !readOnly)
              Center(
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.onPrimary),
                  onPressed: () => runAction(context, () => ref.read(repositoryProvider).undoNext(d.id), success: 'Last Next undone.'),
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text('Undo last Next'),
                ),
              ),
          ]),
        ),
      ),
      if (user.role.canRunQueue && !widget.readOnly) ...[
        const SizedBox(height: Gap.md),
        _sessionControls(d, day, list, canAct),
      ],
      if (called != null && user.role.canRunQueue && !readOnly) ...[
        const SizedBox(height: Gap.sm),
        OutlinedButton.icon(
          onPressed: () => showFollowUpDialog(context, ref, called),
          icon: const Icon(Icons.event_repeat_rounded, size: 18),
          label: Text('Set follow-up for ${called.label}'),
        ),
      ],
      const SizedBox(height: Gap.md),
      Row(children: [
        Expanded(child: StatTile(label: 'Waiting', value: '${list.where((t) => t.status.isWaiting).length}', big: false)),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: StatTile(label: 'Arrived', value: '${list.where((t) => t.status == TokenStatus.arrived).length}', big: false, bg: AppColors.successContainer, fg: AppColors.success),
        ),
      ]),
      const SizedBox(height: Gap.sm),
      Row(children: [
        Expanded(child: StatTile(label: 'Completed', value: '${completed.length}', big: false, bg: AppColors.infoContainer, fg: AppColors.info)),
        const SizedBox(width: Gap.sm),
        Expanded(child: StatTile(label: 'Avg wait', value: WebFmt.minutes(avg), big: false, bg: AppColors.muted, fg: AppColors.textPrimary)),
      ]),
      const SizedBox(height: Gap.md),
      Text('Patients get "3, 2, 1 ahead" and "Your turn" alerts automatically.', style: AppText.labelSmall, textAlign: TextAlign.center),
    ]);
  }

  Widget _sessionControls(Doctor d, QueueDay day, List<QueueToken> list, bool canAct) {
    final s = day.sessionStatus;
    return AppCard(
      padding: const EdgeInsets.all(Gap.md),
      child: Row(children: [
        Text('Session', style: AppText.labelMedium),
        const Spacer(),
        if (s == SessionStatus.notStarted || s == SessionStatus.paused)
          FilledButton.icon(
            onPressed: canAct ? () => _session(d, SessionAction.start, list) : null,
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: Text(s == SessionStatus.paused ? 'Resume' : 'Start'),
          ),
        if (s == SessionStatus.running)
          OutlinedButton.icon(
            onPressed: canAct ? () => _session(d, SessionAction.pause, list) : null,
            icon: const Icon(Icons.pause_rounded, size: 20),
            label: const Text('Pause'),
          ),
        if (s == SessionStatus.running || s == SessionStatus.paused) ...[
          const SizedBox(width: Gap.sm),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
            onPressed: canAct ? () => _session(d, SessionAction.end, list) : null,
            icon: const Icon(Icons.stop_rounded, size: 20),
            label: const Text('End'),
          ),
        ],
        if (s == SessionStatus.ended) Text('Ended for today', style: AppText.bodyMedium),
      ]),
    );
  }

  // --------------------------------------------------------- waiting list

  Widget _waitingList(Doctor d, List<QueueToken> list, UserAccount user, bool readOnly) {
    bool done(QueueToken t) => t.status == TokenStatus.completed || t.status == TokenStatus.cancelled || t.status == TokenStatus.noShow;
    final active = list.where((t) => !done(t)).toList()
      ..sort((a, b) {
        // Called first, then in queue order.
        if (a.status == TokenStatus.called) return -1;
        if (b.status == TokenStatus.called) return 1;
        return a.number.compareTo(b.number);
      });
    final finished = list.where(done).toList()..sort((a, b) => b.number.compareTo(a.number));
    var shown = _showDone ? finished : active;
    shown = shown.where((t) => switch (_filter) {
          _Filter.all => true,
          _Filter.arrived => t.status == TokenStatus.arrived,
          _Filter.app => t.source == TokenSource.app,
          _Filter.walkIn => t.source == TokenSource.walkIn,
        }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        _segment('Waiting (${active.length})', !_showDone, () => setState(() => _showDone = false)),
        const SizedBox(width: Gap.sm),
        _segment('Done today (${finished.length})', _showDone, () => setState(() => _showDone = true)),
      ]),
      const SizedBox(height: Gap.sm),
      Wrap(spacing: Gap.xs, runSpacing: Gap.xs, children: [
        for (final f in _Filter.values) ChoiceChip(label: Text(f.label), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
      ]),
      const SizedBox(height: Gap.md),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: AppColors.muted,
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
            child: Row(children: [
              _h('TOKEN', 2),
              _h('PATIENT', 5),
              _h('STATUS', 3),
              _h(_showDone ? 'WAITED' : 'BOOKED', 2),
              const SizedBox(width: 170),
            ]),
          ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: EmptyState(
                icon: _showDone ? Icons.task_alt_rounded : Icons.event_seat_outlined,
                title: _showDone ? 'Nothing finished yet' : 'No one waiting',
                message: _showDone ? 'Completed, cancelled and no-show tokens appear here.' : 'New app bookings and walk-ins appear here automatically.',
              ),
            ),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const Divider(),
            _row(shown[i], user, readOnly),
          ],
        ]),
      ),
    ]);
  }

  Widget _segment(String label, bool selected, VoidCallback onTap) => Material(
        color: selected ? AppColors.textPrimary : AppColors.surface,
        shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.textPrimary : AppColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 10),
            child: Text(label, style: AppText.labelMedium.copyWith(color: selected ? AppColors.onPrimary : AppColors.textPrimary)),
          ),
        ),
      );

  Widget _h(String text, int flex) => Expanded(flex: flex, child: Text(text, style: AppText.overline.copyWith(fontSize: 11, letterSpacing: 0.8)));

  Widget _row(QueueToken t, UserAccount user, bool readOnly) {
    final s = t.token.patientSnapshot;
    final age = s.age();
    final selected = t.id == _selectedTokenId;
    final isCalled = t.status == TokenStatus.called;
    final online = ref.watch(isOnlineProvider);
    final actions = readOnly ? const <TokenAction>[] : QueueActions.available(t, user.role);
    final quick = actions.where((a) => a == TokenAction.arrive || a == TokenAction.callNow).firstOrNull;

    return Material(
      color: selected ? AppColors.primaryContainer.withValues(alpha: 0.45) : (isCalled ? AppColors.infoContainer.withValues(alpha: 0.6) : AppColors.surface),
      child: InkWell(
        onTap: () => setState(() => _selectedTokenId = selected ? null : t.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
          child: Row(children: [
            Expanded(
              flex: 2,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(t.label, style: AppText.titleMedium.copyWith(fontWeight: FontWeight.w800, color: isCalled ? AppColors.info : AppColors.primary)),
                if (isNewBooking(t)) const Pill(label: 'New', fg: AppColors.onPrimary, bg: AppColors.primaryLight),
              ]),
            ),
            Expanded(flex: 5, child: TwoLine(s.name, '${age ?? '—'} / ${s.gender.short} · ${Fmt.phone(s.phone)}')),
            Expanded(
              flex: 3,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                StatusChip(t.status),
                const SizedBox(height: 2),
                Row(children: [
                  Icon(t.source == TokenSource.app ? Icons.phone_iphone_rounded : Icons.directions_walk_rounded, size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 3),
                  Text(t.source.label, style: AppText.labelSmall),
                ]),
              ]),
            ),
            Expanded(
              flex: 2,
              child: Text(_showDone ? WebFmt.minutes(t.waitMinutes) : Fmt.clock(t.token.createdAt), style: AppText.bodyMedium, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
            ),
            SizedBox(
              width: 170,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (quick != null)
                  quick == TokenAction.arrive
                      ? FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: Gap.md), textStyle: AppText.labelMedium),
                          onPressed: online ? () => QueueActions.perform(context, ref, t, quick) : null,
                          child: Text(QueueActions.label(quick, t)), // "Check in" → slip check dialog
                        )
                      : OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
                          onPressed: online ? () => QueueActions.perform(context, ref, t, quick) : null,
                          child: Text(QueueActions.label(quick, t)),
                        ),
                if (actions.isNotEmpty)
                  PopupMenuButton<TokenAction>(
                    tooltip: 'More actions',
                    enabled: online,
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (a) => QueueActions.perform(context, ref, t, a),
                    itemBuilder: (_) => [
                      for (final a in actions)
                        PopupMenuItem(
                          value: a,
                          child: Row(children: [
                            Icon(QueueActions.icon(a), size: 18, color: QueueActions.isDanger(a) ? AppColors.danger : AppColors.textSecondary),
                            const SizedBox(width: Gap.md),
                            Text(QueueActions.label(a, t), style: AppText.labelMedium.copyWith(color: QueueActions.isDanger(a) ? AppColors.danger : AppColors.textPrimary)),
                          ]),
                        ),
                    ],
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Keyboard key hint, e.g. [ / ].
class _Kbd extends StatelessWidget {
  const _Kbd(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: AppColors.muted, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
        child: Text(text, style: AppText.labelMedium.copyWith(color: AppColors.textSecondary)),
      );
}
