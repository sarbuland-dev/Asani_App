import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';

/// Clinic-web-only tokens from the screens board (page "Clinic web"). The
/// shared Deep forest colours are `AppColors` from asani_ui; the Super Admin
/// screens keep the old palette (`WebColors`).
abstract final class ClinicColors {
  /// Page behind the cards.
  static const page = Color(0xFFF5F2EA);

  /// Quiet fill: disabled inputs, schedule columns, loader placeholders.
  static const quiet = Color(0xFFF7F4EC);

  /// Pale green tint: icon tiles, selected rows, info strips.
  static const tint = Color(0xFFE4EEEA);

  /// Darker cream: top of a slip, tile gradients.
  static const creamDeep = Color(0xFFE9E4D7);

  /// Section labels on the dark sidebar.
  static const sideSection = Color(0xFF6F948C);

  /// Light green accent used in the dark hero and art.
  static const sage = Color(0xFF5E9A8F);

  /// "Live" dot.
  static const live = Color(0xFF22C55E);

  /// Amber fill for the "Next up" card.
  static const amberTint = Color(0xFFFFF8EC);
  static const amberTintDeep = Color(0xFFFDEFD6);
  static const amberBorder = Color(0xFFF6DFB4);
  static const amberDeep = Color(0xFF7C2D12);

  /// Chart status colours on dark.
  static const chartAmber = Color(0xFFF59E0B);
  static const chartRed = Color(0xFFF87171);

  // Lime is used only for follow-ups (D-51).
  static const lime = Color(0xFFA3E635);
  static const limeSoft = Color(0xFFD9F99D);
  static const limeTint = Color(0xFFECFCCB);
  static const limeText = Color(0xFF3F6212);
  static const limeInk = Color(0xFF1A2E05);

  /// Dark hero: "Now serving", daily summary, doctor header, login band.
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primaryDeep, AppColors.navy, AppColors.primaryMid],
    stops: [0, 0.55, 1],
  );
}

/// Radii used by the board.
abstract final class ClinicRadii {
  static const control = 12.0;
  static const card = 20.0;
  static const hero = 24.0;
  static const dialog = 28.0;
}

/// Material theme of the clinic screens: Deep forest, 12 px controls.
ThemeData buildClinicTheme() {
  final base = buildDesktopAppTheme();
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(ClinicRadii.control));
  OutlineInputBorder border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(ClinicRadii.control), borderSide: BorderSide(color: c, width: w));
  final label = AppText.labelMedium.copyWith(fontWeight: FontWeight.w700);

  return base.copyWith(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: ClinicColors.tint,
      onPrimaryContainer: AppColors.primary,
      secondary: AppColors.secondary,
      secondaryContainer: ClinicColors.tint,
      surface: AppColors.surface,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: ClinicColors.page,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        disabledBackgroundColor: AppColors.border,
        disabledForegroundColor: AppColors.textMuted,
        minimumSize: const Size(64, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: shape,
        textStyle: label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        backgroundColor: AppColors.surface,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        side: const BorderSide(color: AppColors.border, width: 1.5),
        shape: shape,
        textStyle: label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.primary, minimumSize: const Size(44, 40), shape: shape, textStyle: label),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      hintStyle: AppText.bodyMedium.copyWith(color: AppColors.textSecondary),
      labelStyle: AppText.bodyMedium,
      border: border(AppColors.border),
      enabledBorder: border(AppColors.border),
      disabledBorder: border(AppColors.border),
      focusedBorder: border(AppColors.primary, 1.6),
      errorBorder: border(AppColors.danger),
      focusedErrorBorder: border(AppColors.danger, 1.6),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: 480,
      backgroundColor: AppColors.navy,
      contentTextStyle: AppText.bodyMedium.copyWith(color: AppColors.onPrimary),
      actionTextColor: AppColors.onPrimary,
      shape: shape,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ClinicRadii.dialog)),
    ),
    popupMenuTheme: PopupMenuThemeData(color: AppColors.surface, surfaceTintColor: Colors.transparent, shape: shape),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: ClinicColors.tint,
      side: const BorderSide(color: AppColors.border),
      labelStyle: AppText.labelMedium,
      shape: const StadiumBorder(),
      showCheckmark: false,
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.cream),
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.onPrimary : AppColors.textSecondary),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.borderStrong),
    ),
    datePickerTheme: const DatePickerThemeData(backgroundColor: AppColors.surface, surfaceTintColor: Colors.transparent),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(8)),
      textStyle: AppText.labelSmall.copyWith(color: AppColors.onPrimary),
    ),
  );
}

/// Applies the clinic theme to its subtree. Dialogs opened from inside keep it.
class ClinicThemed extends StatelessWidget {
  const ClinicThemed({super.key, required this.child});
  final Widget child;

  static final _theme = buildClinicTheme();

  @override
  Widget build(BuildContext context) => Theme(data: _theme, child: child);
}
