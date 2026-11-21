import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/env.dart';
import '../../core/errors/app_exception.dart';
import '../../core/net/connectivity.dart';
import 'package:asani_ui/asani_ui.dart';
import '../../core/utils/launch.dart';
import '../../data/providers.dart';

/// S-11 live token screen (PRD F-05). Notification target.
class TokenScreen extends ConsumerWidget {
  const TokenScreen({super.key, required this.tokenId});
  final String tokenId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokenAsync = ref.watch(tokenProvider(tokenId));
    final token = tokenAsync.value;
    if (tokenAsync.isLoading && token == null) return const Scaffold(body: Center(child: AsaniLoader()));
    if (token == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.confirmation_number_outlined, title: 'Token not found', message: 'This token is no longer available.'),
      );
    }
    final doctor = ref.watch(doctorProvider(token.doctorId)).value;
    final clinic = ref.watch(clinicProvider(token.clinicId)).value;
    final pos = ref.watch(tokenPositionProvider(tokenId)).value;
    final settings = ref.watch(settingsProvider).value;
    if (doctor == null || clinic == null) return const Scaffold(body: Center(child: AsaniLoader()));

    final status = token.status;
    final called = status == TokenStatus.called;
    // D-35: Skipped is paused (the clinic can recall it), not finished.
    final finished = !status.isOpenForPatient;
    final skipped = status == TokenStatus.skipped;
    final isToday = token.date == dayKey(pktNow());
    final session = pos?.day.sessionStatus;
    final live = isToday && !finished && session == SessionStatus.running;
    final relation = token.patientSnapshot.relation == Relation.self ? '' : ' (${token.patientSnapshot.relation.label})';

    return StatusBarScrim(
      color: called ? AppColors.infoDark : (finished ? AppColors.textSecondary : AppColors.primary),
      child: Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ---- header
          GradientHeader(
            gradient: called
                ? AppColors.calledGradient
                : finished
                    ? AppColors.finishedGradient
                    : AppColors.headerGradient,
            padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.md, Gap.screen, 72),
            child: Column(children: [
              Row(children: [
                const HeaderBackButton(),
                const Spacer(),
                if (live || called)
                  Pill(
                    label: called ? 'Called' : 'Live',
                    fg: called ? AppColors.info : AppColors.primary,
                    bg: AppColors.surface,
                    dot: true,
                  ),
              ]),
              const SizedBox(height: Gap.md),
              Text('YOUR TOKEN', style: AppText.overline.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.85))),
              const SizedBox(height: Gap.md),
              _TokenBadge(label: token.label, pulse: called),
              const SizedBox(height: Gap.lg),
              if (called) ...[
                Text('Your turn now', style: AppText.displaySmall.copyWith(color: AppColors.onPrimary)),
                const SizedBox(height: Gap.xs),
                Text('Please go to ${doctor.name}', style: AppText.labelLarge.copyWith(color: AppColors.onPrimary)),
                const SizedBox(height: 2),
                Text('${token.patientSnapshot.name}$relation · ${clinic.name}',
                    textAlign: TextAlign.center, style: AppText.bodyMedium.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.85))),
              ] else ...[
                Text('${token.patientSnapshot.name}$relation',
                    textAlign: TextAlign.center, style: AppText.titleMedium.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${doctor.name} · ${clinic.name}',
                    textAlign: TextAlign.center, style: AppText.bodyMedium.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.9))),
                // A finished token shows its date in the card below instead.
                if (!finished) ...[
                const SizedBox(height: Gap.md),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 6),
                  decoration: BoxDecoration(
                      color: AppColors.headerChip, borderRadius: BorderRadius.circular(Radii.pill)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.onPrimary),
                    const SizedBox(width: 6),
                    Text(Fmt.relativeDay(token.date), style: AppText.labelMedium.copyWith(color: AppColors.onPrimary)),
                  ]),
                ),
                ],
              ],
            ]),
          ),
          // ---- body card overlapping the header
          Transform.translate(
            offset: const Offset(0, -48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.screen),
              child: Container(
                padding: const EdgeInsets.all(Gap.lg),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(Radii.card + 4),
                  boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (skipped && isToday) ...[
                      const _SkippedCard(),
                      const SizedBox(height: Gap.md),
                    ],
                    if (!finished && !skipped && isToday) ..._liveSection(token, doctor, pos, session, called),
                    if (!finished && !isToday) ...[
                      _InfoLine(
                        icon: Icons.event_available_outlined,
                        text: 'Booked for ${Fmt.relativeDay(token.date)}'
                            '${doctor.scheduleOn(DateTime.parse(token.date)) == null ? '' : ', session ${Fmt.timeRange(doctor.scheduleOn(DateTime.parse(token.date))!)}'}.'
                            ' The live queue shows here on that day.',
                      ),
                      const SizedBox(height: Gap.md),
                      Align(alignment: Alignment.centerLeft, child: StatusChip(status)),
                      const SizedBox(height: Gap.md),
                    ],
                    if (finished) ...[
                      Row(children: [
                        Expanded(
                          child: Text(
                            switch (status) {
                              TokenStatus.completed => 'Visit completed',
                              // D-23: say who cancelled and why.
                              TokenStatus.cancelled when token.cancelledByClinic =>
                                'Cancelled by clinic${(token.cancelReason ?? '').trim().isEmpty ? '' : ' · ${token.cancelReason!.trim()}'}',
                              TokenStatus.cancelled =>
                                'Cancelled${token.cancelledAt == null ? '' : ' on ${Fmt.dateTime(token.cancelledAt!)}'}',
                              TokenStatus.noShow => 'Marked as no-show',
                              _ => 'This token was skipped',
                            },
                            style: AppText.titleMedium,
                          ),
                        ),
                        StatusChip(status),
                      ]),
                      const SizedBox(height: Gap.xs),
                      Text(
                        token.cancelledByClinic && token.cancelledAt != null
                            ? '${Fmt.longDay(token.date)} · cancelled on ${Fmt.dateTime(token.cancelledAt!)}'
                            : Fmt.longDay(token.date),
                        style: AppText.bodyMedium,
                      ),
                      const SizedBox(height: Gap.lg),
                      FilledButton(
                        onPressed: () => context.push('/book/${token.clinicId}/${token.doctorId}?patient=${token.patientId}'),
                        child: Text(token.cancelledByClinic ? 'Book another day' : 'Book again'),
                      ),                      const SizedBox(height: Gap.md),
                    ],
                    if (!finished && settings != null && !settings.notificationsAllowed) ...[
                      _NotificationsOffCard(onTurnOn: () => context.push('/notifications')),
                      const SizedBox(height: Gap.md),
                    ],
                    if (!finished)
                      AppCard(
                        color: AppColors.background,
                        padding: const EdgeInsets.all(Gap.md),
                        child: Row(children: [
                          const IconBox(icon: Icons.confirmation_number_outlined),
                          const SizedBox(width: Gap.md),
                          Expanded(
                            child: called
                                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('Show this screen at reception', style: AppText.labelLarge),
                                    Text('If you are already inside, go straight to the doctor.', style: AppText.bodyMedium),
                                  ])
                                : Text.rich(TextSpan(style: AppText.labelLarge, children: [
                                    const TextSpan(text: 'Show this screen at reception or tell them your code '),
                                    TextSpan(text: token.label, style: const TextStyle(color: AppColors.primary)),
                                  ])),
                          ),
                        ]),
                      ),
                    const SizedBox(height: Gap.md),
                    // The slip is for reception: not needed once called or finished.
                    if (!called && !finished)
                      Row(children: [
                        Expanded(
                          child: _ActionButton(
                              icon: Icons.download_outlined, label: 'Download slip', onTap: () => context.push('/token/$tokenId/slip')),
                        ),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: _ActionButton(
                              icon: Icons.share_outlined, label: 'Share slip', onTap: () => context.push('/token/$tokenId/slip?share=1')),
                        ),
                      ]),
                    const SizedBox(height: Gap.sm),
                    Row(children: [
                      Expanded(child: _ActionButton(icon: Icons.call_outlined, label: 'Call clinic', onTap: () => callNumber(context, clinic.phone))),
                      const SizedBox(width: Gap.sm),
                      Expanded(child: _ActionButton(icon: Icons.near_me_outlined, label: 'Directions', onTap: () => openDirections(context, clinic))),
                    ]),
                    // Walk-ins made at reception have no booker; only the clinic can cancel them (D-22).
                    if (status.canCancel && token.bookedByUserId != null) ...[
                      const SizedBox(height: Gap.sm),
                      Builder(builder: (context) {
                        // Cancelling needs internet (ARCHITECTURE.md §8).
                        final online = Env.isDemo || ref.watch(isOnlineProvider);
                        return TextButton(
                          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                          onPressed: online ? () => _cancel(context, ref, token) : null,
                          child: Text(online ? 'Cancel token' : 'Cancel token (needs internet)'),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ));
  }

  List<Widget> _liveSection(Token token, Doctor doctor, TokenPosition? pos, SessionStatus? session, bool called) {
    final day = pos?.day;
    final notice = switch (session) {
      SessionStatus.notStarted => () {
          final s = doctor.scheduleOn(pktNow());
          return "Doctor hasn't started yet.${s == null ? '' : ' Session starts at ${Fmt.time(s.start)}.'}";
        }(),
      SessionStatus.paused => 'Queue is paused for a moment.',
      SessionStatus.ended => 'Session ended.',
      _ => null,
    };
    return [
      Row(children: [
        Expanded(
          child: StatTile(
            label: 'Now serving',
            value: day == null || day.currentToken == 0 ? '—' : '${token.tokenPrefix}-${day.currentToken}',
            bg: called ? AppColors.infoContainer : AppColors.primaryContainer,
            fg: called ? AppColors.info : AppColors.primary,
          ),
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: StatTile(
            label: 'Ahead of you',
            value: called || token.isNextUp ? '0' : '${pos?.ahead ?? '—'}',
            bg: called ? AppColors.muted : AppColors.warningContainer,
            fg: called ? AppColors.textPrimary : AppColors.warning,
          ),
        ),
      ]),
      const SizedBox(height: Gap.md),
      if (notice != null) ...[
        _InfoLine(icon: Icons.info_outline_rounded, text: notice),
        const SizedBox(height: Gap.md),
      ],
      // D-35: checked in again after a skip → called right after the current patient.
      if (token.isNextUp && !called) ...[
        const _InfoLine(icon: Icons.campaign_outlined, text: "You're next · called right after the current patient"),
        const SizedBox(height: Gap.md),
      ],
      if (!called && !token.isNextUp)
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Estimated wait', style: AppText.labelSmall),
              Text(pos == null ? '—' : Fmt.wait(pos.waitMinutes), style: AppText.titleLarge),
            ]),
          ),
          StatusChip(token.status),
        ]),
      if (!called && !token.isNextUp) const SizedBox(height: Gap.md),
    ];
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, Token token) async {
    final ok = await confirmDialog(
      context,
      title: 'Cancel token ${token.label}?',
      message: 'Your place in the queue will be given up. This cannot be undone.',
      confirmLabel: 'Cancel token',
      cancelLabel: 'Keep it',
      danger: true,
    );
    if (!ok) return;
    // The function can take a few seconds; don't leave the user guessing (DESIGN.md principle 4).
    if (context.mounted) showSnack(context, 'Cancelling token ${token.label}…');
    try {
      await ref.read(tokenRepositoryProvider).cancelToken(token.id);
      if (context.mounted) showSnack(context, 'Token ${token.label} cancelled.');
    } catch (e) {
      if (context.mounted) showSnack(context, AppException.messageOf(e));
    }
  }
}

/// D-35: amber card while the token is Skipped. The slip stays; no "Book again".
class _SkippedCard extends StatelessWidget {
  const _SkippedCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(color: AppColors.warningContainer, borderRadius: BorderRadius.circular(Radii.card)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.directions_walk_rounded, color: AppColors.warning),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your turn passed · Go to reception', style: AppText.labelLarge.copyWith(color: AppColors.warning)),
            const SizedBox(height: 2),
            Text("You'll be called right after the patient now with the doctor.",
                style: AppText.bodyMedium.copyWith(color: AppColors.warning)),
          ]),
        ),
      ]),
    );
  }
}

/// Big token number in a soft ring; pulses when called (respects reduce motion).
class _TokenBadge extends StatefulWidget {
  const _TokenBadge({required this.label, required this.pulse});
  final String label;
  final bool pulse;

  @override
  State<_TokenBadge> createState() => _TokenBadgeState();
}

class _TokenBadgeState extends State<_TokenBadge> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (widget.pulse && !reduceMotion) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
    }
    final badge = Container(
      width: 220,
      height: 132,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.pulse ? AppColors.surface : AppColors.onPrimary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(80),
        border: Border.all(color: AppColors.onPrimary.withValues(alpha: 0.5), width: 2),
      ),
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
          child: Text(widget.label,
              style: AppText.tokenDisplay.copyWith(color: widget.pulse ? AppColors.info : AppColors.onPrimary)),
        ),
      ),
    );
    return Semantics(
      label: 'Token ${widget.label}',
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Container(
          padding: EdgeInsets.all(8 + 8 * _c.value),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            color: AppColors.onPrimary.withValues(alpha: widget.pulse ? 0.12 + 0.1 * _c.value : 0.08),
          ),
          child: child,
        ),
        child: badge,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.primaryContainer, width: 1.5),
            backgroundColor: AppColors.primaryContainer.withValues(alpha: 0.25),
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
          ),
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: FittedBox(child: Text(label)),
        ),
      );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(color: AppColors.warningContainer, borderRadius: BorderRadius.circular(Radii.button)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: AppColors.warning),
          const SizedBox(width: Gap.sm),
          Expanded(child: Text(text, style: AppText.bodyMedium.copyWith(color: AppColors.textPrimary))),
        ]),
      );
}

class _NotificationsOffCard extends StatelessWidget {
  const _NotificationsOffCard({required this.onTurnOn});
  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(color: AppColors.dangerContainer, borderRadius: BorderRadius.circular(Radii.button)),
        child: Row(children: [
          const Icon(Icons.notifications_off_outlined, color: AppColors.danger),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text('Notifications are off. You might miss your turn.',
                style: AppText.bodyMedium.copyWith(color: AppColors.danger, fontWeight: FontWeight.w500)),
          ),
          TextButton(style: TextButton.styleFrom(foregroundColor: AppColors.danger), onPressed: onTurnOn, child: const Text('Turn on')),
        ]),
      );
}
