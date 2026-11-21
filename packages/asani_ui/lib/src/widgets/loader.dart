import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Loading indicator made from the logo "a" (PRD D-36, option A "Draw"):
/// the bowl and then the stem write themselves like a pen, hold, then wipe
/// away, on a 2.4 s loop. Used instead of the plain circular spinner.
///
/// Logo colours only (green on cream, or cream on green): pass `color`.
/// With "reduce motion" on, the mark is shown still.
class AsaniLoader extends StatefulWidget {
  const AsaniLoader({super.key, this.size = 48, this.color = AppColors.primary, this.semanticLabel = 'Loading'});
  final double size;
  final Color color;
  final String semanticLabel;

  @override
  State<AsaniLoader> createState() => _AsaniLoaderState();
}

class _AsaniLoaderState extends State<AsaniLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
    return Semantics(
      label: widget.semanticLabel,
      child: SizedBox.square(
        dimension: widget.size,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => CustomPaint(painter: _DrawPainter(widget.color, still ? null : _c.value)),
          ),
        ),
      ),
    );
  }
}

class _DrawPainter extends CustomPainter {
  _DrawPainter(this.color, this.t);
  final Color color;

  /// Loop position 0..1, or null to draw the whole mark (reduce motion).
  final double? t;

  static const _ease = Cubic(0.65, 0, 0.35, 1);
  static const _deg = math.pi / 180;

  static final Path _bowl = Path()..addArc(Rect.fromCircle(center: const Offset(40, 56), radius: 22), -80 * _deg, -262 * _deg);
  static final Path _stem = Path()
    ..moveTo(62, 34)
    ..lineTo(62, 64)
    ..quadraticBezierTo(62, 80, 75, 74)
    ..lineTo(86, 62);

  /// Visible part (start, end) of a stroke, each 0..1, at loop time [x]:
  /// draws in for 45 %, holds full for 10 %, wipes out for 45 %.
  static (double, double) _window(double x) {
    if (x < 0.45) return (0, _ease.transform(x / 0.45));
    if (x < 0.55) return (0, 1);
    return (_ease.transform((x - 0.55) / 0.45), 1);
  }

  void _stroke(Canvas canvas, Path path, Paint paint, double delay) {
    if (t == null) {
      canvas.drawPath(path, paint);
      return;
    }
    final (a, b) = _window((t! - delay) % 1.0);
    if (b - a <= 0.001) return;
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(a * m.length, b * m.length), paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100);
    canvas.translate(2, -4);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    _stroke(canvas, _bowl, paint, 0);
    // The stem follows the bowl by 0.25 s, like the pen moving on.
    _stroke(canvas, _stem, paint, 0.25 / 2.4);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DrawPainter old) => old.t != t || old.color != color;
}
