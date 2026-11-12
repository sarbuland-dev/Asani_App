import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/connectivity.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/web/download.dart';
import '../../core/widgets/desktop.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tokenProvider(tokenId));
    final user = ref.watch(currentUserProvider)!;
    if (t == null) return const SizedBox.shrink();
    final clinic = ref.watch(clinicProvider(t.token.clinicId));
    final doctor = ref.watch(allDoctorsProvider(t.token.clinicId)).where((d) => d.id == t.token.doctorId).firstOrNull;
    final online = ref.watch(isOnlineProvider);
    final actions = readOnly ? const [] : QueueActions.available(t, user.role);
    final s = t.token.patientSnapshot;

    return Container(
      width: 400,
      decoration: const BoxDecoration(color: AppColors.surface, border: Border(left: BorderSide(color: AppColors.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.md, Gap.sm),
          child: Row(children: [
            Expanded(child: Text('Token ${t.label}', style: AppText.titleLarge)),
            StatusChip(t.status),
            IconButton(tooltip: 'Close', onPressed: onClose, icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        const Divider(),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(Gap.xl), children: [
            if (clinic != null && doctor != null) TokenSlip(token: t.token, clinic: clinic.clinic, doctor: doctor, compact: true),
            const SizedBox(height: Gap.lg),
            Row(children: [
              SourcePill(t.source),
              const SizedBox(width: Gap.sm),
              if (t.arrivedAt != null) Pill(label: 'Arrived ${Fmt.clock(t.arrivedAt!)}', fg: AppColors.success, bg: AppColors.successContainer, icon: Icons.login_rounded),
              if (t.waitMinutes != null) ...[
                const SizedBox(width: Gap.sm),
                Pill(label: 'Waited ${WebFmt.minutes(t.waitMinutes)}', fg: AppColors.textSecondary, bg: AppColors.muted, icon: Icons.timer_outlined),
              ],
            ]),
            const SizedBox(height: Gap.md),
            _info(Icons.call_outlined, Fmt.phone(s.phone)),
            if (t.cancelReason != null) _info(Icons.info_outline_rounded, 'Cancel reason: ${t.cancelReason}'),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: Gap.lg),
              Text('ACTIONS', style: AppText.overline),
              const SizedBox(height: Gap.sm),
              Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
                for (final a in actions)
                  a == actions.first
                      ? FilledButton.icon(
                          onPressed: online ? () => QueueActions.perform(context, ref, t, a) : null,
                          icon: Icon(QueueActions.icon(a), size: 18),
                          label: Text(QueueActions.label(a, t)),
                        )
                      : OutlinedButton.icon(
                          style: QueueActions.isDanger(a)
                              ? OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger))
                              : null,
                          onPressed: online ? () => QueueActions.perform(context, ref, t, a) : null,
                          icon: Icon(QueueActions.icon(a), size: 18),
                          label: Text(QueueActions.label(a, t)),
                        ),
              ]),
            ],
            const SizedBox(height: Gap.md),
            Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
              if (!readOnly && user.role.canFollowUp && (t.status == TokenStatus.called || t.status == TokenStatus.completed))
                OutlinedButton.icon(
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
              if (!readOnly && user.role.canSearchPatients)
                TextButton.icon(
                  onPressed: () => context.go('/patients/${t.token.patientId}'),
                  icon: const Icon(Icons.person_search_rounded, size: 18),
                  label: const Text('Patient history'),
                ),
            ]),
            const SizedBox(height: Gap.xl),
            Text('HISTORY', style: AppText.overline),
            const SizedBox(height: Gap.sm),
            for (final e in t.history.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.md),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(child: TwoLine(e.note == null ? e.action : '${e.action} · ${e.note}', '${e.by} · ${Fmt.dateTime(e.at)}')),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _info(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.xs),
        child: Row(children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: Gap.sm),
          Expanded(child: Text(text, style: AppText.bodyMedium)),
        ]),
      );
}
