import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';

import 'package:asani_ui/asani_ui.dart';

/// Ticket-style token slip, same as the patient app (D-16: the receptionist
/// matches it with the slip on the patient's phone).
class TokenSlip extends StatelessWidget {
  const TokenSlip({super.key, required this.token, required this.clinic, required this.doctor, this.compact = false});
  final Token token;
  final Clinic clinic;
  final Doctor doctor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cancelled = token.status == TokenStatus.cancelled;
    final ink = cancelled ? AppColors.textMuted : AppColors.primary;
    final schedule = doctor.scheduleOn(parseDayKey(token.date));
    final snap = token.patientSnapshot;
    final age = snap.age();

    final slip = ClipPath(
      clipper: _TicketClipper(notchY: compact ? 86 : 150),
      child: Container(
        color: AppColors.surface,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(Gap.lg, compact ? Gap.md : Gap.xl, Gap.lg, Gap.md),
              child: Column(children: [
                if (!compact) ...[
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    AsaniMark(size: 30, color: ink, plusColor: cancelled ? AppColors.textMuted : AppColors.secondary),
                    const SizedBox(width: 4),
                    Text('asani', style: AppText.titleLarge.copyWith(color: ink, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: Gap.md),
                  Text(clinic.name, style: AppText.titleMedium.copyWith(color: cancelled ? AppColors.textMuted : AppColors.textPrimary)),
                  Text(clinic.address, style: AppText.bodyMedium),
                ] else
                  Row(children: [
                    AsaniMark(size: 22, color: ink),
                    const SizedBox(width: 4),
                    Expanded(child: Text(clinic.name, style: AppText.labelMedium, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: Gap.sm),
                    Text(clinic.area, style: AppText.labelSmall),
                  ]),
              ]),
            ),
            _dashedLine(),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Gap.lg, vertical: compact ? Gap.md : Gap.lg),
              child: Column(
                crossAxisAlignment: compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                children: [
                  Text('TOKEN', style: AppText.overline),
                  Text(token.label, style: AppText.tokenDisplay.copyWith(color: ink, fontSize: compact ? 40 : 64)),
                  if (compact)
                    Text('${snap.name}${age == null ? '' : ' · $age / ${snap.gender.short}'}', style: AppText.labelMedium)
                  else ...[
                    Text(doctor.name, style: AppText.titleMedium),
                    Text(doctor.speciality, style: AppText.bodyMedium),
                  ],
                  if (compact)
                    Text(
                        '${Fmt.shortDay(token.date)}${schedule == null ? '' : ' · ${Fmt.timeRange(schedule)}'}',
                        style: AppText.labelSmall),
                ],
              ),
            ),
            if (!compact) ...[
              _dashedLine(),
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.md),
                child: Column(children: [
                  _row('Patient', snap.name),
                  _row('Age / Sex', '${age ?? '—'} / ${snap.gender.short}'),
                  _row('Date', Fmt.longDay(token.date)),
                  if (schedule != null) _row('Timing', Fmt.timeRange(schedule)),
                  _row('Booked', Fmt.dateTime(token.createdAt)),
                ]),
              ),
              _dashedLine(),
              Padding(
                padding: const EdgeInsets.all(Gap.lg),
                child: Row(children: [
                  IconBox(icon: Icons.confirmation_number_outlined, bg: cancelled ? AppColors.muted : AppColors.primaryContainer, fg: ink),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Show this slip at reception', style: AppText.labelLarge),
                      Text('Token ${token.label}', style: AppText.bodyMedium),
                    ]),
                  ),
                ]),
              ),
            ],
            Container(
              width: double.infinity,
              color: AppColors.muted,
              padding: const EdgeInsets.symmetric(vertical: Gap.md),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.call_outlined, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text('Clinic: ${clinic.phone}', style: AppText.labelSmall.copyWith(fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.10), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          slip,
          if (cancelled && !compact)
            Positioned.fill(
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: 0.78,
                  child: FittedBox(
                    child: Transform.rotate(
              angle: -0.32,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.xs),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.danger, width: 4),
                  borderRadius: BorderRadius.circular(Radii.button),
                  color: AppColors.surface.withValues(alpha: 0.75),
                ),
                child: Text('CANCELLED',
                    style: AppText.displaySmall.copyWith(color: AppColors.danger, fontWeight: FontWeight.w900, letterSpacing: 2)),
              ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppText.bodyMedium),
          const SizedBox(width: Gap.md),
          Expanded(child: Text(value, style: AppText.labelMedium, textAlign: TextAlign.right)),
        ]),
      );

  Widget _dashedLine() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
        child: LayoutBuilder(
          builder: (_, c) => Row(
            children: List.generate(
              (c.maxWidth / 9).floor(),
              (_) => Container(width: 5, height: 1.4, margin: const EdgeInsets.only(right: 4), color: AppColors.border),
            ),
          ),
        ),
      );
}

/// Rounded ticket with a half-circle notch on both sides.
class _TicketClipper extends CustomClipper<Path> {
  _TicketClipper({required this.notchY});
  final double notchY;

  @override
  Path getClip(Size size) {
    const r = 10.0;
    final y = notchY.clamp(r * 2, size.height - r * 2);
    final outline = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(Radii.card)));
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, y), radius: r))
      ..addOval(Rect.fromCircle(center: Offset(size.width, y), radius: r));
    return Path.combine(PathOperation.difference, outline, notches);
  }

  @override
  bool shouldReclip(_TicketClipper old) => old.notchY != notchY;
}
