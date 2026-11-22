import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:asani_ui/asani_ui.dart';
import '../../data/providers.dart';

/// "Now serving A-7 · 3 ahead" style live line for a token.
String liveLine(Token token, QueueDay? day, int ahead) {
  if (day == null) return '';
  if (token.status == TokenStatus.called) return 'Your turn now';
  // D-35: Skipped is paused, not finished: the clinic can still call them.
  if (token.status == TokenStatus.skipped) return 'Your turn passed · go to reception';
  if (token.status == TokenStatus.onHold) return "You're on hold · you'll be called when they're ready"; // D-37
  switch (day.sessionStatus) {
    case SessionStatus.notStarted:
      return "Doctor hasn't started yet";
    case SessionStatus.paused:
      return 'Queue paused';
    case SessionStatus.ended:
      return 'Session ended';
    case SessionStatus.running:
      final serving = day.currentToken == 0 ? '—' : '${token.tokenPrefix}-${day.currentToken}';
      final aheadText = token.isNextUp ? "You're next · called right after the current patient" : ahead == 0 ? "You're next" : '$ahead ahead';
      return 'Now serving $serving · $aheadText';
  }
}

/// Home ticket (DESIGN S-05, "ticket stack"): one active token drawn like a
/// paper slip: clinic + status chip, a tear line, then the token code on the
/// left and how far away the turn is on the right.
class TokenTicket extends ConsumerWidget {
  const TokenTicket({super.key, required this.token});
  final Token token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctor = ref.watch(doctorProvider(token.doctorId)).value;
    final clinic = ref.watch(clinicProvider(token.clinicId)).value;
    final pos = ref.watch(tokenPositionProvider(token.id)).value;
    final called = token.status == TokenStatus.called;
    final skipped = token.status == TokenStatus.skipped;
    final isToday = token.date == dayKey(pktNow());
    final session = pos?.day.sessionStatus;
    final running = isToday && session == SessionStatus.running;

    final (chip, chipFg, chipBg, dot) = called
        ? ('Your turn', AppColors.info, AppColors.infoContainer, true)
        : skipped
            ? ('Turn passed', AppColors.warning, AppColors.warningContainer, false)
            : !isToday
            ? (Fmt.shortDay(token.date), AppColors.textSecondary, AppColors.muted, false)
            : switch (session) {
                SessionStatus.running => ('Live', AppColors.primary, AppColors.primaryContainer, true),
                SessionStatus.paused => ('Paused', AppColors.warning, AppColors.warningContainer, false),
                SessionStatus.notStarted => ('Not started', AppColors.textSecondary, AppColors.muted, false),
                _ => ('Today', AppColors.textSecondary, AppColors.muted, false),
              };

    final serving = pos == null || pos.day.currentToken == 0 ? '—' : '${token.tokenPrefix}-${pos.day.currentToken}';
    final String big;
    final String small;
    if (called) {
      big = 'Go in now';
      small = 'Show this at reception';
    } else if (skipped) {
      // D-35: paused, not finished.
      big = 'Go to reception';
      small = "You'll be called after the current patient";
    } else if (running) {
      big = pos!.ahead == 0 ? "You're next" : '${pos.ahead} ahead';
      small = token.isNextUp ? 'Called right after the current patient' : '${Fmt.wait(pos.waitMinutes)} · serving $serving';
    } else if (isToday) {
      big = '';
      small = liveLine(token, pos?.day, pos?.ahead ?? 0);
    } else {
      // A later day: the chip already shows the date.
      big = '';
      small = '';
    }

    final codeColor = called ? AppColors.info : AppColors.primary;
    return Semantics(
      button: true,
      label: 'Token ${token.label} for ${token.patientSnapshot.name} with ${doctor?.name ?? 'the doctor'} '
          'at ${clinic?.name ?? 'the clinic'}. $chip. $big $small',
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card + 2),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/token/${token.id}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.md),
            child: Column(
              // Hug the content: no empty white band under the token code.
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(clinic?.name ?? '', style: AppText.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: Gap.sm),
                  Pill(label: chip, fg: chipFg, bg: chipBg, dot: dot),
                ]),
                const SizedBox(height: Gap.sm),
                const DashedLine(),
                const SizedBox(height: Gap.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          '${token.patientSnapshot.name} · ${doctor?.name ?? ''}',
                          style: AppText.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(token.label,
                            style: AppText.displaySmall.copyWith(color: codeColor, fontWeight: FontWeight.w800, height: 1.05)),
                      ]),
                    ),
                    // Only when there is something to say, so the name keeps the full width otherwise.
                    if (big.isNotEmpty || small.isNotEmpty) ...[
                    const SizedBox(width: Gap.sm),
                    Flexible(
                      flex: 2,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        if (big.isNotEmpty)
                          Text(big, style: AppText.titleMedium.copyWith(color: called ? AppColors.info : AppColors.textPrimary), maxLines: 1),
                        if (small.isNotEmpty)
                          Text(small, style: AppText.bodyMedium, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
                      style: AppText.displaySmall.copyWith(color: called ? AppColors.info : AppColors.primary, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('${doctor?.name ?? ''} · ${clinic?.name ?? ''}', style: AppText.bodyMedium, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: Gap.md),
                  if (isToday && running && !called && token.status != TokenStatus.skipped && token.status != TokenStatus.onHold)
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
                    if (isToday && running && !called && token.status != TokenStatus.skipped && token.status != TokenStatus.onHold) ...[
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

/// Token card for the Tokens tab and history lists (board P6 S-12): the
/// token tile (dark green while live), patient and a status chip, doctor ·
/// clinic · day; then a strip with the live queue (active) or what happened
/// and "Book again" (past).
class TokenListCard extends ConsumerWidget {
  const TokenListCard({super.key, required this.token});
  final Token token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctor = ref.watch(doctorProvider(token.doctorId)).value;
    final clinic = ref.watch(clinicProvider(token.clinicId)).value;
    // D-27: an active token whose session is over is shown as finished.
    final active = ref.watch(tokenIsLiveProvider)(token);
    final sessionOver = token.status.isOpenForPatient && !active;
    final isToday = token.date == dayKey(pktNow());
    final pos = active && isToday ? ref.watch(tokenPositionProvider(token.id)).value : null;
    final status = token.status;
    final live = active && isToday && pos?.day.sessionStatus == SessionStatus.running;
    final cancelled = status == TokenStatus.cancelled;
    final missed = status == TokenStatus.noShow || (status == TokenStatus.skipped && !active);

    final (chipText, chipBg, chipFg) = sessionOver && !missed
        ? ('Session over', AppColors.cream, AppColors.textSecondary)
        : switch (status) {
            TokenStatus.called => ('● Your turn', AppColors.infoContainer, AppColors.info),
            TokenStatus.completed => ('✓ Completed', AppColors.successContainer, AppColors.successText),
            TokenStatus.cancelled => ('Cancelled', AppColors.dangerContainer, AppColors.dangerText),
            TokenStatus.noShow => ('Missed', AppColors.warningContainer, AppColors.warningText),
            TokenStatus.skipped => active
                ? ('Turn passed', AppColors.warningContainer, AppColors.warningText)
                : ('Missed', AppColors.warningContainer, AppColors.warningText),
            TokenStatus.onHold => ('On hold', AppColors.warningContainer, AppColors.warningText),
            _ => live
                ? ('● Live', AppColors.primaryContainer, AppColors.primary)
                : (isToday ? 'Today' : Fmt.shortDay(token.date).replaceAll(',', ''), AppColors.cream, AppColors.textSecondary),
          };

    final day = isToday ? 'Today' : Fmt.shortDay(token.date).replaceAll(',', '');
    final doc = (doctor?.name ?? '').split(' ').take(2).join(' ');
    final sub = '$doc · ${clinic?.name.split(' ').first ?? ''} · $day';

    // Bottom strip.
    Widget? strip;
    if (active && pos != null && (live || status == TokenStatus.skipped || status == TokenStatus.called)) {
      strip = _strip(
        cream: true,
        left: Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Serving '),
            TextSpan(
                text: pos.day.currentToken == 0 ? '—' : '${token.tokenPrefix}-${pos.day.currentToken}',
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
            const TextSpan(text: ' · '),
            TextSpan(
                text: status == TokenStatus.called
                    ? 'your turn'
                    : status == TokenStatus.skipped
                        ? 'go to reception'
                        : (pos.ahead == 0 ? "you're next" : '${pos.ahead} ahead'),
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          ]),
          style: AppText.labelSmall.copyWith(fontSize: 13),
        ),
        action: 'View ›',
        onAction: () => context.push('/token/${token.id}'),
      );
    } else if (!active) {
      final note = switch (status) {
        TokenStatus.completed => token.calledAt == null ? 'Visit completed' : 'Seen at ${DateFormat('h:mm a').format(token.calledAt!)}',
        TokenStatus.cancelled => token.cancelledByClinic
            ? 'Cancelled by clinic${(token.cancelReason ?? '').trim().isEmpty ? '' : ' · ${token.cancelReason!.trim()}'}'
            : 'Cancelled by you',
        _ when missed => 'Not at clinic when called',
        _ => 'Session over',
      };
      strip = _strip(
        cream: false,
        left: Text(note, style: AppText.labelSmall.copyWith(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
        action: cancelled && token.cancelledByClinic ? 'Book another day ›' : (cancelled ? null : 'Book again ›'),
        onAction: () => context.push('/book/${token.clinicId}/${token.doctorId}?patient=${token.patientId}'),
      );
    }

    final tileDark = live || status == TokenStatus.called;
    final tileMuted = cancelled || missed;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Semantics(
        button: true,
        label: 'Token ${token.label}, ${token.patientSnapshot.name}, $sub. ${chipText.replaceAll(RegExp(r'[●✓] '), '')}',
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppColors.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/token/${token.id}'),
            child: ExcludeSemantics(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: tileDark ? (status == TokenStatus.called ? AppColors.info : AppColors.primary) : AppColors.cream,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('TOKEN',
                            style: AppText.overline.copyWith(
                                fontSize: 8, letterSpacing: 0.8, color: tileDark ? AppColors.onPrimaryMuted : AppColors.textSecondary)),
                        FittedBox(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(token.label,
                                style: AppText.titleMedium.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: tileDark ? AppColors.onPrimary : (tileMuted ? AppColors.textMuted : AppColors.primary),
                                  decoration: cancelled ? TextDecoration.lineThrough : null,
                                  decorationColor: AppColors.textMuted,
                                )),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(token.patientSnapshot.name,
                                style: AppText.labelLarge.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(Radii.pill)),
                            child: Text(chipText, style: AppText.labelSmall.copyWith(color: chipFg, fontSize: 11, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                        const SizedBox(height: 2),
                        Text(sub, style: AppText.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                  ]),
                ),
                ?strip,
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _strip({required bool cream, required Widget left, String? action, required VoidCallback onAction}) => Container(
        padding: const EdgeInsets.fromLTRB(14, 9, 6, 9),
        decoration: BoxDecoration(
          color: cream ? AppColors.cream : AppColors.surface,
          border: cream ? null : const Border(top: BorderSide(color: AppColors.cream)),
        ),
        child: Row(children: [
          Expanded(child: left),
          if (action != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(action, style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      );
}
