import 'dart:math' as math;

import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// The dark "Now serving" block of the queue board (W-10): progress ring, the
/// called patient, who comes next, and the queue buttons ([actions]).
class NowServing extends ConsumerWidget {
  const NowServing({
    super.key,
    required this.doctor,
    required this.day,
    required this.called,
    required this.upcoming,
    required this.done,
    required this.total,
    required this.actions,
    required this.onOpenToken,
    this.onFollowUp,
    this.nextUpId,
  });

  final Doctor doctor;
  final QueueDay day;
  final QueueToken? called;

  /// The next waiting tokens in the order Next calls them (up to three).
  final List<QueueToken> upcoming;
  final String? nextUpId;
  final int done;
  final int total;
  final Widget? actions;
  final ValueChanged<QueueToken> onOpenToken;
  final VoidCallback? onFollowUp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = called;
    return HeroBlock(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, header) => Row(children: [
          if (day.sessionStatus == SessionStatus.running) ...[const LiveDot(), const SizedBox(width: 10)],
          Expanded(
            child: Text('NOW SERVING · ${doctor.name.toUpperCase()}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: ClinicText.caps.copyWith(color: AppColors.primarySoft, fontSize: 12)),
          ),
          if (c?.token.calledAt != null) _WithDoctor(since: c!.token.calledAt!),
          if (onFollowUp != null && c != null) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.onPrimary, backgroundColor: AppColors.onPrimary.withValues(alpha: 0.12), shape: const StadiumBorder()),
              onPressed: onFollowUp,
              icon: const Icon(Icons.event_repeat_rounded, size: 16),
              label: Text(header.maxWidth >= 640 ? 'Set follow-up for ${c.label}' : 'Follow-up'),
            ),
          ],
        ])),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, box) {
          final lane = box.maxWidth >= 640 && upcoming.isNotEmpty;
          return Row(children: [
            _Ring(label: c?.label ?? '—', done: done, total: total),
            const SizedBox(width: 22),
            if (lane) SizedBox(width: 180, child: _patient(ref, c)) else Expanded(child: _patient(ref, c)),
            if (lane) Expanded(child: _lane(box.maxWidth - 150 - 22 - 180)),
          ]);
        }),
        if (actions != null) ...[const SizedBox(height: 18), actions!],
      ]),
    );
  }

  Widget _patient(WidgetRef ref, QueueToken? c) {
    if (c == null) {
      return Text(
        day.sessionStatus == SessionStatus.running ? 'Press Next to call a patient' : 'No one called yet',
        style: AppText.titleMedium.copyWith(color: AppColors.onPrimary),
      );
    }
    final s = c.token.patientSnapshot;
    final visits = ref.watch(clinicPatientProvider((c.token.clinicId, c.token.patientId)))?.visits;
    final visit = visits == null ? null : visits.where((v) => v.status == TokenStatus.completed && v.token.date.compareTo(c.token.date) < 0).length + 1;
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onOpenToken(c),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.titleMedium.copyWith(fontSize: 20, color: AppColors.onPrimary)),
          Text('${s.age() ?? '—'} / ${s.gender.short} · ${Fmt.phone(s.phone)}', style: AppText.bodyMedium.copyWith(fontSize: 13, color: AppColors.onPrimaryMuted)),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            CChip.onDark(c.source.label),
            if (visit != null) CChip.onDark(visit == 1 ? 'First visit' : 'Visit $visit'),
          ]),
        ]),
      ),
    );
  }

  Widget _lane(double width) {
    final count = (width / 118).floor().clamp(0, math.min(3, upcoming.length));
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: SizedBox(
        height: 100,
        child: Stack(alignment: Alignment.center, children: [
          Positioned(left: 0, right: 0, child: DashedLine(color: AppColors.onPrimary.withValues(alpha: 0.22))),
          Align(
            alignment: Alignment.centerRight,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < count; i++) _miniSlip(upcoming[i], i),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _miniSlip(QueueToken t, int index) {
    final arrived = t.status == TokenStatus.arrived;
    final nextUp = t.id == nextUpId;
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Opacity(
        opacity: 1 - index * 0.1,
        child: Semantics(
          button: true,
          child: GestureDetector(
            onTap: () => onOpenToken(t),
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 104,
                padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
                decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(14)),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.label, maxLines: 1, style: ClinicText.big(22, color: AppColors.primary)),
                  Text(t.token.patientSnapshot.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ClinicText.small.copyWith(fontSize: 11)),
                  Text(arrived ? '● Arrived' : '○ ${t.status.label}',
                      maxLines: 1,
                      style: ClinicText.small.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: arrived ? AppColors.successText : AppColors.textSecondary)),
                ]),
              ),
              if (nextUp)
                const Positioned(top: -10, left: 10, child: CChip('Next up', fg: AppColors.surface, bg: AppColors.warning, fontSize: 10)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "With doctor · 4 min", counted from the call.
class _WithDoctor extends ConsumerWidget {
  const _WithDoctor({required this.since});
  final DateTime since;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(secondTickerProvider);
    final minutes = pktNow().difference(since).inMinutes;
    return CChip.onDark('With doctor · ${minutes < 0 ? 0 : minutes} min', icon: Icons.schedule_rounded);
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.label, required this.done, required this.total});
  final String label;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 150,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: total == 0 ? 0 : (done / total).clamp(0, 1)),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, value, child) => CustomPaint(painter: _RingPainter(value), child: child),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 108,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(label, key: ValueKey(label), maxLines: 1, style: ClinicText.big(46, color: AppColors.onPrimary)),
                  ),
                ),
              ),
              Text('$done of $total done', style: ClinicText.small.copyWith(fontSize: 11, color: AppColors.primarySoft)),
            ]),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value);
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arc = rect.deflate(13);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = AppColors.onPrimary.withValues(alpha: 0.12);
    canvas.drawArc(arc, 0, math.pi * 2, false, paint);
    if (value > 0) canvas.drawArc(arc, -math.pi / 2, math.pi * 2 * value, false, paint..color = AppColors.onPrimary);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}
