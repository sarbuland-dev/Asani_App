import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

/// Type scale (DESIGN.md §3.2). Font: Inter.
abstract final class AppText {
  static TextStyle _inter(double size, FontWeight weight, {Color color = AppColors.textPrimary, double? height}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color, height: height);

  static TextStyle get tokenDisplay => _inter(72, FontWeight.w800, color: AppColors.primary, height: 1.0);
  static TextStyle get displaySmall => _inter(32, FontWeight.w700, height: 1.1);
  static TextStyle get titleLarge => _inter(22, FontWeight.w700, height: 1.2);
  static TextStyle get titleMedium => _inter(18, FontWeight.w600, height: 1.25);
  static TextStyle get bodyLarge => _inter(16, FontWeight.w400, height: 1.4);
  static TextStyle get bodyMedium => _inter(14, FontWeight.w400, color: AppColors.textSecondary, height: 1.4);
  static TextStyle get labelLarge => _inter(16, FontWeight.w600);
  static TextStyle get labelMedium => _inter(14, FontWeight.w600);
  static TextStyle get labelSmall => _inter(12, FontWeight.w500, color: AppColors.textSecondary);
  static TextStyle get overline =>
      _inter(12, FontWeight.w700, color: AppColors.textSecondary).copyWith(letterSpacing: 1.4);

  static TextTheme textTheme() => GoogleFonts.interTextTheme().copyWith(
        displaySmall: displaySmall,
        titleLarge: titleLarge,
        titleMedium: titleMedium,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        labelLarge: labelLarge,
        labelSmall: labelSmall,
      );
}
