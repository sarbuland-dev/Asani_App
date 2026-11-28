import 'dart:math' as math;

import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/config/env.dart';
import '../../core/errors/app_exception.dart';
import '../../core/net/connectivity.dart';
import '../../core/widgets/drawn_map.dart';
import 'package:asani_ui/asani_ui.dart';
import '../../core/utils/launch.dart';
import '../../data/location_service.dart';
import '../../data/providers.dart';
import '../clinic/clinic_card.dart' show clinicInitials;
import '../../core/widgets/dead_end.dart';

/// S-11 live token screen (PRD F-05; boards P5, P5b, P8). Notification target.
/// Three looks: called (blue "Your turn now"), finished (grey visit summary)
/// and live (green header with the numbers, Live queue | Details tabs).
class TokenScreen extends ConsumerStatefulWidget {
  const TokenScreen({super.key, required this.tokenId});
  final String tokenId;

  @override
  ConsumerState<TokenScreen> createState() => _TokenScreenState();
}

class _TokenScreenState extends ConsumerState<TokenScreen> {
  bool _details = false;

  /// True while the cancel request runs: the whole screen shows the loader.
  bool _cancelling = false;

  @override
  Widget build(BuildContext context) {
    final tokenAsync = ref.watch(tokenProvider(widget.tokenId));
    final token = tokenAsync.value;
    if (tokenAsync.isLoading && token == null) return const LoadingScreen(message: 'Loading your token…');
    if (token == null) {
      // A failed load is not the same as a token that does not exist (B8).
      if (tokenAsync.hasError) {
        return LoadErrorScreen(error: tokenAsync.error, onRetry: () => ref.invalidate(tokenProvider(widget.tokenId)));
      }
      return const NotFoundScreen(
          icon: Icons.confirmation_number_outlined, title: 'Token not found', message: 'This token is no longer available.');
    }
    final doctorAsync = ref.watch(doctorProvider(token.doctorId));
    final clinicAsync = ref.watch(clinicProvider(token.clinicId));
    final doctor = doctorAsync.value;
    final clinic = clinicAsync.value;
    if (doctor == null || clinic == null) {
      if (doctorAsync.hasError || clinicAsync.hasError) {
        return LoadErrorScreen(
          error: doctorAsync.error ?? clinicAsync.error,
          onRetry: () {
            ref.invalidate(doctorProvider(token.doctorId));
            ref.invalidate(clinicProvider(token.clinicId));
          },
        );
      }
      return const LoadingScreen(message: 'Loading your token…');
    }

    final status = token.status;
    if (_cancelling) {
      // No going back half-way through a cancel.
      return const PopScope(canPop: false, child: LoadingScreen(message: 'Cancelling your token…'));
    }
    if (status == TokenStatus.called) return _CalledView(token: token, doctor: doctor, clinic: clinic);
    // D-35: Skipped is paused (the clinic can recall it), not finished.
    if (!status.isOpenForPatient) return _FinishedView(token: token, doctor: doctor, clinic: clinic);
    return _liveView(token, doctor, clinic);
  }

  Widget _liveView(Token token, Doctor doctor, Clinic clinic) {
    final pos = ref.watch(tokenPositionProvider(widget.tokenId)).value;
    final settings = ref.watch(settingsProvider).value;
    final status = token.status;
    final isToday = token.date == dayKey(pktNow());
    final session = pos?.day.sessionStatus;
    final skipped = status == TokenStatus.skipped;
    final onHold = status == TokenStatus.onHold;
    final queueOn = isToday && (session == SessionStatus.running || session == SessionStatus.paused);
    final s = token.patientSnapshot;
    final who = s.relation == Relation.self ? s.name : '${s.name} (${s.relation.label})';
    final schedule = doctor.scheduleOn(parseDayKey(token.date));

    final (chip, chipBg, chipFg) = skipped
        ? ('Turn passed', AppColors.warningContainer, AppColors.warningText)
        : onHold
            ? ('On hold', AppColors.warningContainer, AppColors.warningText)
            : !isToday
                ? (Fmt.shortDay(token.date), AppColors.cream, AppColors.primary)
                : switch (session) {
                    SessionStatus.running => ('● Live', AppColors.cream, AppColors.primary),
                    SessionStatus.paused => ('Paused', AppColors.warningContainer, AppColors.warningText),
                    SessionStatus.ended => ('Ended', AppColors.cream, AppColors.textSecondary),
                    _ => ('Today', AppColors.cream, AppColors.primary),
                  };

    final serving = pos == null || pos.day.currentToken == 0 ? '—' : '${token.tokenPrefix}-${pos.day.currentToken}';
    final ahead = token.isNextUp ? 0 : pos?.ahead;
    final sent = token.notified.length;

    Widget number(String label, String value, {CrossAxisAlignment align = CrossAxisAlignment.start, Color? color}) =>
        Column(crossAxisAlignment: align, children: [
          Text(label, style: AppText.labelSmall.copyWith(color: AppColors.onPrimaryMuted)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: AppText.displaySmall.copyWith(
                    fontSize: 42, height: 1.1, fontWeight: FontWeight.w700, color: color ?? AppColors.onPrimary)),
          ),
        ]);

    final List<Widget> numbers;
    if (queueOn && (skipped || onHold)) {
      numbers = [
        Expanded(child: number('Now serving', serving)),
        Expanded(child: number('Your token', token.label, align: CrossAxisAlignment.end, color: const Color(0xFFFCD9A8))),
      ];
    } else if (queueOn) {
      numbers = [
        Expanded(child: number('Now serving', serving)),
        Expanded(child: number('Ahead of you', ahead == null ? '—' : '$ahead', align: CrossAxisAlignment.center)),
        Expanded(
          child: token.isNextUp
              ? number('Your place', 'Next', align: CrossAxisAlignment.end)
              : number('Est. wait', pos == null ? '—' : _shortWait(pos.waitMinutes), align: CrossAxisAlignment.end),
        ),
      ];
    } else {
      numbers = [
        Expanded(child: number('Your token', token.label)),
        Expanded(
          child: number(isToday ? 'Session' : Fmt.shortDay(token.date), schedule == null ? '—' : Fmt.timeRangeShort(schedule),
              align: CrossAxisAlignment.end),
        ),
      ];
    }

    final online = Env.isDemo || ref.watch(isOnlineProvider);
    final canCancel = token.status.canCancel && token.bookedByUserId != null;

    return StatusBarScrim(
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Column(children: [
          Container(
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, Gap.sm, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const HeaderBackButton(),
                    Expanded(
                      child: Column(children: [
                        Text('Token ${token.label}',
                            style: AppText.labelLarge.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700)),
                        Text('$who · ${isToday ? 'Today' : Fmt.shortDay(token.date)}',
                            style: AppText.labelSmall.copyWith(color: AppColors.onPrimaryMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(Radii.pill)),
                      child: Text(chip, style: AppText.labelSmall.copyWith(color: chipFg, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  Semantics(
                    container: true,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: numbers),
                  ),
                  const SizedBox(height: 14),
                  // One bar per queue alert; filled = already sent (max 4 per token).
                  Semantics(
                    label: '$sent of 4 queue alerts sent',
                    child: Row(children: [
                      for (var i = 0; i < 4; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        Expanded(
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: i < sent ? AppColors.cream : AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(height: Gap.sm),
                  Row(children: [
                    _tab('Live queue', !_details, () => setState(() => _details = false)),
                    _tab('Details', _details, () => setState(() => _details = true)),
                  ]),
                ]),
              ),
            ),
          ),
          Expanded(
            child: _details
                ? _DetailsTab(token: token, doctor: doctor, clinic: clinic)
                : ListView(padding: const EdgeInsets.only(bottom: Gap.lg), children: [
                    if (skipped && isToday) const _SkippedCard(),
                    if (onHold && isToday) const _OnHoldCard(),
                    if (token.isNextUp) _NextUpCard(checkedInAt: token.priorityAt),
                    if (isToday && !skipped && !onHold && !token.isNextUp) ..._sessionNotice(session, doctor),
                    if (!isToday)
                      _note(Icons.event_available_outlined,
                          'Booked for ${Fmt.relativeDay(token.date)}${schedule == null ? '' : ', session ${Fmt.timeRange(schedule)}'}. '
                          'The live queue shows here on that day.'),
                    _ClinicRow(clinic: clinic, doctor: doctor),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, Gap.md, 20, 0),
                      child: GestureDetector(
                        onTap: () => openDirections(context, clinic),
                        child: DrawnMap(label: clinic.name.split(' ').first),
                      ),
                    ),
                    _ReceptionCard(token: token, skipped: skipped, nextUp: token.isNextUp),
                    if (settings != null && !settings.notificationsAllowed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, Gap.md, 20, 0),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                          decoration: BoxDecoration(color: AppColors.warningContainer, borderRadius: BorderRadius.circular(12)),
                          child: Row(children: [
                            Expanded(
                              child: Text('Notifications are off. You might miss your turn.',
                                  style: AppText.labelSmall.copyWith(color: AppColors.warningText, fontSize: 13)),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(foregroundColor: AppColors.warningText),
                              onPressed: () => context.push('/notifications'),
                              child: const Text('Turn on'),
                            ),
                          ]),
                        ),
                      ),
                  ]),
          ),
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, Gap.md, 20, Gap.lg),
                child: Row(children: [
                  // Walk-ins made at reception have no booker; only the clinic can cancel them (D-22).
                  if (canCancel) ...[
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          foregroundColor: AppColors.danger,
                        ),
                        // Cancelling needs internet (ARCHITECTURE.md §8).
                        onPressed: online ? () => _cancel(context, token) : null,
                        child: Text(online ? 'Cancel token' : 'Needs internet', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: () => callNumber(context, clinic.phone),
                      child: const Text('Call clinic'),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  String _shortWait(int minutes) => minutes < 60 ? '${minutes}m' : '${minutes ~/ 60}h${minutes % 60 == 0 ? '' : ' ${minutes % 60}m'}';

  Widget _tab(String label, bool on, VoidCallback onTap) => Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: on ? AppColors.onPrimary : Colors.transparent, width: 3)),
              ),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: AppText.labelMedium.copyWith(
                      color: on ? AppColors.onPrimary : AppColors.primarySoft, fontWeight: on ? FontWeight.w700 : FontWeight.w600)),
            ),
          ),
        ),
      );

  List<Widget> _sessionNotice(SessionStatus? session, Doctor doctor) {
    final text = switch (session) {
      SessionStatus.notStarted => () {
          final s = doctor.scheduleOn(pktNow());
          return "Doctor hasn't started yet.${s == null ? '' : ' Session starts at ${Fmt.time(s.start)}.'}";
        }(),
      SessionStatus.paused => 'Queue is paused for a moment.',
      SessionStatus.ended => 'Session ended.',
      _ => null,
    };
    return text == null ? const [] : [_note(Icons.info_outline_rounded, text)];
  }

  Widget _note(IconData icon, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, Gap.md, 20, 0),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: Gap.sm),
            Expanded(child: Text(text, style: AppText.labelSmall.copyWith(color: AppColors.textPrimary, fontSize: 13, height: 1.45))),
          ]),
        ),
      );

  Future<void> _cancel(BuildContext context, Token token) async {
    final ok = await confirmDialog(
      context,
      title: 'Cancel token ${token.label}?',
      message: 'Your place in the queue will be given up. This cannot be undone.',
      confirmLabel: 'Cancel token',
      cancelLabel: 'Keep it',
      danger: true,
    );
    if (!ok || !mounted) return;
    // The function can take a few seconds; don't leave the user guessing (DESIGN.md
    // principle 4): the full-screen logo loader over a blurred screen (D-36).
    setState(() => _cancelling = true);
    try {
      await ref.read(tokenRepositoryProvider).cancelToken(token.id);
      if (context.mounted) showSnack(context, 'Token ${token.label} cancelled.');
    } catch (e) {
      if (context.mounted) showSnack(context, AppException.messageOf(e));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }
}

/// Clinic tile, name, distance and doctor, with a directions button.
class _ClinicRow extends ConsumerWidget {
  const _ClinicRow({required this.clinic, required this.doctor});
  final Clinic clinic;
  final Doctor doctor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(userLocationProvider).value;
    final km = me == null || clinic.location == null ? null : distanceKm(me, clinic.location!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, Gap.lg, 20, 0),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(12)),
          child: Text(clinicInitials(clinic.name), style: AppText.labelMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(clinic.name, style: AppText.labelLarge.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
            Text('${km == null ? clinic.area : '${km.toStringAsFixed(1)} km'} · ${doctor.name}',
                style: AppText.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        Semantics(
          button: true,
          label: 'Directions',
          excludeSemantics: true,
          child: Material(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => openDirections(context, clinic),
              child: const SizedBox.square(dimension: 42, child: Icon(Icons.near_me_outlined, size: 18, color: AppColors.onPrimary)),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Board P5 "At reception": ticket tile, the instruction, the big code and
/// Show slip. After a skip it says the same; once checked in again it says
/// to stay near the room (board P8).
class _ReceptionCard extends StatelessWidget {
  const _ReceptionCard({required this.token, required this.skipped, required this.nextUp});
  final Token token;
  final bool skipped;
  final bool nextUp;

  @override
  Widget build(BuildContext context) {
    final (title, sub) = nextUp
        ? ('Stay near the room', 'We\'ll notify you: "Your turn now"')
        : skipped
            ? ('At reception', 'Show this token at the counter')
            : ('At reception', 'When you arrive, show this token at the counter');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.confirmation_number_outlined, size: 26, color: AppColors.onPrimary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: AppText.labelLarge.copyWith(fontWeight: FontWeight.w700)),
                Text(sub, style: AppText.labelSmall.copyWith(fontSize: 13, height: 1.4)),
              ]),
            ),
            const SizedBox(width: Gap.sm),
            Text(token.label, style: AppText.titleLarge.copyWith(fontSize: 28, color: AppColors.primary, fontWeight: FontWeight.w800)),
          ]),
          if (!nextUp) ...[
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () => context.push('/token/${token.id}/slip'),
              child: const Text('Show slip'),
            ),
          ],
        ]),
      ),
    );
  }
}

/// D-37: amber note while the reception has the token On hold. No push.
class _OnHoldCard extends StatelessWidget {
  const _OnHoldCard();

  @override
  Widget build(BuildContext context) => _amber(
        Icons.pause_circle_outline_rounded,
        "You're on hold",
        "The reception paused your turn. You'll be called when they're ready.",
      );
}

/// D-35 / board P8: amber card while the token is Skipped. The slip stays.
class _SkippedCard extends StatelessWidget {
  const _SkippedCard();

  @override
  Widget build(BuildContext context) => _amber(
        Icons.directions_walk_rounded,
        'Your turn passed',
        "Go to reception. You'll be called right after the patient now with the doctor.",
      );
}

Widget _amber(IconData icon, String title, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.warningContainer, Color(0xFFFDE6C4)]),
          border: Border.all(color: const Color(0xFFF5C98A)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: AppColors.warning, borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, size: 26, color: AppColors.surface),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppText.labelLarge.copyWith(fontSize: 17, color: AppColors.warningText, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(text, style: AppText.bodyMedium.copyWith(color: AppColors.warningText, height: 1.45)),
            ]),
          ),
        ]),
      ),
    );

/// Board P8: checked in again after a skip → called right after the current patient.
class _NextUpCard extends StatelessWidget {
  const _NextUpCard({this.checkedInAt});

  /// D-50: when the skipped patient checked in again (`priorityAt`).
  final DateTime? checkedInAt;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.primaryMid, AppColors.primary]),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.22), blurRadius: 24, offset: const Offset(0, 12))],
          ),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.cream,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.cream.withValues(alpha: 0.16), spreadRadius: 6)],
              ),
              child: const Icon(Icons.campaign_outlined, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("You're next", style: AppText.titleMedium.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700)),
                Text('Called right after the current patient', style: AppText.bodyMedium.copyWith(color: AppColors.onPrimaryMuted)),
                if (checkedInAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Checked in at reception · ${DateFormat('h:mm a').format(checkedInAt!)}',
                        style: AppText.labelSmall.copyWith(color: AppColors.onPrimaryMuted)),
                  ),
              ]),
            ),
          ]),
        ),
      );
}

/// Board P5b Details tab: who / doctor / clinic / date, and the 4 alerts.
class _DetailsTab extends StatelessWidget {
  const _DetailsTab({required this.token, required this.doctor, required this.clinic});
  final Token token;
  final Doctor doctor;
  final Clinic clinic;

  @override
  Widget build(BuildContext context) {
    final s = token.patientSnapshot;
    final age = s.age();
    final schedule = doctor.scheduleOn(parseDayKey(token.date));
    Widget row(IconData icon, String label, String value, {Widget? trailing, bool last = false}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.cream))),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 16, color: AppColors.primary),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: AppText.labelSmall.copyWith(fontSize: 11)),
                Text(value, style: AppText.labelMedium.copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
              ]),
            ),
            ?trailing,
          ]),
        );

    final steps = [
      (QueueStep.threeAhead, '3', '3 patients ahead of you'),
      (QueueStep.twoAhead, '2', '2 patients ahead of you'),
      (QueueStep.oneAhead, '1', "You're next"),
      (QueueStep.called, '✓', 'Your turn now'),
    ];
    final nextIdx = steps.indexWhere((x) => !token.notified.contains(x.$1));

    return ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, Gap.lg), children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)),
        child: Column(children: [
          row(Icons.person_outline_rounded, 'Patient',
              '${s.name}${s.relation == Relation.self ? '' : ' · ${s.relation.label}'}${age == null ? '' : ' · $age ${s.gender.short}'}'),
          row(Icons.medical_services_outlined, 'Doctor', '${doctor.name} · ${doctor.specialityEnum.label}'),
          row(Icons.local_hospital_outlined, 'Clinic', '${clinic.name} · ${clinic.address}'),
          row(
            Icons.calendar_today_outlined,
            'Date and session',
            '${Fmt.shortDay(token.date)}${schedule == null ? '' : ' · ${Fmt.timeRange(schedule)}'}',
            trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Booked', style: AppText.labelSmall.copyWith(fontSize: 11)),
              Text(DateFormat('h:mm a').format(token.createdAt), style: AppText.labelSmall.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
            ]),
            last: true,
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Text('Alerts for this token', style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.textSecondary)),
      const SizedBox(height: Gap.sm),
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)),
        child: Column(children: [
          _TimelineRow(dot: '✓', title: 'Token booked', sub: DateFormat('h:mm a').format(token.createdAt), done: true, line: true),
          for (var i = 0; i < steps.length; i++)
            _TimelineRow(
              dot: steps[i].$2,
              title: steps[i].$3,
              // D-50: "Sent 6:05 PM" when the time is known; a skipped step (N-3) shows "Skipped".
              sub: token.notified.contains(steps[i].$1)
                  ? (token.notifiedAt[steps[i].$1] == null ? 'Skipped' : 'Sent ${DateFormat('h:mm a').format(token.notifiedAt[steps[i].$1]!)}')
                  : (i == nextIdx ? 'Coming next' : null),
              done: token.notified.contains(steps[i].$1),
              next: i == nextIdx,
              line: i < steps.length - 1,
            ),
        ]),
      ),
    ]);
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.dot, required this.title, this.sub, required this.done, this.next = false, required this.line});
  final String dot;
  final String title;
  final String? sub;
  final bool done;
  final bool next;
  final bool line;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = done
        ? (AppColors.primary, AppColors.onPrimary)
        : next
            ? (AppColors.primaryContainer, AppColors.primary)
            : (AppColors.cream, AppColors.textMuted);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 22,
          child: Column(children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                boxShadow: next ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.12), spreadRadius: 4)] : null,
              ),
              child: Text(dot, style: AppText.labelSmall.copyWith(color: fg, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
            if (line) Expanded(child: Container(width: 2, color: done ? AppColors.primary : AppColors.border)),
          ]),
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: AppText.labelMedium.copyWith(
                      fontSize: 13, fontWeight: FontWeight.w700, color: done || next ? AppColors.textPrimary : AppColors.textSecondary)),
              if (sub != null)
                Text(sub!,
                    style: AppText.labelSmall.copyWith(
                        fontSize: 11, color: next ? AppColors.primary : AppColors.textSecondary, fontWeight: next ? FontWeight.w600 : FontWeight.w500)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Board P5 "Your turn": blue screen, the token in pulsing rings, "Your turn
/// now", and a card with the clinic and patient (no Call button: it
/// distracted people at the door). Pulse off with reduce motion.
class _CalledView extends StatefulWidget {
  const _CalledView({required this.token, required this.doctor, required this.clinic});
  final Token token;
  final Doctor doctor;
  final Clinic clinic;

  @override
  State<_CalledView> createState() => _CalledViewState();
}

class _CalledViewState extends State<_CalledView> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.token;
    final s = t.patientSnapshot;
    final who = s.relation == Relation.self ? s.name : '${s.name} (${s.relation.label})';
    return StatusBarScrim(
      color: AppColors.info,
      child: Scaffold(
        backgroundColor: AppColors.info,
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, Gap.sm, 20, 0),
              child: Row(children: [
                const HeaderBackButton(color: AppColors.infoDark),
                Expanded(
                  child: Text('Your token',
                      textAlign: TextAlign.center,
                      style: AppText.labelLarge.copyWith(color: AppColors.surface, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 44),
              ]),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Semantics(
                        label: 'Token ${t.label}. Your turn now. Please go to ${widget.doctor.name}.',
                        child: ExcludeSemantics(
                          child: AnimatedBuilder(
                            animation: _c,
                            builder: (_, child) {
                              final v = Curves.easeInOut.transform(_c.value);
                              final ring = math.min(240.0, box.maxWidth - 48);
                              return Container(
                                width: ring,
                                height: ring,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF1478B0),
                                  boxShadow: [BoxShadow(color: AppColors.surface.withValues(alpha: 0.10 * v), spreadRadius: 14 * v)],
                                ),
                                child: child,
                              );
                            },
                            child: Container(
                              width: 190,
                              height: 190,
                              decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Text('TOKEN', style: AppText.overline.copyWith(color: AppColors.info)),
                                FittedBox(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Text(t.label, style: AppText.tokenDisplay.copyWith(fontSize: 62, color: AppColors.info)),
                                  ),
                                ),
                              ]),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Text('Your turn now', style: AppText.displaySmall.copyWith(color: AppColors.surface, fontSize: 34, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
                        child: Text('Please go to ${widget.doctor.name}.',
                            textAlign: TextAlign.center, style: AppText.bodyLarge.copyWith(color: AppColors.infoContainer, fontSize: 17)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, Gap.xl),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
                child: Row(children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.infoContainer, borderRadius: BorderRadius.circular(12)),
                    child: Text(clinicInitials(widget.clinic.name), style: AppText.labelMedium.copyWith(color: AppColors.info, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.clinic.name, style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700)),
                      Text(who, style: AppText.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Board P5 "Completed": grey header with the date, the token and a status
/// chip; the visit; the visit detail; Share slip / Book again. Cancelled and
/// no-show use the same layout.
class _FinishedView extends ConsumerWidget {
  const _FinishedView({required this.token, required this.doctor, required this.clinic});
  final Token token;
  final Doctor doctor;
  final Clinic clinic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = token.status;
    final s = token.patientSnapshot;
    final completed = status == TokenStatus.completed;
    final (chipText, chipBg, chipFg) = switch (status) {
      TokenStatus.completed => ('COMPLETED', AppColors.cream, AppColors.textSecondary),
      TokenStatus.cancelled => ('CANCELLED', AppColors.dangerContainer, AppColors.dangerText),
      TokenStatus.noShow => ('NO-SHOW', AppColors.dangerContainer, AppColors.dangerText),
      _ => (status.label.toUpperCase(), AppColors.cream, AppColors.textSecondary),
    };
    final followUp = (ref.watch(myFollowUpsProvider).value ?? const <FollowUp>[])
        .where((f) => f.patientId == token.patientId && f.doctorId == token.doctorId && f.dueDate.compareTo(token.date) > 0)
        .firstOrNull;
    Widget row(String label, String value, {Color? color, bool top = false}) => Container(
          padding: EdgeInsets.only(top: top ? 12 : 7, bottom: 7),
          margin: EdgeInsets.only(top: top ? 4 : 0),
          decoration: BoxDecoration(border: top ? const Border(top: BorderSide(color: AppColors.border)) : null),
          child: Row(children: [
            Expanded(child: Text(label, style: AppText.labelSmall.copyWith(fontSize: 14))),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700, color: color ?? AppColors.textPrimary)),
            ),
          ]),
        );
    Widget section(String title, List<Widget> children, {bool border = true}) => Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          decoration: BoxDecoration(border: border ? const Border(bottom: BorderSide(color: AppColors.border)) : null),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            ...children,
          ]),
        );

    return StatusBarScrim(
      color: AppColors.textSecondary,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Column(children: [
          Expanded(
            child: ListView(padding: EdgeInsets.zero, children: [
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.textSecondary,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header)),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, Gap.sm, 20, 22),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        // Board P5 S-11 Completed: lighter grey button on the grey header.
                        const HeaderBackButton(color: AppColors.headerChipGrey),
                        Expanded(
                          child: Text(Fmt.shortDay(token.date),
                              textAlign: TextAlign.center,
                              style: AppText.labelLarge.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 44),
                      ]),
                      const SizedBox(height: 18),
                      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Token', style: AppText.labelSmall.copyWith(color: AppColors.border, fontSize: 13)),
                            Text(token.label,
                                style: AppText.displaySmall.copyWith(color: AppColors.onPrimary, fontSize: 48, fontWeight: FontWeight.w800, height: 1.05)),
                          ]),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(Radii.pill)),
                          child: Text(chipText, style: AppText.labelSmall.copyWith(color: chipFg, fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ]),
                  ),
                ),
              ),
              section('Visit', [
                Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppColors.cream, shape: BoxShape.circle),
                    child: Text(Fmt.initials(s.name), style: AppText.labelMedium.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.name, style: AppText.labelLarge.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
                      Text('${doctor.name} · ${clinic.name}', style: AppText.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ]),
              ]),
              section('Visit detail', border: false, [
                row('Booked at', DateFormat('h:mm a').format(token.createdAt)),
                if (token.calledAt != null) row('Called at', DateFormat('h:mm a').format(token.calledAt!)),
                if (completed && token.waitedMinutes != null) row('You waited', Fmt.wait(token.waitedMinutes!)),
                // D-23: say who cancelled and why.
                if (status == TokenStatus.cancelled)
                  row(
                    'Cancelled',
                    token.cancelledByClinic
                        ? 'By clinic${(token.cancelReason ?? '').trim().isEmpty ? '' : ' · ${token.cancelReason!.trim()}'}'
                        : (token.cancelledAt == null ? 'By you' : 'By you · ${Fmt.dateTime(token.cancelledAt!)}'),
                    color: AppColors.dangerText,
                  ),
                if (followUp != null) row('Follow-up', Fmt.shortDay(followUp.dueDate), color: AppColors.primary, top: true),
              ]),
            ]),
          ),
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, Gap.lg),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: () => context.push('/token/${token.id}/slip?share=1'),
                      child: const Text('Share slip'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: () => context.push('/book/${token.clinicId}/${token.doctorId}?patient=${token.patientId}'),
                      // Shrinks a little on narrow phones instead of cutting the words.
                      child: FittedBox(
                          fit: BoxFit.scaleDown, child: Text(token.cancelledByClinic ? 'Book another day' : 'Book again', maxLines: 1)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
