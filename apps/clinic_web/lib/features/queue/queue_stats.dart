import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';

/// The four number cards under "Now serving" (W-10).
class QueueStats extends StatelessWidget {
  const QueueStats({super.key, required this.waiting, required this.completed, required this.total, required this.nextUp});

  /// Tokens still waiting (booked, arrived, on hold).
  final List<QueueToken> waiting;
  final List<QueueToken> completed;
  final int total;
  final QueueToken? nextUp;

  @override
  Widget build(BuildContext context) {
    final here = waiting.where((t) => t.status == TokenStatus.arrived).length;
    final onWay = waiting.where((t) => t.status == TokenStatus.booked).length;
    // Completed tokens in the order they were called, for the two small charts.
    final inOrder = [...completed]..sort((a, b) => (a.token.calledAt ?? a.token.createdAt).compareTo(b.token.calledAt ?? b.token.createdAt));
    final waits = [for (final t in inOrder) if (t.waitMinutes != null) t.waitMinutes!.toDouble()];
    final avg = waits.isEmpty ? null : waits.reduce((a, b) => a + b) / waits.length;
    final byHour = <int, int>{};
    for (final t in inOrder) {
      final at = t.token.completedAt ?? t.token.calledAt;
      if (at != null) byHour[at.hour] = (byHour[at.hour] ?? 0) + 1;
    }

    final cards = <Widget>[
      _card(
          'Waiting',
          Icons.people_alt_outlined,
          Text('${waiting.length}', style: ClinicText.big(30)),
          Row(children: [
            if (waiting.isNotEmpty) ...[_faces(), const SizedBox(width: 6)],
            Expanded(
              child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('$here here · $onWay on the way', style: ClinicText.small)),
            ),
          ]),
        ),
      _card(
          'Completed',
          Icons.check_rounded,
          Text.rich(TextSpan(
            text: '${completed.length}',
            style: ClinicText.big(30),
            children: [TextSpan(text: ' / $total', style: AppText.labelMedium.copyWith(color: AppColors.textSecondary))],
          )),
          _Bars([for (final h in (byHour.keys.toList()..sort())) byHour[h]!.toDouble()]),
        ),
      _card(
          'Average wait',
          Icons.timer_outlined,
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(WebFmt.minutes(avg), style: ClinicText.big(30))),
          SizedBox(height: 22, width: double.infinity, child: CustomPaint(painter: _SparkPainter(waits))),
        ),
      _nextCard(),
    ];

    Widget line(List<Widget> items) => IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, card) in items.indexed) ...[if (i > 0) const SizedBox(width: 12), card],
          ]),
        );

    // Beside the token panel on a small screen the four cards make two lines.
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= 640
          ? line(cards)
          : Column(children: [line(cards.sublist(0, 2)), const SizedBox(height: 12), line(cards.sublist(2))]),
    );
  }

  Widget _faces() {
    final shown = waiting.take(3).toList();
    final colors = [(AppColors.primary, AppColors.onPrimary), (AppColors.primaryLight, AppColors.onPrimary), (AppColors.primarySoft, AppColors.navy)];
    return SizedBox(
      width: 22 + (shown.length - 1) * 15,
      height: 22,
      child: Stack(children: [
        for (var i = 0; i < shown.length; i++)
          Positioned(left: i * 15, child: Av(shown[i].token.patientSnapshot.name, size: 22, bg: colors[i].$1, fg: colors[i].$2)),
      ]),
    );
  }

  Widget _card(String label, IconData icon, Widget value, Widget foot) => Expanded(
        child: Panel(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconTile(icon, size: 26),
              const SizedBox(width: 8),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ClinicText.small.copyWith(fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 6),
            value,
            const SizedBox(height: 4),
            foot,
          ]),
        ),
      );

  Widget _nextCard() {
    final t = nextUp;
    final why = t == null
        ? 'No one waiting'
        : t.token.isNextUp
            ? 'Back after skip · arrived'
            : t.status == TokenStatus.arrived
                ? 'Arrived'
                : 'Not arrived yet';
    return Expanded(
      child: Panel(
        radius: 18,
        color: ClinicColors.amberTint,
        borderColor: ClinicColors.amberBorder,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const IconTile(Icons.arrow_forward_rounded, size: 26, bg: AppColors.warning, fg: AppColors.surface),
            const SizedBox(width: 8),
            Text('Next up', style: ClinicText.small.copyWith(fontWeight: FontWeight.w600, color: AppColors.warningText)),
          ]),
          const SizedBox(height: 6),
          FittedBox(fit: BoxFit.scaleDown, child: Text(t?.label ?? '—', style: ClinicText.big(30, color: ClinicColors.amberDeep))),
          const SizedBox(height: 4),
          Text(why, maxLines: 1, overflow: TextOverflow.ellipsis, style: ClinicText.small.copyWith(color: AppColors.warningText)),
        ]),
      ),
    );
  }
}

/// Completed patients per hour.
class _Bars extends StatelessWidget {
  const _Bars(this.values);
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final max = values.fold<double>(0, (a, b) => b > a ? b : a);
    final shown = values.length > 8 ? values.sublist(values.length - 8) : values;
    return SizedBox(
      height: 22,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final v in shown)
          Container(
            width: 12,
            height: 4 + 18 * v / max,
            margin: const EdgeInsets.only(right: 5),
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2)),
          ),
        if (shown.isEmpty) Expanded(child: Container(height: 4, decoration: BoxDecoration(color: ClinicColors.tint, borderRadius: BorderRadius.circular(2)))),
      ]),
    );
  }
}

/// Wait of each completed patient, in call order.
class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values);
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      canvas.drawRect(Rect.fromLTWH(0, size.height - 4, size.width, 4), Paint()..color = ClinicColors.tint);
      return;
    }
    final max = values.reduce((a, b) => a > b ? a : b);
    final min = values.reduce((a, b) => a < b ? a : b);
    final range = max - min == 0 ? 1.0 : max - min;
    final line = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = 2 + (size.height - 4) * (1 - (values[i] - min) / range);
      i == 0 ? line.moveTo(x, y) : line.lineTo(x, y);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = AppColors.primary.withValues(alpha: 0.08));
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values.toString() != values.toString();
}
