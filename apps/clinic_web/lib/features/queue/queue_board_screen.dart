import 'dart:async';

import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/net/connectivity.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/clinic_repository.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../doctors/doctors_screen.dart';
import 'check_in_dialog.dart';
import 'now_serving.dart';
import 'queue_actions.dart';
import 'queue_stats.dart';
import 'token_panel.dart';
import 'walk_in_dialog.dart';

enum _NotArrivedChoice { skip, callAnyway }

enum _Filter {
  all('All'),
  arrived('Arrived'),
  app('App'),
  walkIn('Walk-in');

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

  /// W-24: "Calling A-11…" appears only if the call takes more than a moment.
  String? _calling;
  Timer? _callingTimer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _callingTimer?.cancel();
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
    final expected = _nextUpOf(ref.read(todayTokensProvider(widget.clinicId)).where((t) => t.token.doctorId == doctorId).toList());
    _callingTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _calling = expected == null ? 'Calling…' : 'Calling ${expected.label}…');
    });
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
      _callingTimer?.cancel();
      if (mounted) {
        setState(() {
          _nextBusy = false;
          _calling = null;
        });
      }
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

    final board = Focus(
      focusNode: _focus,
      autofocus: true,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _focus.requestFocus(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _topBar(user, clinic, readOnly),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              // Wide screens: the token panel sits beside the board. Narrow
              // ones: it slides over, so the table keeps its width.
              final beside = box.maxWidth >= 1150;
              final panel = _selectedTokenId == null
                  ? null
                  : TokenPanel(tokenId: _selectedTokenId!, readOnly: readOnly, onClose: () => setState(() => _selectedTokenId = null));
              final column = ListView(
                padding: EdgeInsets.fromLTRB(24, 18, panel != null && beside ? 16 : 24, 24),
                children: [
                  _doctorCards(doctors, all),
                  const SizedBox(height: 14),
                  ..._doctorBoard(doctor, list, user, readOnly),
                ],
              );
              if (panel == null) return column;
              if (beside) {
                return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: column), panel]);
              }
              return Stack(children: [
                Positioned.fill(child: column),
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  child: Material(
                    elevation: 12,
                    shadowColor: AppColors.navy.withValues(alpha: 0.4),
                    child: ColoredBox(color: ClinicColors.page, child: Padding(padding: const EdgeInsets.only(left: 16), child: panel)),
                  ),
                ),
              ]);
            }),
          ),
        ]),
      ),
    );
    // The Super Admin opens this board read only inside their own screens.
    return widget.readOnly ? ClinicThemed(child: ColoredBox(color: ClinicColors.page, child: board)) : board;
  }

  // ---------------------------------------------------------------- top bar

  Widget _topBar(UserAccount user, ClinicAccount clinic, bool readOnly) {
    final today = ref.watch(todayProvider).value ?? dayKey(pktNow());
    final canType = user.role.canRunQueue && !widget.readOnly;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(color: AppColors.background, border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Queue board', style: ClinicText.pageTitle.copyWith(fontSize: 22)),
            Row(children: [
              const LiveDot(),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.readOnly ? '${clinic.clinic.name} · read-only view' : 'Live · ${Fmt.longDay(today)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ClinicText.small,
                ),
              ),
            ]),
          ]),
        ),
        if (canType) ...[
          const SizedBox(width: 14),
          SizedBox(
            width: 320,
            child: Tooltip(
              message: 'Shortcut: /',
              child: Panel(
                radius: ClinicRadii.control,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                onTap: _openCheckIn,
                child: Row(children: [
                  const Icon(Icons.search_rounded, size: 20, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Enter token code to check in', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyMedium)),
                  const Kbd('/'),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Tooltip(
            message: 'Shortcut: W',
            child: FilledButton.icon(
              onPressed: readOnly ? null : _openWalkIn,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Walk-in'), SizedBox(width: 10), Kbd('W', onDark: true)]),
            ),
          ),
        ],
      ]),
    );
  }

  // ----------------------------------------------------------- doctor cards

  Widget _doctorCards(List<Doctor> doctors, List<QueueToken> all) {
    return LayoutBuilder(builder: (context, box) {
      // Up to three cards share the row; more of them scroll sideways.
      final fit = doctors.length <= 3 && box.maxWidth / doctors.length >= 230;
      final width = fit ? (box.maxWidth - 10 * (doctors.length - 1)) / doctors.length : 280.0;
      final cards = Row(children: [
        for (final (i, d) in doctors.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          SizedBox(width: width, child: _doctorCard(d, all.where((t) => t.token.doctorId == d.id).toList(), narrow: width < 270)),
        ],
      ]);
      return fit ? cards : SingleChildScrollView(scrollDirection: Axis.horizontal, child: cards);
    });
  }

  Widget _doctorCard(Doctor d, List<QueueToken> mine, {required bool narrow}) {
    final day = ref.watch(queueDayProvider((widget.clinicId, d.id)));
    final selected = d.id == _doctorId;
    final onLeave = d.onLeave(pktNow());
    final schedule = d.scheduleOn(pktNow());
    final completed = mine.where((t) => t.status == TokenStatus.completed).length;
    final total = mine.where((t) => t.status != TokenStatus.cancelled).length;
    final booked = mine.where((t) => t.status.isActive).length;

    final Widget chip;
    if (onLeave) {
      chip = const CChip.red('On leave', dot: false);
    } else {
      chip = switch (day.sessionStatus) {
        SessionStatus.running => const CChip.green('Running'),
        SessionStatus.paused => const CChip.amber('Paused'),
        SessionStatus.ended => const CChip('Ended'),
        SessionStatus.notStarted => CChip(schedule == null ? 'Off today' : 'Starts ${Fmt.time(schedule.start)}'),
      };
    }
    final started = day.sessionStatus != SessionStatus.notStarted;
    final detail = started
        ? '$completed of $total seen${schedule == null ? '' : ' · ${Fmt.timeRangeShort(schedule)}'}'
        : '$booked booked · ${d.specialityEnum.display}';

    return Semantics(
      selected: selected,
      button: true,
      child: Panel(
        radius: 16,
        borderColor: selected ? AppColors.primary : AppColors.border,
        borderWidth: selected ? 2 : 1,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: () => setState(() {
          _doctorId = d.id;
          _selectedTokenId = null;
        }),
        child: Row(children: [
          selected ? Av.solid(d.name, size: 38) : Av(d.name, size: 38, bg: AppColors.cream),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700))),
                if (!narrow) ...[const SizedBox(width: 6), chip],
              ]),
              if (narrow) ...[const SizedBox(height: 4), chip],
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: total == 0 || !started ? 0 : completed / total,
                  minHeight: 5,
                  color: AppColors.primary,
                  backgroundColor: AppColors.cream,
                ),
              ),
              const SizedBox(height: 4),
              Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: ClinicText.small),
            ]),
          ),
        ]),
      ),
    );
  }

  // ------------------------------------------------------- selected doctor

  /// Waiting order as Next calls it: re-checked-in Skipped patients first
  /// (D-24/D-35, oldest check-in first), then the queue number.
  static int _queueOrder(QueueToken a, QueueToken b) {
    final an = a.token.isNextUp, bn = b.token.isNextUp;
    if (an && bn) return a.token.priorityAt!.compareTo(b.token.priorityAt!);
    if (an) return -1;
    if (bn) return 1;
    return a.number.compareTo(b.number);
  }

  /// The tokens Next can pick, in order.
  static List<QueueToken> _comingUp(List<QueueToken> list) =>
      list.where((t) => t.token.isNextUp || t.status == TokenStatus.booked || t.status == TokenStatus.arrived).toList()..sort(_queueOrder);

  static QueueToken? _nextUpOf(List<QueueToken> list) => _comingUp(list).firstOrNull;

  List<Widget> _doctorBoard(Doctor d, List<QueueToken> list, UserAccount user, bool readOnly) {
    final day = ref.watch(queueDayProvider((widget.clinicId, d.id)));
    final called = list.where((t) => t.status == TokenStatus.called).firstOrNull;
    final coming = _comingUp(list);
    final completed = list.where((t) => t.status == TokenStatus.completed).toList();
    final total = list.where((t) => t.status != TokenStatus.cancelled).length;
    final online = ref.watch(isOnlineProvider);

    return [
      NowServing(
        doctor: d,
        day: day,
        called: called,
        upcoming: coming.take(3).toList(),
        nextUpId: coming.firstOrNull?.id,
        done: completed.length,
        total: total,
        onOpenToken: (t) => setState(() => _selectedTokenId = t.id),
        onFollowUp: called != null && user.role.canRunQueue && !readOnly ? () => showFollowUpDialog(context, ref, called) : null,
        actions: user.role.canRunQueue && !widget.readOnly ? _heroActions(d, day, list, !readOnly && online, readOnly) : null,
      ),
      const SizedBox(height: 14),
      QueueStats(
        waiting: list.where((t) => t.status.isWaiting).toList(),
        completed: completed,
        total: total,
        nextUp: coming.firstOrNull,
      ),
      const SizedBox(height: 14),
      _waitingList(d, list, user, readOnly),
      const SizedBox(height: 10),
      Text('Patients get "3, 2, 1 ahead" and "Your turn" alerts automatically.', style: ClinicText.small, textAlign: TextAlign.center),
    ];
  }

  /// Next, Undo, Start / Pause / Resume and End.
  Widget _heroActions(Doctor d, QueueDay day, List<QueueToken> list, bool canAct, bool readOnly) {
    final s = day.sessionStatus;
    final running = s == SessionStatus.running;
    final canUndo = ref.watch(repositoryProvider).canUndoNext(d.id);
    if (canUndo) ref.watch(secondTickerProvider); // re-check the 30 s window
    final busy = _nextBusy;
    final startIsMain = s == SessionStatus.notStarted || s == SessionStatus.paused;

    ButtonStyle style({required bool main}) => FilledButton.styleFrom(
          backgroundColor: main ? AppColors.cream : AppColors.onPrimary.withValues(alpha: 0.1),
          foregroundColor: main ? AppColors.primary : AppColors.onPrimary,
          disabledBackgroundColor: AppColors.onPrimary.withValues(alpha: main ? 0.25 : 0.06),
          disabledForegroundColor: AppColors.onPrimary.withValues(alpha: 0.5),
          side: main ? null : BorderSide(color: AppColors.onPrimary.withValues(alpha: 0.16)),
          minimumSize: const Size(0, 52),
          textStyle: AppText.labelLarge.copyWith(fontWeight: FontWeight.w700, fontSize: main ? 16 : 14),
        );

    final next = FilledButton(
      // While it is calling, the button keeps its look and cannot be pressed twice.
      style: _calling != null
          ? style(main: true).copyWith(
              backgroundColor: const WidgetStatePropertyAll(AppColors.cream),
              foregroundColor: const WidgetStatePropertyAll(AppColors.primary),
            )
          : style(main: !startIsMain),
      onPressed: canAct && running && !busy ? () => _next(d.id) : null,
      child: BusyLabel(
        busy: _calling != null,
        busyText: _calling ?? '',
        color: AppColors.primary,
        child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Next patient'), SizedBox(width: 8), Kbd('N')]),
      ),
    );

    return Row(children: [
      if (startIsMain) ...[
        Expanded(
          child: FilledButton.icon(
            style: style(main: true),
            onPressed: canAct && !busy ? () => _session(d, SessionAction.start, list) : null,
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: Text(s == SessionStatus.paused ? 'Resume session' : 'Start session'),
          ),
        ),
        const SizedBox(width: 8),
        next,
      ] else if (s == SessionStatus.ended)
        Expanded(child: Text('Session ended for today', style: AppText.labelLarge.copyWith(color: AppColors.onPrimaryMuted)))
      else
        Expanded(child: next),
      if (canUndo && !readOnly) ...[
        const SizedBox(width: 8),
        FilledButton.icon(
          style: style(main: false),
          onPressed: busy ? null : () => runAction(context, () => ref.read(repositoryProvider).undoNext(d.id), success: 'Last Next undone.'),
          icon: const Icon(Icons.undo_rounded, size: 18),
          label: const Text('Undo'),
        ),
      ],
      if (running) ...[
        const SizedBox(width: 8),
        FilledButton.icon(
          style: style(main: false),
          onPressed: canAct && !busy ? () => _session(d, SessionAction.pause, list) : null,
          icon: const Icon(Icons.pause_rounded, size: 18),
          label: const Text('Pause'),
        ),
      ],
      if (running || s == SessionStatus.paused) ...[
        const SizedBox(width: 8),
        FilledButton.icon(
          style: style(main: false),
          onPressed: canAct && !busy ? () => _session(d, SessionAction.end, list) : null,
          icon: const Icon(Icons.stop_rounded, size: 18),
          label: const Text('End'),
        ),
      ],
    ]);
  }

  // --------------------------------------------------------- waiting list

  Widget _waitingList(Doctor d, List<QueueToken> list, UserAccount user, bool readOnly) {
    bool done(QueueToken t) => t.status == TokenStatus.completed || t.status == TokenStatus.cancelled || t.status == TokenStatus.noShow;
    // The called patient is shown in "Now serving", not in the list.
    final active = list.where((t) => !done(t) && t.status != TokenStatus.called).toList()..sort(_queueOrder);
    final finished = list.where(done).toList()..sort((a, b) => b.number.compareTo(a.number));
    bool matches(QueueToken t, _Filter f) => switch (f) {
          _Filter.all => true,
          _Filter.arrived => t.status == TokenStatus.arrived,
          _Filter.app => t.source == TokenSource.app,
          _Filter.walkIn => t.source == TokenSource.walkIn,
        };
    final source = _showDone ? finished : active;
    final shown = source.where((t) => matches(t, _filter)).toList();
    final nextUpId = _nextUpOf(list)?.id;

    return Panel(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text('${_showDone ? 'Done today' : 'Waiting list'} · ${d.name}', style: AppText.titleSmall.copyWith(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.end, children: [
                for (final f in _Filter.values)
                  FilterPill('${f.label} ${source.where((t) => matches(t, f)).length}', selected: _filter == f, onTap: () => setState(() => _filter = f)),
                const SizedBox(width: 6),
                FilterPill(
                  _showDone ? 'Back to waiting ${active.length}' : 'Done today ${finished.length}',
                  selected: _showDone,
                  onTap: () => setState(() {
                    _showDone = !_showDone;
                    _filter = _Filter.all;
                  }),
                ),
              ]),
            ),
          ]),
        ),
        SimpleTable(
          columns: [
            const TableColumn('Token', flex: 3),
            const TableColumn('Patient', flex: 8),
            const TableColumn('Source', flex: 3),
            const TableColumn('Status', flex: 4),
            TableColumn(_showDone ? 'Waited' : 'Booked', flex: 3),
            const TableColumn('', flex: 6, align: TextAlign.right),
          ],
          empty: EmptyState(
            icon: _showDone ? Icons.task_alt_rounded : Icons.event_seat_outlined,
            title: _showDone ? 'Nothing finished yet' : 'No one waiting',
            message: _showDone ? 'Completed, cancelled and no-show tokens appear here.' : 'New app bookings and walk-ins appear here automatically.',
          ),
          onTap: (i) => setState(() => _selectedTokenId = shown[i].id == _selectedTokenId ? null : shown[i].id),
          rowColor: (i) => shown[i].id == _selectedTokenId
              ? ClinicColors.tint
              : (!_showDone && shown[i].id == nextUpId ? ClinicColors.amberTint : null),
          rows: [for (final t in shown) _row(t, user, readOnly, !_showDone && t.id == nextUpId)],
        ),
      ]),
    );
  }

  List<Widget> _row(QueueToken t, UserAccount user, bool readOnly, bool nextUp) {
    final s = t.token.patientSnapshot;
    final online = ref.watch(isOnlineProvider) && !_nextBusy;
    final actions = readOnly ? const <TokenAction>[] : QueueActions.available(t, user.role);
    // One button per row: what this patient most likely needs now.
    final preferred = switch (t.status) {
      TokenStatus.booked => TokenAction.arrive,
      TokenStatus.onHold => TokenAction.backToQueue,
      TokenStatus.arrived || TokenStatus.skipped => TokenAction.callNow,
      _ => null,
    };
    final quick = actions.contains(preferred) ? preferred : null;
    final filled = quick == TokenAction.callNow && t.status == TokenStatus.arrived;
    const compact = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, 34)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
    );

    return [
      Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(minWidth: 52),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: nextUp ? AppColors.primary : AppColors.cream, borderRadius: BorderRadius.circular(10)),
          child: Center(
            widthFactor: 1,
            child: Text(t.label,
                maxLines: 1,
                style: AppText.labelMedium.copyWith(fontSize: 15, fontWeight: FontWeight.w800, color: nextUp ? AppColors.onPrimary : AppColors.primary)),
          ),
        ),
      ),
      Row(children: [
        nextUp ? Av.solid(s.name, size: 34) : Av(s.name, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Flexible(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700))),
              if (t.token.isNextUp || isNewBooking(t)) ...[
                const SizedBox(width: 6),
                t.token.isNextUp
                    ? const CChip('Next up', fg: AppColors.surface, bg: AppColors.warning, fontSize: 10)
                    : const CChip('New', fg: AppColors.onPrimary, bg: AppColors.primaryLight, fontSize: 10),
              ],
            ]),
            Text('${s.age() ?? '—'} / ${s.gender.short} · ${Fmt.phone(s.phone)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ClinicText.small),
          ]),
        ),
      ]),
      Row(children: [
        Icon(t.source == TokenSource.app ? Icons.phone_iphone_rounded : Icons.directions_walk_rounded, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 5),
        Flexible(child: Text(t.source.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyMedium.copyWith(fontSize: 13))),
      ]),
      TokenStatusChip(t.status),
      Text(_showDone ? WebFmt.minutes(t.waitMinutes) : Fmt.clock(t.token.createdAt),
          maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: ClinicText.body),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        if (quick != null)
          Flexible(
            child: filled
                ? FilledButton(
                    style: compact,
                    onPressed: online ? () => QueueActions.perform(context, ref, t, quick) : null,
                    child: Text(QueueActions.label(quick, t), maxLines: 1, overflow: TextOverflow.ellipsis),
                  )
                : OutlinedButton(
                    style: compact,
                    onPressed: online ? () => QueueActions.perform(context, ref, t, quick) : null,
                    child: Text(QueueActions.label(quick, t), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ), // "Check in" → slip check dialog (D-26)
          ),
        if (actions.isNotEmpty)
          PopupMenuButton<TokenAction>(
            tooltip: 'More actions',
            enabled: online,
            icon: const Icon(Icons.more_vert_rounded, size: 20),
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
    ];
  }
}
