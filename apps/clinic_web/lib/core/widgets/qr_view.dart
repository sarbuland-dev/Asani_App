import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../theme/app_theme.dart';

/// Draws a QR code (clinic standee preview, slip QR).
class QrView extends StatelessWidget {
  const QrView({super.key, required this.data, this.size = 120, this.color = AppColors.textPrimary});
  final String data;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _QrPainter(QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M)), color),
      );
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.img, this.color);
  final QrImage img;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final n = img.moduleCount;
    final cell = size.width / n;
    final p = Paint()..color = color;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (img.isDark(y, x)) canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell + 0.3, cell + 0.3), p);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.img != img || old.color != color;
}
