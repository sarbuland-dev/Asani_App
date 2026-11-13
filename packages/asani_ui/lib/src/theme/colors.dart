import 'package:flutter/material.dart';

/// Colour tokens (DESIGN.md §3.1). Widgets use these, never raw hex values.
abstract final class AppColors {
  static const primary = Color(0xFF0F766E);
  static const primaryLight = Color(0xFF14B8A6);
  static const primaryContainer = Color(0xFFCCFBF1);
  static const onPrimary = Color(0xFFFFFFFF);
  static const secondary = Color(0xFF1E3A8A);
  static const surface = Color(0xFFFFFFFF);
  static const background = Color(0xFFF6F8F7);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF475569);
  static const textMuted = Color(0xFF94A3B8);
  static const border = Color(0xFFE2E8F0);
  static const muted = Color(0xFFF1F5F9);
  static const success = Color(0xFF15803D);
  static const successContainer = Color(0xFFDCFCE7);
  static const warning = Color(0xFFB45309);
  static const warningContainer = Color(0xFFFEF3C7);
  static const danger = Color(0xFFB91C1C);
  static const dangerContainer = Color(0xFFFEE2E2);
  static const info = Color(0xFF0369A1);
  static const infoDark = Color(0xFF075985);
  static const infoContainer = Color(0xFFE0F2FE);
  static const navy = Color(0xFF134E4A);
  static const avatarWarm = Color(0xFFFEF3C7);
  static const avatarCool = Color(0xFFE0E7FF);

  /// Header gradient used across screens (UI design).
  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryLight],
  );

  static const calledGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [infoDark, info],
  );
}
