import 'dart:math' as math;

import '../../core/widgets/clinic_kit.dart';
import 'package:flutter/material.dart';

/// W-01 artwork: a token slip, the patient's phone and the "You're next"
/// alert, floating gently. Still when "reduce motion" is on.
class LoginArt extends StatefulWidget {
  const LoginArt({super.key});

  @override
  State<LoginArt> createState() => _LoginArtState();
}

class _LoginArtState extends State<LoginArt> with SingleTickerProviderStateMixin {
  // 30 s fits whole turns of the 5 s and 6 s loops, so the restart is seamless.
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 30));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _float(double seconds, double period) => -5 * (1 - math.cos(2 * math.pi * seconds / period));

  /// The alert pops in, stays, then fades (6 s loop).
  static double _ping(double seconds) {
    final x = (seconds % 6) / 6;
    if (x < 0.30) return 0;
    if (x < 0.38) return (x - 0.30) / 0.08;
    if (x < 0.85) return 1;
    if (x < 0.95) return 1 - (x - 0.85) / 0.10;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
    return Semantics(
      label: "A token slip and a patient's phone getting the alert",
      child: ExcludeSemantics(
        child: SizedBox(
          width: 360,
          height: 370,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) {
              final t = _c.value * 30;
              final alpha = still ? 1.0 : _ping(t);
              final a = still ? 0.0 : _float(t, 5);
              final b = still ? 0.0 : _float(t + 2, 6);
              return Stack(clipBehavior: Clip.none, children: [
                Positioned(left: 60, top: 90 + a, child: const _Slip()),
                Positioned(left: 200, top: 150 + b, child: const _Phone()),
                Positioned(
                  left: 150,
                  top: 64 + (1 - alpha) * 10,
                  child: Opacity(opacity: alpha.clamp(0, 1), child: const _Alert()),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

Widget _bar(double width, Color color, [double height = 8]) =>
    Container(width: width, height: height, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height)));

class _Slip extends StatelessWidget {
  const _Slip();

  @override
  Widget build(BuildContext context) => Container(
        width: 170,
        height: 230,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            color: ClinicColors.creamDeep,
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
            child: Text('Al-Shifa Clinic', style: AppText.labelSmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('TOKEN', style: ClinicText.caps.copyWith(fontSize: 10)),
              Text('A-11', style: ClinicText.big(48, color: AppColors.primary)),
            ]),
          ),
          const SizedBox(height: 12),
          const TearLine(notch: AppColors.primary),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _bar(96, AppColors.borderStrong, 9),
              const SizedBox(height: 9),
              _bar(130, AppColors.border, 9),
              const SizedBox(height: 9),
              _bar(80, AppColors.border, 9),
            ]),
          ),
        ]),
      );
}

class _Phone extends StatelessWidget {
  const _Phone();

  @override
  Widget build(BuildContext context) => Container(
        width: 120,
        height: 200,
        decoration: BoxDecoration(color: AppColors.primaryMid, borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.cream, width: 4)),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
        child: Column(children: [
          _bar(32, AppColors.cream.withValues(alpha: 0.5), 6),
          const SizedBox(height: 14),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(12)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const AsaniMark(size: 44, color: AppColors.cream),
                const SizedBox(height: 14),
                _bar(56, AppColors.primaryLight, 7),
                const SizedBox(height: 7),
                _bar(40, AppColors.primaryLight, 7),
              ]),
            ),
          ),
        ]),
      );
}

class _Alert extends StatelessWidget {
  const _Alert();

  @override
  Widget build(BuildContext context) => Container(
        width: 200,
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(9)),
            child: const Center(child: AsaniMark(size: 28, color: AppColors.cream)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("You're next", style: AppText.labelSmall.copyWith(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w800, height: 1.3)),
              Text('Token A-11 · Dr. Ayesha', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.labelSmall.copyWith(fontSize: 11, height: 1.3)),
            ]),
          ),
        ]),
      );
}
