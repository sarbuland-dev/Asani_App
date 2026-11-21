import 'dart:async';

import 'package:flutter/material.dart';

import 'package:asani_ui/asani_ui.dart';

import '../../core/router/app_router.dart' show splashMinDuration;

/// S-01 (PRD D-25): logo, name and tagline on the brand green,
/// shown about 1.5 s on every launch. A spinner appears only if loading
/// takes longer than that; after 10 s it also says to check the internet.
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
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.primary),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AsaniLogoTile(size: 96),
                const SizedBox(height: Gap.lg),
                Text('asani', style: AppText.displaySmall.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w800)),
                const SizedBox(height: Gap.sm),
                Text(
                  'Book your clinic token without the long wait.',
                  textAlign: TextAlign.center,
                  style: AppText.bodyLarge.copyWith(color: AppColors.primaryContainer),
                ),
                const SizedBox(height: Gap.xl),
                // Same height either way, so the logo never jumps.
                SizedBox.square(
                  dimension: 24,
                  child: _showSpinner ? const AsaniLoader(size: 24, color: AppColors.onPrimary) : null,
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
        ),
      ),
    );
  }
}
