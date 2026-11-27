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
  const TokenPanel({super.key, required this.tokenId, required this.onClose, this.readOnly = false});
  final String tokenId;
  final VoidCallback onClose;
  final bool readOnly;

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
    final actions = readOnly ? const <TokenAction>[] : QueueActions.available(t, user.role);

    // This patient's completed visits here before today's token.
    final earlier = (patient?.visits ?? const <QueueToken>[])
        .where((v) => v.status == TokenStatus.completed && v.token.date.compareTo(t.token.date) < 0)
        .toList();
    final snap = t.token.patientSnapshot;
    final visitNote = patient == null ? null : '${snap.age() ?? '—'} / ${snap.gender.short} · ${WebFmt.ordinal(earlier.length + 1)} visit here';

    return SizedBox(
      width: width,
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
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            _actionGrid(context, ref, t, actions, online),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 4, runSpacing: 4, children: [
            if (!readOnly && user.role.canRunQueue && (t.status == TokenStatus.called || t.status == TokenStatus.completed))
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
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: i == 0 ? AppColors.primary : AppColors.primarySoft, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.note == null ? e.action : '${e.action} · ${e.note}', style: AppText.labelMedium.copyWith(fontSize: 12)),
                        Text('${Fmt.dateTime(e.at)} · ${e.by}', style: ClinicText.small),
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

  /// First action full width, then pairs; Cancel always full width at the end.
  Widget _actionGrid(BuildContext context, WidgetRef ref, QueueToken t, List<TokenAction> actions, bool online) {
    Widget button(TokenAction a, {bool primary = false}) {
      final onPressed = online ? () => QueueActions.perform(context, ref, t, a) : null;
      final label = Text(QueueActions.label(a, t), maxLines: 1, overflow: TextOverflow.ellipsis);
      if (primary) return SizedBox(height: 50, child: FilledButton(onPressed: onPressed, child: label));
      return OutlinedButton(
        style: QueueActions.isDanger(a) ? OutlinedButton.styleFrom(foregroundColor: AppColors.danger) : null,
        onPressed: onPressed,
        child: label,
      );
    }

    final rest = actions.skip(1).where((a) => a != TokenAction.cancel).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      button(actions.first, primary: true),
      for (var i = 0; i < rest.length; i += 2) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: button(rest[i])),
          if (i + 1 < rest.length) ...[const SizedBox(width: 8), Expanded(child: button(rest[i + 1]))],
        ]),
      ],
      if (actions.skip(1).contains(TokenAction.cancel)) ...[const SizedBox(height: 8), button(TokenAction.cancel)],
    ]);
  }
}
