import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/clinic_kit.dart';

/// Cream ticket the receptionist matches with the slip on the patient's phone
/// (D-16, board W-11 and W-12).
class TokenSlip extends StatelessWidget {
  const TokenSlip({
    super.key,
    required this.token,
    required this.clinic,
    required this.doctor,
    required this.notch,
    this.ribbon,
    this.headerTrailing,
    this.tokenTrailing,
    this.patientNote,
    this.rows = const [],
  });

  final Token token;
  final Clinic clinic;
  final Doctor doctor;

  /// Colour behind the slip, for the two notches.
  final Color notch;

  /// Strip above the slip (check-in result).
  final Widget? ribbon;
  final Widget? headerTrailing;

  /// Right of the big token number.
  final Widget? tokenTrailing;

  /// Second line under the patient's name; defaults to age and gender.
  final String? patientNote;

  /// Extra "label: value" lines.
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final cancelled = token.status == TokenStatus.cancelled;
    final snap = token.patientSnapshot;
    final age = snap.age();
    final note = patientNote ?? '${age ?? '—'} / ${snap.gender.short} · ${Fmt.phone(snap.phone)}';

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: ColoredBox(
        color: AppColors.cream,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ?ribbon,
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [ClinicColors.creamDeep, AppColors.cream]),
            ),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(clinic.name, overflow: TextOverflow.ellipsis, style: AppText.labelMedium.copyWith(fontSize: 13, fontWeight: FontWeight.w700))),
                ?headerTrailing,
              ]),
              const SizedBox(height: 8),
              Text('TOKEN', style: ClinicText.caps),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(token.label,
                        style: ClinicText.big(54, color: cancelled ? AppColors.textSecondary : AppColors.primary)
                            .copyWith(decoration: cancelled ? TextDecoration.lineThrough : null)),
                  ),
                ),
                if (tokenTrailing != null) ...[const SizedBox(width: 8), tokenTrailing!],
              ]),
            ]),
          ),
          TearLine(notch: notch),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Av.solid(snap.name, size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(snap.name, style: AppText.titleSmall.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
                    Text(note, style: ClinicText.small),
                  ]),
                ),
              ]),
              const SizedBox(height: 8),
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: AppText.bodyMedium.copyWith(fontSize: 13)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(value, textAlign: TextAlign.right, style: AppText.labelMedium.copyWith(fontSize: 13))),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
