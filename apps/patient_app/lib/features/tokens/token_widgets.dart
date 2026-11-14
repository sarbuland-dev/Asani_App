import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:asani_ui/asani_ui.dart';
import '../../data/providers.dart';

/// "Now serving A-7 · 3 ahead" style live line for a token.
String liveLine(Token token, QueueDay? day, int ahead) {
  if (day == null) return '';
  if (token.status == TokenStatus.called) return 'Your turn now';
  switch (day.sessionStatus) {
    case SessionStatus.notStarted:
      return "Doctor hasn't started yet";
    case SessionStatus.paused:
      return 'Queue paused';
    case SessionStatus.ended:
      return 'Session ended';
    case SessionStatus.running:
      final serving = day.currentToken == 0 ? '—' : '${token.tokenPrefix}-${day.currentToken}';
      final aheadText = ahead == 0 ? "You're next" : '$ahead ahead';
      return 'Now serving $serving · $aheadText';
  }
}

/// Home banner for an active token (DESIGN S-05).
class ActiveTokenBanner extends ConsumerWidget {
  const ActiveTokenBanner({super.key, required this.token});
  final Token token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctor = ref.watch(doctorProvider(token.doctorId)).value;
    final clinic = ref.watch(clinicProvider(token.clinicId)).value;
    final pos = ref.watch(tokenPositionProvider(token.id)).value;
    final called = token.status == TokenStatus.called;
    final isToday = token.date == dayKey(pktNow());
    final running = pos?.day.sessionStatus == SessionStatus.running;

    return Material(
      color: called ? AppColors.infoContainer : AppColors.primaryContainer,
      borderRadius: BorderRadius.circular(Radii.card + 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/token/${token.id}'),
        child: Stack(
          children: [
            Positioned(
              right: -40,
              top: -40,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withValues(alpha: 0.06)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Gap.lg + 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(isToday ? 'ACTIVE TOKEN' : 'UPCOMING TOKEN',
                          style: AppText.overline.copyWith(color: AppColors.primary), overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: Gap.sm),
                    StatusChip(token.status),
                  ]),
                  const SizedBox(height: Gap.xs),
                  Text('Token ${token.label}',
                      style: AppText.displaySmall.copyWith(color: called ? AppColors.info : AppColors.primary, fontWeight: FontWeight.w800, fontSize: 34)),
                  const SizedBox(height: 2),
                  Text('${doctor?.name ?? ''} · ${clinic?.name ?? ''}', style: AppText.bodyMedium, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: Gap.md),
                  if (isToday && running && !called)
                    Row(children: [
                      Expanded(
                        child: StatTile(
                          label: 'Now serving',
                          value: pos!.day.currentToken == 0 ? '—' : '${token.tokenPrefix}-${pos.day.currentToken}',
                          bg: AppColors.surface,
                          big: false,
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: StatTile(
                          label: 'Ahead of you',
                          value: pos.ahead == 0 ? "You're next" : '${pos.ahead} ahead',
                          bg: AppColors.surface,
                          big: false,
                        ),
                      ),
                    ])
                  else
                    Text(
                      called
                          ? 'Your turn now. Please go to ${doctor?.name ?? 'the doctor'}.'
                          : isToday
                              ? liveLine(token, pos?.day, pos?.ahead ?? 0)
                              : Fmt.relativeDay(token.date),
                      style: AppText.labelLarge.copyWith(color: called ? AppColors.info : AppColors.textPrimary),
                    ),
                  const SizedBox(height: Gap.md),
                  Row(children: [
                    if (isToday && running && !called) ...[
                      const Icon(Icons.schedule_rounded, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Flexible(child: Text('${Fmt.wait(pos!.waitMinutes)} wait', style: AppText.labelMedium)),
                    ],
                    const Spacer(),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      child: const Icon(Icons.arrow_forward_rounded, color: AppColors.onPrimary),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Token row for the Tokens tab and history lists (DESIGN S-12).
class TokenListCard extends ConsumerWidget {
  const TokenListCard({super.key, required this.token});
  final Token token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctor = ref.watch(doctorProvider(token.doctorId)).value;
    final clinic = ref.watch(clinicProvider(token.clinicId)).value;
    // D-27: an active token whose session is over is shown as finished.
    final active = ref.watch(tokenIsLiveProvider)(token);
    final sessionOver = token.status.isActive && !active;
    final isToday = token.date == dayKey(pktNow());
    final pos = active && isToday ? ref.watch(tokenPositionProvider(token.id)).value : null;
    final (tileBg, tileFg) = sessionOver ? (AppColors.muted, AppColors.textSecondary) : switch (token.status) {
      TokenStatus.booked || TokenStatus.onHold => (AppColors.primaryContainer, AppColors.primary),
      TokenStatus.arrived || TokenStatus.called => (AppColors.avatarCool, AppColors.secondary),
      _ => (AppColors.muted, AppColors.textSecondary),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: AppCard(
        onTap: () => context.push('/token/${token.id}'),
        padding: const EdgeInsets.all(Gap.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              padding: const EdgeInsets.symmetric(vertical: Gap.md),
              decoration: BoxDecoration(color: tileBg, borderRadius: BorderRadius.circular(Radii.button)),
              child: Column(children: [
                if (active) Text('TOKEN', style: AppText.overline.copyWith(fontSize: 9, color: tileFg)),
                FittedBox(
                  child: Text(token.label, style: AppText.titleLarge.copyWith(color: tileFg, fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(token.patientSnapshot.name,
                          style: AppText.titleMedium.copyWith(fontSize: 16), overflow: TextOverflow.ellipsis),
                    ),
                    if (sessionOver)
                      const Pill(label: 'Session over', fg: AppColors.textSecondary, bg: AppColors.muted, dot: true)
                    else
                      StatusChip(token.status),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    active ? (doctor?.name ?? '') : '${doctor?.name ?? ''} · ${clinic?.name ?? ''}',
                    style: AppText.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    active
                        ? '${clinic?.name ?? ''} · ${Fmt.relativeDay(token.date)}'
                        : [
                            Fmt.shortDay(token.date),
                            if (token.status == TokenStatus.completed && token.waitedMinutes != null)
                              'Waited ${token.waitedMinutes} min',
                          ].join(' · '),
                    style: AppText.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (pos != null) ...[
                    const SizedBox(height: Gap.xs),
                    Row(children: [
                      Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(liveLine(token, pos.day, pos.ahead),
                            style: AppText.labelSmall.copyWith(color: AppColors.success, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
