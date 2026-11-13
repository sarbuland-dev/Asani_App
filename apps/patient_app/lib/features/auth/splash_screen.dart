import 'dart:async';

import 'package:flutter/material.dart';

import 'package:asani_ui/asani_ui.dart';

/// S-01: logo on primary while the auth state loads. If it takes long
/// (no internet on first launch), says so instead of spinning silently.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _slow = Duration(seconds: 10);
  Timer? _timer;
  bool _slowNow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_slow, () => setState(() => _slowNow = true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.headerGradient),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AsaniLogoTile(size: 96),
                const SizedBox(height: Gap.lg),
                Text('asani', style: AppText.displaySmall.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w800)),
                const SizedBox(height: Gap.xl),
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onPrimary),
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
