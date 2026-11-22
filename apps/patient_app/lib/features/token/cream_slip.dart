import 'package:asani_core/asani_core.dart';
import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The cream token slip from the screens board (P5 "Booking done"): clinic
/// and a status chip, the big token code and booking time, a tear line with
/// notches, patient / doctor / date / session, and a green strip with the
/// address and "asani". No QR (board decision).
class CreamSlip extends StatelessWidget {
  const CreamSlip({
    super.key,
    required this.token,
    required this.clinic,
    required this.doctor,
    required this.chip,
    this.notchColor = AppColors.surface,
  });
  final Token token;
  final Clinic clinic;
  final Doctor doctor;

  /// (text, background, foreground) for the status chip.
  final (String, Color, Color) chip;

  /// Colour behind the slip, so the notches look cut out.
  final Color notchColor;

  @override
  Widget build(BuildContext context) {
    final s = token.patientSnapshot;
    final age = s.age();
    final schedule = doctor.scheduleOn(parseDayKey(token.date));
    final (chipText, chipBg, chipFg) = chip;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Text(label, style: AppText.labelSmall.copyWith(fontSize: 13)),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: AppText.labelMedium.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        );

    return Semantics(
      container: true,
      label: 'Token slip. ${clinic.name}. Token ${token.label}. ${s.name}, ${doctor.name}, ${Fmt.shortDay(token.date)}.',
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cream,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.16), blurRadius: 26, offset: const Offset(0, 12))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Text(clinic.name,
                        style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(Radii.pill)),
                    child: Text(chipText, style: AppText.labelSmall.copyWith(color: chipFg, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: Gap.sm),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('TOKEN', style: AppText.overline.copyWith(fontSize: 11, letterSpacing: 1.1)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(token.label, style: AppText.tokenDisplaySmall.copyWith(fontSize: 58, letterSpacing: -1)),
                      ),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('Booked at', style: AppText.labelSmall),
                    Text(DateFormat('h:mm a').format(token.createdAt),
                        style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700)),
                  ]),
                ]),
              ]),
            ),
            // Tear line with notches.
            SizedBox(
              height: 22,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned(
                  left: -11,
                  top: 0,
                  child: Container(width: 22, height: 22, decoration: BoxDecoration(color: notchColor, shape: BoxShape.circle)),
                ),
                Positioned(
                  right: -11,
                  top: 0,
                  child: Container(width: 22, height: 22, decoration: BoxDecoration(color: notchColor, shape: BoxShape.circle)),
                ),
                const Positioned(left: 14, right: 14, top: 10, child: DashedLine(color: AppColors.borderStrong)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
              child: Column(children: [
                row('Patient', '${s.name}${age == null ? '' : ' · $age ${s.gender.short}'}'),
                row('Doctor', doctor.name),
                row('Date', Fmt.shortDay(token.date)),
                if (schedule != null) row('Session', Fmt.timeRange(schedule)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(clinic.address,
                      style: AppText.labelSmall.copyWith(color: AppColors.onPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: Gap.sm),
                Text('asani', style: AppText.labelSmall.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w800)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
