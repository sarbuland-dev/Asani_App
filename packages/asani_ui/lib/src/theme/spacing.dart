/// Spacing and radius tokens (DESIGN.md §3.3).
abstract final class Gap {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
  static const screen = 16.0;
}

abstract final class Radii {
  static const card = 18.0;
  static const button = 14.0;
  static const pill = 999.0;
  static const sheet = 24.0;
  static const header = 30.0;
}

/// Minimum tap target (DESIGN.md §3.3).
const double kMinTap = 48;
