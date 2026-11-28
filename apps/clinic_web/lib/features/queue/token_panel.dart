import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/connectivity.dart';
import '../../core/utils/formatters.dart';
import '../../core/web/download.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/clinic_repository.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'queue_actions.dart';
import 'token_slip.dart';

/// W-11: token detail panel (slip, actions, history).
class TokenPanel extends ConsumerWidget {
  const TokenPanel({super.key, required this.tokenId, required this.onClose, this.readOnly = false, this.cancelOnly = false, this.nextUp = false, this.panelWidth = width});
  final String tokenId;
  final VoidCallback onClose;
  final bool readOnly;

  /// A suspended clinic: only "Cancel token" changes anything (D-68).
  final bool cancelOnly;

  /// This is the token Next patient will call.
  final bool nextUp;
  final double panelWidth;

  static const width = 340.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tokenProvider(tokenId));
    final user = ref.watch(currentUserProvider)!;
    if (t == null) return const SizedBox.shrink();
    final clinicId = t.token.clinicId;
    final clinic = ref.watch(clinicProvider(clinicId));
    final doctor = ref.watch(allDoctorsProvider(clinicId)).where((d) => d.id == t.token.doctorId).firstOrNull;
    final patient = ref.watch(clinicPatientProvider((clinicId, t.token.patientId)));
    final online = ref.watch(isOnlineProvider);
    final actions = readOnly
        ? const <TokenAction>[]
        : QueueActions.available(t, user.role).where((a) => !cancelOnly || a == TokenAction.cancel).toList();

    // This patient's completed visits here before today's token.
    final earlier = (patient?.visits ?? const <QueueToken>[])
        .where((v) => v.status == TokenStatus.completed && v.token.date.compareTo(t.token.date) < 0)
        .toList();
    final snap = t.token.patientSnapshot;
    final visitNote = patient == null ? null : '${snap.age() ?? '—'} / ${snap.gender.short} · ${WebFmt.ordinal(earlier.length + 1)} visit here';

    return SizedBox(
      width: panelWidth,
      child: ColoredBox(
        color: ClinicColors.page,
        child: ListView(padding: const EdgeInsets.fromLTRB(4, 20, 20, 20), children: [
          Row(children: [
            Expanded(child: Text('Token detail', style: AppText.titleSmall.copyWith(fontSize: 15, fontWeight: FontWeight.w800))),
            IconButton(
              tooltip: 'Close',
              onPressed: onClose,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surface,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
              ),
              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
            ),
          ]),
          const SizedBox(height: 10),
          if (clinic != null && doctor != null)
            TokenSlip(
              token: t.token,
              clinic: clinic.clinic,
              doctor: doctor,
              notch: ClinicColors.page,
              headerTrailing: TokenStatusChip(t.status),
              tokenTrailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(t.source == TokenSource.app ? 'Booked' : 'Walk-in', style: ClinicText.small),
                Text(Fmt.clock(t.token.createdAt), style: AppText.labelMedium.copyWith(fontSize: 13)),
              ]),
              patientNote: visitNote,
              rows: [
                ('Phone', Fmt.phone(snap.phone)),
                ('Doctor', doctor.name),
                if (earlier.isNotEmpty) ('Last visit', Fmt.shortDay(earlier.first.token.date)),
                if (t.arrivedAt != null) ('Arrived', Fmt.clock(t.arrivedAt!)),
                if (t.waitMinutes != null) ('Waited', WebFmt.minutes(t.waitMinutes)),
                if (t.cancelReason != null) ('Cancel reason', t.cancelReason!),
              ],
            ),
          if (nextUp) ...[
            const SizedBox(height: 14),
            _nextUpNote(t),
          ],
          if (t.status == TokenStatus.skipped) ...[
            const SizedBox(height: 14),
            const NoteBox('Skipped. When the patient checks in with the token code, they are called right after the current one.'),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            _actionGrid(context, ref, t, actions, online),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 4, runSpacing: 4, children: [
            if (!readOnly && !cancelOnly && user.role.canRunQueue && (t.status == TokenStatus.called || t.status == TokenStatus.completed))
              TextButton.icon(
                onPressed: () => showFollowUpDialog(context, ref, t),
                icon: const Icon(Icons.event_repeat_rounded, size: 18),
                label: const Text('Set follow-up'),
              ),
            if (!readOnly)
              TextButton.icon(
                onPressed: () async {
                  await copyText(QueueActions.patientDetails(t, doctor));
                  if (context.mounted) showSnack(context, 'Patient details copied.');
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy patient details'),
              ),
            if (!readOnly && user.role.canRunQueue)
              TextButton.icon(
                onPressed: () => context.go('/patients/${t.token.patientId}'),
                icon: const Icon(Icons.person_search_rounded, size: 18),
                label: const Text('Patient history'),
              ),
          ]),
          const SizedBox(height: 8),
          Panel(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('History', style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              for (final (i, e) in t.history.reversed.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _dot(i, e),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.note == null ? e.action : '${e.action} · ${e.note}', style: AppText.labelMedium.copyWith(fontSize: 12)),
                        Text('${dayKey(e.at) == t.token.date ? Fmt.clock(e.at) : Fmt.dateTime(e.at)} · ${e.by}', style: ClinicText.small),
                      ]),
                    ),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  /// Latest step forest, a skip amber, older steps sage (board W-10).
  Widget _dot(int index, TokenEvent e) {
    final skip = e.action.startsWith('Skipped');
    final color = skip ? AppColors.warning : (index == 0 ? AppColors.primary : AppColors.primarySoft);
    final ring = skip ? AppColors.warningContainer : (index == 0 ? ClinicColors.tint : null);
    return Container(
      margin: const EdgeInsets.only(top: 3),
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: ring == null ? null : [BoxShadow(color: ring, spreadRadius: 3)]),
    );
  }

  Widget _nextUpNote(QueueToken t) {
    final why = t.token.isNextUp
        ? ' Checked in again after a skip, so the app tells the patient they are next.'
        : (t.status == TokenStatus.booked ? ' Not arrived yet.' : '');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: ClinicColors.amberTint, borderRadius: BorderRadius.circular(14), border: Border.all(color: ClinicColors.amberBorder)),
      child: Row(children: [
        const Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.warningText),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Next up. Pressing Next patient calls ${t.label}.$why',
              style: AppText.bodyMedium.copyWith(fontSize: 13, color: AppColors.warningText)),
        ),
      ]),
    );
  }

  /// Back to queue (held tokens) on top, then pairs, Cancel full width, and the
  /// emergency call as a small link.
  Widget _actionGrid(BuildContext context, WidgetRef ref, QueueToken t, List<TokenAction> actions, bool online) {
    VoidCallback? run(TokenAction a) => online ? () => QueueActions.perform(context, ref, t, a) : null;
    Widget button(TokenAction a) => OutlinedButton(
          style: QueueActions.isDanger(a) ? OutlinedButton.styleFrom(foregroundColor: AppColors.danger) : null,
          onPressed: run(a),
          child: Text(a == TokenAction.noShow ? 'No-show' : QueueActions.label(a, t), maxLines: 1, overflow: TextOverflow.ellipsis),
        );

    const own = {TokenAction.backToQueue, TokenAction.cancel, TokenAction.callNow};
    final pairs = actions.where((a) => !own.contains(a)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (actions.contains(TokenAction.backToQueue)) ...[
        SizedBox(height: 50, child: FilledButton(onPressed: run(TokenAction.backToQueue), child: Text(QueueActions.label(TokenAction.backToQueue, t)))),
        const SizedBox(height: 8),
      ],
      for (var i = 0; i < pairs.length; i += 2) ...[
        if (i > 0) const SizedBox(height: 8),
        Row(children: [
          Expanded(child: button(pairs[i])),
          if (i + 1 < pairs.length) ...[const SizedBox(width: 8), Expanded(child: button(pairs[i + 1]))],
        ]),
      ],
      if (actions.contains(TokenAction.cancel)) ...[const SizedBox(height: 8), button(TokenAction.cancel)],
      if (actions.contains(TokenAction.callNow)) ...[
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            onPressed: run(TokenAction.callNow),
            child: Text('Call out of turn (emergency)', style: ClinicText.small.copyWith(fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
          ),
        ),
      ],
    ]);
  }
}
