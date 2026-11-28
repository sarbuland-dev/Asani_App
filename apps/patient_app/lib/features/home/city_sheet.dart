import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

/// The only city Asani is live in for now (PRD D-64).
const kLiveCity = 'Lahore';

/// City sheet (board P12, D-64): Asani is in Lahore only for now. Opens from
/// the city pill on Home, in Search and from Account. "Got it" moves an older
/// account that still has another city back to Lahore.
Future<void> showCitySheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true, // above the floating nav bar
    isScrollControlled: true,
    showDragHandle: false, // drawn on the picture (board P12)
    backgroundColor: AppColors.background,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.header))),
    builder: (ctx) => const _CitySheet(),
  );
  if (ref.read(selectedCityProvider) != kLiveCity) {
    try {
      await ref.read(authRepositoryProvider).setCity(kLiveCity);
    } catch (_) {
      // Offline: the city stays as it is; the sheet opens again next time.
    }
  }
}

class _CitySheet extends StatelessWidget {
  const _CitySheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      // Scrolls only when it can't fit (small phone with large text).
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(children: [
              const ExcludeSemantics(child: AspectRatio(aspectRatio: 390 / 150, child: CustomPaint(painter: _LahoreSkyline()))),
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(color: AppColors.onPrimary.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl - 2, Gap.xl - 4, Gap.xl - 2, Gap.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _LiveChip(),
                  const SizedBox(height: Gap.md),
                  Text('Asani is in Lahore for now', style: AppText.titleLarge.copyWith(fontSize: 25, fontWeight: FontWeight.w800)),
                  const SizedBox(height: Gap.sm),
                  Text('You can find and book tokens at clinics in Lahore. More cities are on the way.',
                      style: AppText.bodyMedium.copyWith(fontSize: 15, height: 1.5)),
                  const SizedBox(height: Gap.lg),
                  const _CityCard(),
                  const SizedBox(height: Gap.lg),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Got it')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveChip extends StatefulWidget {
  const _LiveChip();

  @override
  State<_LiveChip> createState() => _LiveChipState();
}

class _LiveChipState extends State<_LiveChip> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: Gap.md),
      decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(Radii.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 16,
          height: 16,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Stack(alignment: Alignment.center, children: [
              if (_c.isAnimating)
                Transform.scale(
                  scale: 0.5 + _c.value * 1.1,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.8 * (1 - _c.value)), width: 2),
                    ),
                  ),
                ),
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
            ]),
          ),
        ),
        const SizedBox(width: 6),
        Text('Live now', style: AppText.labelMedium.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
      ]),
    );
  }
}

class _CityCard extends StatelessWidget {
  const _CityCard();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Lahore, selected. All clinics on Asani.',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(Radii.card)),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.primaryMid, borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.location_on_outlined, color: AppColors.primarySoft, size: 22),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kLiveCity, style: AppText.titleSmall.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700)),
                Text('All clinics on Asani', style: AppText.labelSmall.copyWith(color: AppColors.onPrimaryMuted)),
              ]),
            ),
            Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(color: AppColors.cream, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, size: 16, color: AppColors.primary),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Lahore at sunset (board P12): Badshahi Mosque, Minar-e-Pakistan, houses.
/// Drawn in a 390 x 150 box. These sunset colours are an illustration-only
/// exception to the forest + cream palette (D-64); nothing else uses them.
class _LahoreSkyline extends CustomPainter {
  const _LahoreSkyline();

  static const _skyTop = Color(0xFF2E3A6E);
  static const _skyMid = Color(0xFF8E4F8C);
  static const _skyLow = Color(0xFFE8806A);
  static const _skyEdge = Color(0xFFF7C873);
  static const _sunGlow = Color(0xFFFFD27A);
  static const _sunTop = Color(0xFFFFE7A3);
  static const _sunLow = Color(0xFFF59E4B);
  static const _cloud = Color(0xFFFBD3C0);
  static const _sandstone = Color(0xFFB5523B);
  static const _sandstoneDark = Color(0xFF8E3B2A);
  static const _marble = Color(0xFFFFF7EC);
  static const _minarShade = Color(0xFFE6DCCB);
  static const _baseTop = Color(0xFFE9DCC6);
  static const _baseLow = Color(0xFFD9C7A8);
  static const _houses = Color(0xFFC77E4A);
  static const _housesTop = Color(0xFFE8A15E);
  static const _window = Color(0xFFFFE3A3);
  static const _tree = Color(0xFF3E8E5E);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 390;
    canvas.save();
    canvas.scale(s, size.height / 150);
    final p = Paint();
    const box = Rect.fromLTWH(0, 0, 390, 150);

    p.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [_skyTop, _skyMid, _skyLow, _skyEdge],
      stops: [0, 0.45, 0.75, 1],
    ).createShader(box);
    canvas.drawRect(box, p);
    p.shader = null;

    p.color = Colors.white.withValues(alpha: 0.7);
    for (final o in const [Offset(40, 16), Offset(96, 10), Offset(150, 24), Offset(250, 12), Offset(350, 20)]) {
      canvas.drawCircle(o, 1.2, p);
    }

    p.color = _sunGlow.withValues(alpha: 0.35);
    canvas.drawCircle(const Offset(300, 92), 30, p);
    p.shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_sunTop, _sunLow])
        .createShader(Rect.fromCircle(center: const Offset(300, 92), radius: 20));
    canvas.drawCircle(const Offset(300, 92), 20, p);
    p.shader = null;

    p.color = _cloud.withValues(alpha: 0.55);
    canvas.drawPath(
        Path()
          ..moveTo(30, 48)
          ..cubicTo(44, 42, 56, 44, 64, 50)
          ..cubicTo(54, 49, 42, 50, 30, 48)
          ..moveTo(250, 40)
          ..cubicTo(262, 35, 274, 37, 280, 42)
          ..cubicTo(271, 41, 260, 42, 250, 40),
        p);

    final bird = Paint()
      ..color = _skyTop
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (final b in const [(220.0, 46.0, 4.0), (240.0, 34.0, 3.0), (120.0, 40.0, 3.0)]) {
      final (x, y, w) = b;
      canvas.drawPath(
          Path()
            ..moveTo(x, y)
            ..quadraticBezierTo(x + w, y - w, x + 2 * w, y)
            ..quadraticBezierTo(x + 3 * w, y - w, x + 4 * w, y),
          bird);
    }

    // Badshahi Mosque.
    p.color = _sandstone;
    canvas.drawRect(const Rect.fromLTWH(14, 80, 8, 70), p);
    canvas.drawRect(const Rect.fromLTWH(132, 80, 8, 70), p);
    canvas.drawRect(const Rect.fromLTWH(22, 104, 110, 46), p);
    p.color = _sandstoneDark;
    canvas.drawRect(const Rect.fromLTWH(22, 104, 110, 5), p);
    for (final a in const [(40.0, 132.0, 5.0), (60.0, 128.0, 6.0), (82.0, 124.0, 8.0), (104.0, 132.0, 5.0)]) {
      final (x, top, r) = a;
      canvas.drawPath(
          Path()
            ..moveTo(x, 150)
            ..lineTo(x, top)
            ..arcToPoint(Offset(x + 2 * r, top), radius: Radius.circular(r))
            ..lineTo(x + 2 * r, 150)
            ..close(),
          p);
    }
    p.color = _marble;
    for (final x in const [12.0, 130.0]) {
      canvas.drawPath(Path()..moveTo(x, 80)..lineTo(x + 12, 80)..lineTo(x + 6, 67)..close(), p);
    }
    for (final d in const [(44.0, 13.0), (62.0, 16.0), (86.0, 13.0)]) {
      final (x, r) = d;
      canvas.drawArc(Rect.fromLTWH(x, 104 - r, 2 * r, 2 * r), 3.14159, 3.14159, true, p);
    }
    canvas.drawRect(const Rect.fromLTWH(76.5, 78, 3, 10), p);

    // Minar-e-Pakistan.
    p.color = Colors.white;
    canvas.drawPath(Path()..moveTo(196, 18)..lineTo(200, 18)..lineTo(207, 114)..lineTo(189, 114)..close(), p);
    canvas.drawPath(Path()..moveTo(189, 22)..lineTo(208, 22)..lineTo(206, 28)..lineTo(191, 28)..close(), p);
    canvas.drawPath(Path()..moveTo(194, 12)..lineTo(203, 12)..lineTo(202, 22)..lineTo(195, 22)..close(), p);
    canvas.drawRect(const Rect.fromLTWH(197, 4, 3, 8), p);
    p.color = _minarShade;
    canvas.drawPath(Path()..moveTo(200, 18)..lineTo(207, 114)..lineTo(200, 114)..close(), p);
    p.color = _baseTop;
    canvas.drawPath(Path()..moveTo(170, 114)..lineTo(226, 114)..lineTo(234, 128)..lineTo(162, 128)..close(), p);
    p.color = _baseLow;
    canvas.drawRect(const Rect.fromLTWH(156, 128, 84, 22), p);

    // Houses with lit windows.
    p.color = _houses;
    canvas.drawRect(const Rect.fromLTWH(250, 112, 140, 38), p);
    p.color = _housesTop;
    canvas.drawRect(const Rect.fromLTWH(268, 96, 30, 16), p);
    canvas.drawRect(const Rect.fromLTWH(320, 102, 40, 10), p);
    p.color = _window;
    for (final w in const [Offset(258, 120), Offset(276, 120), Offset(300, 122), Offset(332, 118), Offset(352, 122)]) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w.dx, w.dy, 6, 7), const Radius.circular(1)), p);
    }
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(276, 101, 5, 6), const Radius.circular(1)), p);

    p.color = _tree;
    for (final t in const [(150.0, 138.0, 9.0), (244.0, 136.0, 10.0), (8.0, 140.0, 9.0), (378.0, 138.0, 9.0)]) {
      final (x, y, r) = t;
      canvas.drawCircle(Offset(x, y), r, p);
    }

    p.shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.primaryLight, AppColors.primary])
        .createShader(const Rect.fromLTWH(0, 130, 390, 20));
    canvas.drawPath(
        Path()
          ..moveTo(0, 150)
          ..lineTo(0, 138)
          ..cubicTo(40, 132, 80, 130, 120, 134)
          ..cubicTo(170, 138, 210, 140, 260, 134)
          ..cubicTo(310, 128, 350, 128, 390, 134)
          ..lineTo(390, 150)
          ..close(),
        p);
    p.shader = null;
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LahoreSkyline old) => false;
}
