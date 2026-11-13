import 'package:flutter/material.dart';

import 'colors.dart';
import 'spacing.dart';
import 'typography.dart';

export 'colors.dart';
export 'spacing.dart';
export 'typography.dart';

/// Same brand as the patient app (DESIGN.md §3), adapted for desktop:
/// buttons size to their content instead of filling the width.
ThemeData buildDesktopAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryContainer,
    secondary: AppColors.secondary,
    surface: AppColors.surface,
    error: AppColors.danger,
  );
  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.button));
  OutlineInputBorder border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.button), borderSide: BorderSide(color: c, width: w));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: AppText.textTheme(),
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: AppText.titleLarge,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        disabledBackgroundColor: AppColors.border,
        disabledForegroundColor: AppColors.textMuted,
        minimumSize: const Size(64, kMinTap),
        padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
        shape: const StadiumBorder(),
        textStyle: AppText.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(kMinTap, 44),
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
        side: const BorderSide(color: AppColors.primary, width: 1.2),
        shape: const StadiumBorder(),
        textStyle: AppText.labelMedium,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(kMinTap, 40),
        shape: buttonShape,
        textStyle: AppText.labelMedium,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 14),
      hintStyle: AppText.bodyLarge.copyWith(color: AppColors.textMuted),
      labelStyle: AppText.bodyMedium,
      border: border(AppColors.border),
      enabledBorder: border(AppColors.border),
      focusedBorder: border(AppColors.primary, 1.6),
      errorBorder: border(AppColors.danger),
      focusedErrorBorder: border(AppColors.danger, 1.6),
    ),
    checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: 480,
      backgroundColor: AppColors.textPrimary,
      contentTextStyle: AppText.bodyMedium.copyWith(color: AppColors.onPrimary),
      actionTextColor: AppColors.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.button)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sheet)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.button)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.primaryContainer,
      side: const BorderSide(color: AppColors.border),
      labelStyle: AppText.labelMedium,
      shape: const StadiumBorder(),
      showCheckmark: false,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.textSecondary,
      indicatorColor: AppColors.primary,
      labelStyle: AppText.labelLarge,
      unselectedLabelStyle: AppText.labelLarge,
      dividerColor: AppColors.border,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.circular(8)),
      textStyle: AppText.labelSmall.copyWith(color: AppColors.onPrimary),
    ),
  );
}
