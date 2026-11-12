import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/connectivity.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/desktop.dart';
import '../../data/clinic_repository.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'queue_actions.dart';
import 'token_slip.dart';

/// W-12 / C-05: type the token code → see the patient's own slip → Arrived & Print.
Future<void> showCheckInDialog(BuildContext context, String clinicId, {String initialCode = ''}) =>
    showDialog<void>(context: context, builder: (_) => _CheckInDialog(clinicId: clinicId, initialCode: initialCode));

class _CheckInDialog extends ConsumerStatefulWidget {
  const _CheckInDialog({required this.clinicId, required this.initialCode});
  final String clinicId;
  final String initialCode;

  @override
  ConsumerState<_CheckInDialog> createState() => _CheckInDialogState();
}

class _CheckInDialogState extends ConsumerState<_CheckInDialog> {
  late final _code = TextEditingController(text: widget.initialCode);
  String? _pickedId; // when "11" matched several doctors
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _arrive(QueueToken t) async {
    setState(() => _busy = true);
    final ok = await QueueActions.perform(context, ref, t, TokenAction.arrive);
    if (!mounted) return;
    setState(() => _busy = false);
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
    final canArrive = token != null && token.status == TokenStatus.booked && user.role.canCheckIn && online;

    return AppDialog(
      title: 'Check in',
      subtitle: 'Type the code the patient shows, e.g. A11 or A-11.',
      width: 560,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        if (token != null && token.status.canCancel && user.role.canAllTokenActions)
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
            onPressed: _busy || !online ? null : () => QueueActions.perform(context, ref, token, TokenAction.cancel),
            child: const Text('Cancel token'),
          ),
        if (token != null && token.status == TokenStatus.arrived)
          OutlinedButton.icon(
            onPressed: () => QueueActions.perform(context, ref, token, TokenAction.reprint),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Reprint'),
          ),
        FilledButton.icon(
          onPressed: canArrive && !_busy ? () => _arrive(token) : null,
          icon: const Icon(Icons.how_to_reg_rounded),
          label: const Text('Arrived & Print'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: AppText.titleLarge.copyWith(letterSpacing: 2),
          decoration: const InputDecoration(hintText: 'Token code', prefixIcon: Icon(Icons.confirmation_number_outlined)),
          onChanged: (_) => setState(() => _pickedId = null),
          onSubmitted: (_) {
            if (canArrive && !_busy) _arrive(token);
          },
        ),
        const SizedBox(height: Gap.lg),
        if (lookup == null)
          _hint()
        else if (lookup.ambiguous.isNotEmpty && picked == null)
          _ambiguous(lookup.ambiguous, doctorOf)
        else if (token != null) ...[
          _status(token),
          const SizedBox(height: Gap.lg),
          if (clinic != null && doctorOf(token) != null)
            Center(child: SizedBox(width: 380, child: TokenSlip(token: token.token, clinic: clinic.clinic, doctor: doctorOf(token)!))),
        ] else if (lookup.otherDate != null)
          Banner2(
            icon: Icons.event_busy_rounded,
            text: 'This token is for another date (${Fmt.shortDay(lookup.otherDate!.token.date)}), '
                '${lookup.otherDate!.token.patientSnapshot.name}.',
          )
        else
          Banner2(
            icon: Icons.cancel_outlined,
            fg: AppColors.danger,
            bg: AppColors.dangerContainer,
            text: 'No token ${code.toUpperCase()} today.',
          ),
      ]),
    );
  }

  Widget _hint() => Container(
        padding: const EdgeInsets.all(Gap.xl),
        decoration: BoxDecoration(color: AppColors.muted, borderRadius: BorderRadius.circular(Radii.card)),
        child: Row(children: [
          const IconBox(icon: Icons.qr_code_2_rounded, bg: AppColors.surface),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text("The patient's slip appears here so you can match it with the one on their phone or WhatsApp.",
                style: AppText.bodyMedium),
          ),
        ]),
      );

  Widget _status(QueueToken t) {
    final s = t.status;
    if (s == TokenStatus.booked) {
      return const Banner2(text: 'Booked: today, valid', icon: Icons.check_circle_rounded, fg: AppColors.success, bg: AppColors.successContainer);
    }
    if (s == TokenStatus.cancelled) {
      return const Banner2(text: 'This token was cancelled.', icon: Icons.cancel_outlined, fg: AppColors.danger, bg: AppColors.dangerContainer);
    }
    if (s == TokenStatus.completed) {
      return const Banner2(text: 'This token is already completed.', icon: Icons.cancel_outlined, fg: AppColors.danger, bg: AppColors.dangerContainer);
    }
    if (s == TokenStatus.noShow) {
      return const Banner2(text: 'This token was marked No-show.', icon: Icons.person_off_outlined, fg: AppColors.danger, bg: AppColors.dangerContainer);
    }
    return Banner2(text: 'Already checked in · ${s.label}', icon: Icons.info_outline_rounded, fg: AppColors.info, bg: AppColors.infoContainer);
  }

  Widget _ambiguous(List<QueueToken> list, Doctor? Function(QueueToken) doctorOf) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('More than one doctor has this number today. Which one?', style: AppText.labelMedium),
        const SizedBox(height: Gap.sm),
        for (final t in list)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: AppCard(
              onTap: () => setState(() => _pickedId = t.id),
              child: Row(children: [
                Text(t.label, style: AppText.titleLarge.copyWith(color: AppColors.primary)),
                const SizedBox(width: Gap.lg),
                Expanded(child: TwoLine(t.token.patientSnapshot.name, doctorOf(t)?.name)),
                StatusChip(t.status),
              ]),
            ),
          ),
      ]);
}
