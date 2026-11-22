import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:asani_ui/asani_ui.dart';
import 'package:asani_core/asani_core.dart';
import '../../data/providers.dart';
import '../token/cream_slip.dart';

/// Booking done (board P5, animation "D"): green header with close and save,
/// a check that pops in and draws its tick, "Token booked", then the cream
/// slip rises over the header edge. Plays once; still with reduce motion.
class BookingSuccessScreen extends ConsumerStatefulWidget {
  const BookingSuccessScreen({super.key, required this.tokenId});
  final String tokenId;

  @override
  ConsumerState<BookingSuccessScreen> createState() => _BookingSuccessScreenState();
}

class _BookingSuccessScreenState extends ConsumerState<BookingSuccessScreen> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _seg(double a, double b, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((_c.value - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final token = ref.watch(tokenProvider(widget.tokenId)).value;
    final doctor = token == null ? null : ref.watch(doctorProvider(token.doctorId)).value;
    final clinic = token == null ? null : ref.watch(clinicProvider(token.clinicId)).value;
    if (token == null || doctor == null || clinic == null) {
      return const LoadingScreen(message: 'Loading your token…');
    }
    final isToday = token.date == dayKey(pktNow());
    final day = ref.watch(queueDayProvider((doctorId: doctor.id, date: token.date))).value;
    final chip = !isToday
        ? (Fmt.shortDay(token.date), AppColors.surface, AppColors.primary)
        : switch (day?.sessionStatus) {
            SessionStatus.running => ('● Live', AppColors.primary, AppColors.onPrimary),
            SessionStatus.paused => ('Paused', AppColors.warningContainer, AppColors.warningText),
            SessionStatus.ended => ('Session ended', AppColors.cream, AppColors.textSecondary),
            _ => ('Not started', AppColors.warningContainer, AppColors.warningText),
          };

    Widget circleButton(IconData icon, String label, VoidCallback onTap) => Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: Material(
            color: AppColors.primaryMid,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox.square(dimension: 44, child: Icon(icon, color: AppColors.onPrimary, size: 20)),
            ),
          ),
        );

    return StatusBarScrim(
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Column(children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final pop = _seg(0, 0.2, Curves.easeOutBack);
                final tick = _seg(0.08, 0.3);
                final title = _seg(0.18, 0.36);
                final slip = _seg(0.3, 0.6, Curves.easeOutBack);
                return ListView(padding: EdgeInsets.zero, children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header)),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, Gap.sm, 20, 70),
                        child: Column(children: [
                          Row(children: [
                            circleButton(Icons.close_rounded, 'Close', () => context.go('/home')),
                            const Spacer(),
                            circleButton(Icons.download_rounded, 'Save slip', () => context.push('/token/${widget.tokenId}/slip')),
                          ]),
                          const SizedBox(height: 4),
                          Transform.scale(
                            scale: pop,
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: AppColors.cream,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: AppColors.cream.withValues(alpha: 0.12), spreadRadius: 8)],
                              ),
                              child: CustomPaint(painter: _TickPainter(tick)),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Opacity(
                            opacity: title,
                            child: Transform.translate(
                              offset: Offset(0, 8 * (1 - title)),
                              child: Column(children: [
                                Text('Token booked',
                                    style: AppText.titleLarge.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Text('Show this slip at reception when you arrive',
                                    textAlign: TextAlign.center, style: AppText.labelSmall.copyWith(color: AppColors.onPrimaryMuted, fontSize: 13)),
                              ]),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(0, -52 + 40 * (1 - slip)),
                    child: Opacity(
                      opacity: slip.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: 0.85 + 0.15 * slip,
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: CreamSlip(token: token, clinic: clinic, doctor: doctor, chip: chip),
                        ),
                      ),
                    ),
                  ),
                ]);
              },
            ),
          ),
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, Gap.lg),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: () => context.push('/token/${widget.tokenId}/slip?share=1'),
                      child: const Text('Share slip'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: () => context.pushReplacement('/token/${widget.tokenId}'),
                      child: const Text('Track token ›'),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The tick inside the check circle, drawn up to [t] (0..1).
class _TickPainter extends CustomPainter {
  _TickPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final s = size.width / 72;
    final path = Path()
      ..moveTo(22 * s, 37 * s)
      ..lineTo(32 * s, 47 * s)
      ..lineTo(51 * s, 27 * s);
    final m = path.computeMetrics().first;
    canvas.drawPath(
      m.extractPath(0, m.length * t),
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.t != t;
}
