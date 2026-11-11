import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

/// S-01: logo on primary while the auth state loads.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.headerGradient),
        child: Center(
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
            ],
          ),
        ),
      ),
    );
  }
}
