import 'dart:async';

import 'package:flutter/material.dart';

import 'package:asani_ui/asani_ui.dart';

import '../../core/router/app_router.dart' show splashMinDuration;

/// S-01 (PRD D-25, board P1): cream logo tile, name and tagline on the
/// forest green with two faint rings behind, shown about 1.5 s on every
/// launch. The logo loader appears only if loading takes longer than that;
/// after 10 s it also says to check the internet.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _slow = Duration(seconds: 10);
  Timer? _spinnerTimer;
  Timer? _slowTimer;
  bool _showSpinner = false;
  bool _slowNow = false;

  @override
  void initState() {
    super.initState();
    _spinnerTimer = Timer(splashMinDuration, () => setState(() => _showSpinner = true));
    _slowTimer = Timer(_slow, () => setState(() => _slowNow = true));
  }

  @override
  void dispose() {
    _spinnerTimer?.cancel();
    _slowTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget ring(double d) => IgnorePointer(
          child: Container(
            width: d,
            height: d,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.primaryMid)),
          ),
        );
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Decoration only: two thin rings centred a little below the logo.
          Positioned.fill(child: OverflowBox(maxWidth: 520, maxHeight: 520, child: ring(520))),
          ring(360),
          Padding(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AsaniLogoTile(size: 104),
                const SizedBox(height: Gap.lg + 2),
                Text('asani',
                    style: AppText.displaySmall.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w800, fontSize: 40, letterSpacing: -0.8)),
                const SizedBox(height: Gap.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    'Book your clinic token without the long wait.',
                    textAlign: TextAlign.center,
                    style: AppText.bodyLarge.copyWith(color: AppColors.onPrimaryMuted, fontSize: 15),
                  ),
                ),
                const SizedBox(height: Gap.xl),
                // Same height either way, so the logo never jumps.
                SizedBox.square(
                  dimension: 28,
                  child: _showSpinner ? const AsaniLoader(size: 28, color: AppColors.onPrimary) : null,
                ),
                if (_slowNow) ...[
                  const SizedBox(height: Gap.lg),
                  Text(
                    'Still connecting… Please check your internet.',
                    textAlign: TextAlign.center,
                    style: AppText.bodyMedium.copyWith(color: AppColors.onPrimary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
