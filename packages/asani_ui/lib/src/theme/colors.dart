import 'package:flutter/material.dart';

/// Colour tokens (DESIGN.md §3.1). Widgets use these, never raw hex values.
/// Palette 3 "Deep forest" (2026-11-21, D-43): only the logo colours,
/// forest green #004741 and cream #F0EDE4, plus status colours.
abstract final class AppColors {
  // ---- forest (logo green)
  static const primary = Color(0xFF004741);
  static const primaryLight = Color(0xFF2C6E66);

  /// Light end of the header gradient; also chips and the active nav tab on
  /// green. Cream text on it stays above 4.5:1.
  static const primaryMid = Color(0xFF0B5A52);

  /// Pale green tint: selected tiles, info strips on white.
  static const primaryContainer = Color(0xFFDCE9E5);

  /// Soft green: back layers of the Home ticket stack, inactive dots on green.
  static const primarySoft = Color(0xFF9FC0B8);

  /// Text and icons on forest: the logo cream.
  static const onPrimary = Color(0xFFF0EDE4);

  /// Muted text on forest (sub-lines in headers).
  static const onPrimaryMuted = Color(0xFFC6D8D2);
  static const secondary = Color(0xFF0B5A52);

  /// Darkest green: the floating nav and clinic card covers.
  static const navy = Color(0xFF00332E);
  static const primaryDeep = Color(0xFF00221F);

  // ---- cream (logo cream) and neutrals
  static const cream = Color(0xFFF0EDE4);
  static const surface = Color(0xFFFFFFFF);
  static const background = Color(0xFFFAF8F3);
  static const textPrimary = Color(0xFF1A2A27);
  static const textSecondary = Color(0xFF5D6B66);

  /// Decoration only (chevrons, dividers). Fails 4.5:1: never use for text.
  static const textMuted = Color(0xFF9AA39F);

  /// Light end of the finished-token header (cream text stays above 4.5:1).
  static const slate = Color(0xFF6B7773);
  static const border = Color(0xFFE3DED1);
  static const borderStrong = Color(0xFFC9C2B0);

  /// Cream fill: cards on white, chips, quiet buttons.
  static const muted = Color(0xFFF0EDE4);

  // ---- status
  static const success = Color(0xFF2F7D4F);
  static const successText = Color(0xFF1E5E3A);
  static const successContainer = Color(0xFFDCEFE3);
  static const warning = Color(0xFFB45309);
  static const warningText = Color(0xFF92400E);
  static const warningContainer = Color(0xFFFEF3E2);
  static const danger = Color(0xFFB91C1C);
  static const dangerText = Color(0xFF991B1B);
  static const dangerContainer = Color(0xFFFDE8E8);

  /// Blue is used only for "Your turn" (called state).
  static const info = Color(0xFF0369A1);
  static const infoDark = Color(0xFF075985);
  static const infoContainer = Color(0xFFE0F2FE);

  // ---- follow-ups (approved exception: lime 400)
  static const lime = Color(0xFF8DAE3A);
  static const limeLight = Color(0xFF9DBB4C);
  static const onLime = Color(0xFF1F3306);
  static const onLimeMuted = Color(0xFF2E4A0A);

  /// Fill for chips and switches with cream text on the green header.
  static const headerChip = Color(0xFF0B5A52);
  static const avatarWarm = Color(0xFFFEF3E2);
  static const avatarCool = Color(0xFFDCE9E5);

  /// Header gradient used across screens: almost flat forest.
  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryMid, primary],
  );

  /// Card covers (clinic cards) and dark tickets.
  static const coverGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDeep, navy, primaryMid],
    stops: [0, 0.65, 1],
  );

  /// Follow-up cards.
  static const limeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [lime, limeLight],
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
