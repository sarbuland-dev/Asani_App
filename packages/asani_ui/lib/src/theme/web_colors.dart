import 'package:flutter/material.dart';

/// Clinic web colours (D-44): the old "Monochrome green" palette, kept for the
/// clinic web until it is redesigned. The patient app uses [AppColors].
/// Palette 6 "Monochrome green" (2026-11-17): shades of the logo green #004741.
abstract final class WebColors {
  static const primary = Color(0xFF004741);
  static const primaryLight = Color(0xFF3E7D73);

  /// Light end of the header gradient. Dark enough for white text (4.5:1).
  static const primaryMid = Color(0xFF0B5C55);
  static const primaryContainer = Color(0xFFD2E8E1);

  /// Soft mid green: the back layers of the Home ticket stack, inactive dots on green.
  static const primarySoft = Color(0xFF88B6AC);
  static const onPrimary = Color(0xFFFFFFFF);
  static const secondary = Color(0xFF0B5C55);
  static const surface = Color(0xFFFFFFFF);
  static const background = Color(0xFFF2F7F5);
  static const textPrimary = Color(0xFF0C2522);
  static const textSecondary = Color(0xFF4F6662);
  /// Decoration only (chevrons, dividers). Fails 4.5:1: never use for text.
  static const textMuted = Color(0xFF8FA39E);

  /// Light end of the finished-token header (white text stays above 4.5:1).
  static const slate = Color(0xFF66807A);
  static const border = Color(0xFFD9E7E2);
  static const muted = Color(0xFFE4EFEB);
  static const success = Color(0xFF00754F);
  static const successContainer = Color(0xFFD2E8E1);
  static const warning = Color(0xFFB45309);
  static const warningContainer = Color(0xFFFEF3C7);
  static const danger = Color(0xFFB91C1C);
  static const dangerContainer = Color(0xFFFEE2E2);
  static const info = Color(0xFF0369A1);
  static const infoDark = Color(0xFF075985);
  static const infoContainer = Color(0xFFE0F2FE);
  static const navy = Color(0xFF00332E);

  /// Fill for chips and switches with white text on the green header
  /// (white text 7.8:1).
  static const headerChip = Color(0xFF0B5C55);
  static const avatarWarm = Color(0xFFFEF3C7);

  static const avatarCool = Color(0xFFE0E7FF);

  /// Header gradient used across screens (UI design).
  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryMid],
  );

  /// Header of a finished (completed / cancelled) token.
  static const finishedGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [textSecondary, slate],
  );

  static const calledGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [infoDark, info],
  );
}
