import 'package:flutter/material.dart';

import 'web_colors.dart';
import 'spacing.dart';
import 'typography.dart';

export 'colors.dart';
export 'spacing.dart';
export 'typography.dart';

/// Same brand as the patient app (DESIGN.md §3), adapted for desktop:
/// buttons size to their content instead of filling the width.
ThemeData buildDesktopAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: WebColors.primary,
    primary: WebColors.primary,
    onPrimary: WebColors.onPrimary,
    primaryContainer: WebColors.primaryContainer,
    secondary: WebColors.secondary,
    surface: WebColors.surface,
    error: WebColors.danger,
  );
  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.button));
  OutlineInputBorder border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.button), borderSide: BorderSide(color: c, width: w));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: WebColors.background,
    textTheme: AppText.textTheme(),
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: WebColors.surface,
      foregroundColor: WebColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: AppText.titleLarge,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: WebColors.primary,
        foregroundColor: WebColors.onPrimary,
        disabledBackgroundColor: WebColors.border,
        disabledForegroundColor: WebColors.textMuted,
        minimumSize: const Size(64, kMinTap),
        padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
        shape: const StadiumBorder(),
        textStyle: AppText.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: WebColors.primary,
        minimumSize: const Size(kMinTap, 44),
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
        side: const BorderSide(color: WebColors.primary, width: 1.2),
        shape: const StadiumBorder(),
        textStyle: AppText.labelMedium,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: WebColors.primary,
        minimumSize: const Size(kMinTap, 40),
        shape: buttonShape,
        textStyle: AppText.labelMedium,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: WebColors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 14),
      hintStyle: AppText.bodyLarge.copyWith(color: WebColors.textMuted),
      labelStyle: AppText.bodyMedium,
      border: border(WebColors.border),
      enabledBorder: border(WebColors.border),
      focusedBorder: border(WebColors.primary, 1.6),
      errorBorder: border(WebColors.danger),
      focusedErrorBorder: border(WebColors.danger, 1.6),
    ),
    checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: 480,
      backgroundColor: WebColors.textPrimary,
      contentTextStyle: AppText.bodyMedium.copyWith(color: WebColors.onPrimary),
      actionTextColor: WebColors.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.button)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: WebColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sheet)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: WebColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.button)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: WebColors.surface,
      selectedColor: WebColors.primaryContainer,
      side: const BorderSide(color: WebColors.border),
      labelStyle: AppText.labelMedium,
      shape: const StadiumBorder(),
      showCheckmark: false,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: WebColors.primary,
      unselectedLabelColor: WebColors.textSecondary,
      indicatorColor: WebColors.primary,
      labelStyle: AppText.labelLarge,
      unselectedLabelStyle: AppText.labelLarge,
      dividerColor: WebColors.border,
    ),
    dividerTheme: const DividerThemeData(color: WebColors.border, thickness: 1, space: 1),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: WebColors.textPrimary, borderRadius: BorderRadius.circular(8)),
      textStyle: AppText.labelSmall.copyWith(color: WebColors.onPrimary),
    ),
  );
}
