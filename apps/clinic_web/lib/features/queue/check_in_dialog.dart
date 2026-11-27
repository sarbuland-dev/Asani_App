import 'dart:async';

import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/connectivity.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/clinic_repository.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'queue_actions.dart';
import 'token_slip.dart';

/// W-12 / C-05: type the token code → see the patient's own slip → Arrived & Print.
/// Every "Arrived" goes through here, so the slip is always checked first.
/// [tokenId] opens it on one token (from the board or the token panel).
Future<void> showCheckInDialog(BuildContext context, String clinicId, {String initialCode = '', String? tokenId}) =>
    showDialog<void>(context: context, builder: (_) => _CheckInDialog(clinicId: clinicId, initialCode: initialCode, tokenId: tokenId));

class _CheckInDialog extends ConsumerStatefulWidget {
  const _CheckInDialog({required this.clinicId, required this.initialCode, this.tokenId});
  final String clinicId;
  final String initialCode;
  final String? tokenId;

  @override
  ConsumerState<_CheckInDialog> createState() => _CheckInDialogState();
}

class _CheckInDialogState extends ConsumerState<_CheckInDialog> {
  late final _code = TextEditingController(text: widget.initialCode);
  late String? _pickedId = widget.tokenId; // set when "11" matched several doctors, or opened on one token
  bool _busy = false;

  /// W-24: the "Marking arrived…" label shows only after a short wait.
  bool _showBusy = false;
  Timer? _busyTimer;

  @override
  void dispose() {
    _busyTimer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _arrive(QueueToken t) async {
    setState(() => _busy = true);
    _busyTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _showBusy = true);
    });
    final ok = await QueueActions.perform(context, ref, t, TokenAction.arrive, slipChecked: true);
    _busyTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _showBusy = false;
    });
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(repoTickProvider); // live status while the dialog is open
    final repo = ref.watch(repositoryProvider);
    final user = ref.watch(currentUserProvider)!;
    final code = _code.text.trim();
    final lookup = code.isEmpty ? null : repo.findByCode(widget.clinicId, code);
    final picked = _pickedId == null ? null : repo.tokenById(_pickedId!);
    final token = picked ?? lookup?.token;
    final clinic = ref.watch(clinicProvider(widget.clinicId));
    final doctors = ref.watch(allDoctorsProvider(widget.clinicId));
    Doctor? doctorOf(QueueToken t) => doctors.where((d) => d.id == t.token.doctorId).firstOrNull;
    final online = ref.watch(isOnlineProvider);
    // D-24: a Skipped patient can check in later and is called right after the current patient.
    final canArrive = token != null && (token.status == TokenStatus.booked || token.status == TokenStatus.skipped) && user.role.canRunQueue && online;

    final Widget result;
    if (lookup == null && token == null) {
      result = _message(Icons.confirmation_number_outlined, "The patient's slip appears here",
          'Match it with the one on their phone or WhatsApp.', ClinicColors.tint, AppColors.primary);
    } else if (lookup != null && lookup.ambiguous.isNotEmpty && picked == null) {
      result = _ambiguous(lookup.ambiguous, doctorOf);
    } else if (token != null) {
      final doctor = doctorOf(token);
      result = clinic == null || doctor == null ? _ribbon(token) : _slip(token, clinic.clinic, doctor);
    } else if (lookup?.otherDate != null) {
      result = _message(
        Icons.calendar_today_rounded,
        'Booked for another date',
        'This token is for ${Fmt.shortDay(lookup!.otherDate!.token.date)}, ${lookup.otherDate!.token.patientSnapshot.name}.',
        AppColors.warningContainer,
        AppColors.warning,
      );
    } else {
      result = _message(Icons.search_off_rounded, 'Not found', 'No token ${code.toUpperCase()} today. Check the code.', AppColors.cream, AppColors.textSecondary);
    }

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 800, maxHeight: (MediaQuery.sizeOf(context).height - 48).clamp(0, 620)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: 290, child: _codePane(canArrive && !_busy ? () => _arrive(token) : null)),
          Expanded(
            child: ColoredBox(
              color: AppColors.background,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 12), child: result)),
                Padding(padding: const EdgeInsets.fromLTRB(24, 4, 24, 20), child: _buttons(context, user, token, canArrive, online)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buttons(BuildContext context, UserAccount user, QueueToken? token, bool canArrive, bool online) => Row(children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: canArrive && !_busy ? () => _arrive(token!) : null,
              style: _showBusy
                  ? FilledButton.styleFrom(disabledBackgroundColor: AppColors.primary, disabledForegroundColor: AppColors.onPrimary)
                  : null,
              icon: _showBusy ? const AsaniLoader(size: 22, color: AppColors.onPrimary) : const Icon(Icons.print_rounded, size: 18),
              label: Text(_showBusy ? 'Marking arrived…' : 'Arrived & print', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        if (token != null && token.status == TokenStatus.arrived) ...[
          const SizedBox(width: 10),
          SizedBox(
            height: 52,
            child: OutlinedButton(onPressed: () => QueueActions.perform(context, ref, token, TokenAction.reprint), child: const Text('Reprint')),
          ),
        ],
        if (token != null && token.status.canCancel && user.role.canRunQueue) ...[
          const SizedBox(width: 10),
          SizedBox(
            height: 52,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: _busy || !online ? null : () => QueueActions.perform(context, ref, token, TokenAction.cancel),
              child: const Text('Cancel token'),
            ),
          ),
        ],
        const SizedBox(width: 10),
        SizedBox(height: 52, child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))),
      ]);

  // ------------------------------------------------------------ code pane

  /// Dark left side: the code boxes. A transparent text field on top of them
  /// takes the typing.
  Widget _codePane(VoidCallback? onEnter) {
    final typed = _code.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return HeroBlock(
      radius: 0,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: IntrinsicHeight(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const IconTile(Icons.how_to_reg_rounded, bg: AppColors.cream),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Check in', style: AppText.titleLarge.copyWith(color: AppColors.onPrimary))),
                  InkWell(onTap: () => Navigator.pop(context), child: const Kbd('Esc', onDark: true)),
                ]),
                const SizedBox(height: 22),
                Text('TOKEN CODE', style: ClinicText.caps.copyWith(color: AppColors.primarySoft)),
                const SizedBox(height: 14),
                Stack(children: [
                  _codeBoxes(typed),
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0,
                      alwaysIncludeSemantics: true,
                      child: TextField(
                        controller: _code,
                        autofocus: true,
                        expands: true,
                        maxLines: null,
                        showCursor: false,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 -]')), LengthLimitingTextInputFormatter(6)],
                        decoration: const InputDecoration(labelText: 'Token code'),
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() => _pickedId = null),
                        onSubmitted: (_) => onEnter?.call(),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                Text('Type the code the patient shows on the phone or says at the counter. The dash is optional: A11 or A-11.',
                    style: AppText.bodyMedium.copyWith(fontSize: 13, color: AppColors.onPrimaryMuted, height: 1.55)),
                const Spacer(),
                const SizedBox(height: 16),
                _hint('Enter', 'Arrived & print'),
                const SizedBox(height: 8),
                _hint('/', 'Open check-in from the queue board'),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hint(String key, String text) => Row(children: [
        Kbd(key, onDark: true),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: ClinicText.small.copyWith(color: AppColors.primarySoft))),
      ]);

  /// "A – 1 1": one box per typed character, plus the next empty one.
  Widget _codeBoxes(String typed) {
    final hasLetter = typed.isNotEmpty && RegExp(r'^[A-Z]').hasMatch(typed);
    final letter = hasLetter ? typed[0] : '';
    final digits = hasLetter ? typed.substring(1) : typed;

    Widget box(String char, {bool cursor = false}) => Container(
          width: 46,
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.onPrimary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cursor ? AppColors.onPrimary : AppColors.onPrimary.withValues(alpha: 0.18), width: 1.5),
          ),
          child: Text(char, style: ClinicText.big(28, color: AppColors.onPrimary)),
        );

    return Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      box(letter, cursor: typed.isEmpty),
      Text('–', style: ClinicText.big(24, color: AppColors.primarySoft)),
      for (final d in digits.split('')) box(d),
      if (typed.isNotEmpty && digits.length < 3) box('', cursor: true),
    ]);
  }

  // -------------------------------------------------------------- results

  Widget _slip(QueueToken t, Clinic clinic, Doctor doctor) {
    final schedule = doctor.scheduleOn(parseDayKey(t.token.date));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TokenSlip(
        token: t.token,
        clinic: clinic,
        doctor: doctor,
        notch: AppColors.background,
        ribbon: _ribbon(t),
        headerTrailing: Text(
          '${t.source == TokenSource.app ? 'Booked in the app' : 'Walk-in'} · ${Fmt.clock(t.token.createdAt)}',
          style: ClinicText.small,
        ),
        tokenTrailing: CChip('${doctor.name} · ${doctor.tokenPrefix}', bg: AppColors.surface, fg: AppColors.primary),
        rows: [
          ('Doctor', doctor.name),
          ('Date', '${Fmt.shortDay(t.token.date)}${schedule == null ? '' : ' · ${Fmt.timeRange(schedule)}'}'),
        ],
      ),
      const SizedBox(height: 10),
      Text("Match this with the slip on the patient's phone.", style: ClinicText.small, textAlign: TextAlign.center),
    ]);
  }

  Widget _ribbon(QueueToken t) {
    final (IconData icon, String text, Color bg, Color fg) = switch (t.status) {
      TokenStatus.booked => (Icons.check_circle_rounded, 'Booked for today · valid', AppColors.successContainer, AppColors.successText),
      TokenStatus.skipped => (
          Icons.replay_rounded,
          'Skipped earlier. Arrived & print puts them next in line.',
          AppColors.warningContainer,
          AppColors.warningText
        ),
      TokenStatus.cancelled => (Icons.cancel_rounded, 'This token was cancelled.', AppColors.dangerContainer, AppColors.dangerText),
      TokenStatus.noShow => (Icons.person_off_rounded, 'This token was marked No-show.', AppColors.dangerContainer, AppColors.dangerText),
      TokenStatus.completed => (
          Icons.task_alt_rounded,
          t.token.completedAt == null ? 'Already completed.' : 'Already completed at ${Fmt.clock(t.token.completedAt!)}.',
          ClinicColors.tint,
          AppColors.primary
        ),
      _ => (Icons.info_outline_rounded, 'Already checked in · ${t.status.label}', AppColors.infoContainer, AppColors.infoDark),
    };
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      child: Row(children: [
        Icon(icon, size: 22, color: fg),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AppText.labelMedium.copyWith(color: fg, fontWeight: FontWeight.w800))),
      ]),
    );
  }

  Widget _message(IconData icon, String title, String text, Color bg, Color fg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(children: [
          IconTile(icon, size: 56, bg: bg, fg: fg),
          const SizedBox(height: 14),
          Text(title, style: AppText.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(text, style: AppText.bodyMedium, textAlign: TextAlign.center),
        ]),
      );

  Widget _ambiguous(List<QueueToken> list, Doctor? Function(QueueToken) doctorOf) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('More than one doctor has this number today. Which one?', style: AppText.labelMedium),
        const SizedBox(height: 10),
        for (final t in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              radius: 14,
              padding: const EdgeInsets.all(14),
              onTap: () => setState(() => _pickedId = t.id),
              child: Row(children: [
                Text(t.label, style: ClinicText.big(22, color: AppColors.primary)),
                const SizedBox(width: 16),
                Expanded(child: TwoLine(t.token.patientSnapshot.name, doctorOf(t)?.name)),
                TokenStatusChip(t.status),
              ]),
            ),
          ),
      ]);
}
