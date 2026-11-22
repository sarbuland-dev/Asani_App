import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';

/// Drawn map tile from the screens board (D-43: no map library, no API key):
/// streets, a park, the canal, a dotted route from "You" to the clinic pin
/// (with a soft pulse) and the clinic's name tag. Decoration only; the
/// caller makes it tappable (opens Google Maps).
class DrawnMap extends StatefulWidget {
  const DrawnMap({super.key, required this.label, this.height = 80});
  final String label;
  final double height;

  @override
  State<DrawnMap> createState() => _DrawnMapState();
}

class _DrawnMapState extends State<DrawnMap> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, _) => CustomPaint(painter: _MapPainter(widget.label, _pulse.value)),
            ),
          ),
        ),
      );
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.label, this.t);
  final String label;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // Board art is 340×100, drawn "slice": cover the box, centred.
    const w = 340.0, h = 100.0;
    final s = size.width / w > size.height / h ? size.width / w : size.height / h;
    canvas.save();
    canvas.translate((size.width - w * s) / 2, (size.height - h * s) / 2);
    canvas.scale(s);

    canvas.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFECE8DD));
    final block = Paint()..color = const Color(0xFFE1DBCC);
    for (final r in const [
      Rect.fromLTWH(8, 6, 56, 30),
      Rect.fromLTWH(8, 58, 40, 30),
      Rect.fromLTWH(78, 60, 58, 24),
      Rect.fromLTWH(206, 58, 48, 26),
      Rect.fromLTWH(150, 62, 36, 22),
    ]) {
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), block);
    }
    // Park with trees.
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(268, 56, 66, 40), const Radius.circular(6)),
        Paint()..color = const Color(0xFFCFE3D2));
    final tree = Paint()..color = const Color(0xFFB2D1B9);
    canvas.drawCircle(const Offset(284, 70), 6, tree);
    canvas.drawCircle(const Offset(300, 80), 5, tree);
    canvas.drawCircle(const Offset(318, 68), 6, tree);
    // Canal.
    canvas.drawPath(
        Path()
          ..moveTo(-10, 96)
          ..cubicTo(60, 86, 90, 100, 150, 90)
          ..cubicTo(210, 80, 260, 84, 350, 92),
        Paint()
          ..color = const Color(0xFFBFE3F7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7);
    // Roads.
    Paint road(double width, [Color c = const Color(0xFFFAF8F3)]) => Paint()
      ..color = c
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(0, 48), const Offset(340, 48), road(9));
    canvas.drawLine(const Offset(190, -5), const Offset(190, 105), road(8));
    canvas.drawLine(const Offset(60, 105), const Offset(140, -5), road(6));
    final lane = road(3, const Color(0xFFF5F2EA));
    canvas.drawLine(const Offset(0, 20), const Offset(180, 20), lane);
    canvas.drawLine(const Offset(262, 0), const Offset(262, 48), lane);
    canvas.drawLine(const Offset(70, 48), const Offset(70, 100), lane);
    canvas.drawLine(const Offset(240, 48), const Offset(240, 100), lane);

    // Dotted route from You to the clinic.
    final route = Path()
      ..moveTo(95, 72)
      ..cubicTo(125, 62, 165, 54, 190, 48)
      ..cubicTo(200, 45, 207, 40, 210, 32);
    final dash = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final m in route.computeMetrics()) {
      for (double d = 0; d < m.length; d += 8) {
        canvas.drawPath(m.extractPath(d, d + 4), dash);
      }
    }
    // You.
    canvas.drawCircle(const Offset(95, 72), 6.5, Paint()..color = AppColors.surface);
    canvas.drawCircle(const Offset(95, 72), 4, Paint()..color = AppColors.info);
    _text(canvas, 'You', const Offset(95, 60), 8, AppColors.textPrimary);

    // Pulse under the pin.
    canvas.drawCircle(const Offset(210, 32), 6 + 10 * (t < 0.5 ? t * 2 : (1 - t) * 2),
        Paint()..color = AppColors.primary.withValues(alpha: 0.35 * (1 - t)));
    // Pin.
    canvas.drawPath(
        Path()
          ..moveTo(210, 32)
          ..cubicTo(204, 25, 201, 21, 201, 17)
          ..arcToPoint(const Offset(219, 17), radius: const Radius.circular(9))
          ..cubicTo(219, 21, 216, 25, 210, 32)
          ..close(),
        Paint()..color = AppColors.primary);
    canvas.drawCircle(const Offset(210, 17), 3.5, Paint()..color = AppColors.cream);
    // Name tag.
    final tag = _layout(label, 9, AppColors.cream);
    final tw = tag.width + 16;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(222, 8, tw, 18), const Radius.circular(9)),
        Paint()..color = AppColors.primary);
    tag.paint(canvas, Offset(222 + 8, 17 - tag.height / 2));
    canvas.restore();
  }

  TextPainter _layout(String text, double size, Color color) => TextPainter(
        text: TextSpan(text: text, style: TextStyle(fontFamily: 'Inter', fontSize: size, fontWeight: FontWeight.w700, color: color)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 100);

  void _text(Canvas c, String text, Offset center, double size, Color color) {
    final tp = _layout(text, size, color);
    tp.paint(c, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.t != t || old.label != label;
}
