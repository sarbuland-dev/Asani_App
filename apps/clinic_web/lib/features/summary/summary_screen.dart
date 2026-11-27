import 'dart:async';

import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// W-16 / C-10 daily summary.
class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen(this.clinicId, {super.key});
  final String clinicId;

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  late DateTime _date = parseDayKey(dayKey(pktNow()));
  String? _doctorId;

  /// W-24: an older day is still loading; cards keep their shape and shimmer.
  bool _loading = false;
  Timer? _loadingTimer;

  @override
  void dispose() {
    _loadingTimer?.cancel();
    super.dispose();
  }

  void _pick(DateTime date) {
    setState(() {
      _date = date;
      _loading = false;
    });
    final key = dayKey(date);
    _loadingTimer?.cancel();
    _loadingTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted && dayKey(_date) == key) setState(() => _loading = true);
    });
    ref.read(repositoryProvider).loadTokens(widget.clinicId, key, key).then((_) {}).catchError((_) {}).whenComplete(() {
      if (!mounted || dayKey(_date) != key) return;
      _loadingTimer?.cancel();
      setState(() => _loading = false);
    });
  }

  String _hour(int h) => '${(h + 11) % 12 + 1} ${h < 12 ? 'AM' : 'PM'}';

  /// "7 – 8 PM"
  String _hourRange(int h) => (h < 12) == ((h + 1) % 24 < 12) ? '${(h + 11) % 12 + 1} – ${_hour(h + 1)}' : '${_hour(h)} – ${_hour((h + 1) % 24)}';

  @override
  Widget build(BuildContext context) {
    final doctors = ref.watch(allDoctorsProvider(widget.clinicId));
    final doctorId = _doctorId;
    final key = dayKey(_date);
    final all = ref.watch(tokensOnProvider((widget.clinicId, key)));
    final tokens = doctorId == null ? all : all.where((t) => t.token.doctorId == doctorId).toList();
    final s = DaySummary.of(tokens);
    final doctorName = doctorId == null ? 'All doctors' : doctors.where((d) => d.id == doctorId).firstOrNull?.name ?? 'All doctors';

    return ClinicPage(
      title: 'Daily summary',
      subtitle: 'Pick any day in the last 30 days',
      actions: [_datePicker(key), _doctorPicker(doctors, doctorName)],
      children: _loading
          ? const [Shimmer(height: 230), SizedBox(height: 16), Shimmer(height: 250), SizedBox(height: 16), Shimmer(height: 220)]
          : [
              _hero(s, key, doctorName),
              const SizedBox(height: 16),
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(width: 260, child: _waitTile(s, doctorName)),
                  const SizedBox(width: 16),
                  Expanded(child: _hours(s)),
                ]),
              ),
              if (doctorId == null && doctors.isNotEmpty) ...[const SizedBox(height: 16), _byDoctor(doctors, all)],
            ],
    );
  }

  // --------------------------------------------------------------- pickers

  Widget _datePicker(String key) {
    final today = parseDayKey(dayKey(pktNow()));
    final first = today.subtract(const Duration(days: 30));
    return Panel(
      radius: ClinicRadii.control,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Previous day',
          onPressed: _date.isAfter(first) ? () => _pick(_date.subtract(const Duration(days: 1))) : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        TextButton.icon(
          onPressed: () async {
            final d = await showDatePicker(context: context, firstDate: first, lastDate: today, initialDate: _date);
            if (d != null && mounted) _pick(d);
          },
          icon: _loading ? const AsaniLoader(size: 18) : const Icon(Icons.calendar_today_rounded, size: 16),
          label: Text(Fmt.relativeDay(key), style: const TextStyle(color: AppColors.textPrimary)),
        ),
        IconButton(
          tooltip: 'Next day',
          onPressed: _date.isBefore(today) ? () => _pick(_date.add(const Duration(days: 1))) : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ]),
    );
  }

  Widget _doctorPicker(List<Doctor> doctors, String label) => PopupMenuButton<String>(
        tooltip: 'Choose a doctor',
        onSelected: (v) => setState(() => _doctorId = v.isEmpty ? null : v),
        itemBuilder: (_) => [
          const PopupMenuItem(value: '', child: Text('All doctors')),
          for (final d in doctors) PopupMenuItem(value: d.id, child: Text('${d.name} (${d.tokenPrefix})')),
        ],
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(ClinicRadii.control), border: Border.all(color: AppColors.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.textSecondary),
          ]),
        ),
      );

  // ------------------------------------------------------------------ hero

  Widget _hero(DaySummary s, String key, String doctorName) {
    final open = s.issued - s.completed - s.cancelled - s.noShow;
    final ended = [
      ('Completed', s.completed, AppColors.cream),
      ('Cancelled', s.cancelled, ClinicColors.chartAmber),
      ('No-show', s.noShow, ClinicColors.chartRed),
      if (open > 0) ('Still open', open, ClinicColors.sage),
    ];
    final from = [('App', s.app, AppColors.cream), ('Walk-in', s.walkIn, ClinicColors.sage)];

    Widget zone(String title, List<(String, int, Color)> parts) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: ClinicText.caps.copyWith(color: AppColors.primarySoft, fontSize: 12)),
          const SizedBox(height: 16),
          _stackedBar(parts, 22),
          const SizedBox(height: 18),
          const Spacer(),
          Row(children: [
            for (final (i, part) in parts.indexed) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: _stat(part.$1, part.$2, s.issued, part.$3)),
            ],
          ]),
        ]);

    Widget line() => Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 22), color: AppColors.onPrimary.withValues(alpha: 0.12));

    return HeroBlock(
      radius: 28,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      // A fixed height: the three zones line up and the stat tiles sit at the bottom.
      child: SizedBox(
        height: 180,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 170,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('TOKENS ISSUED', style: ClinicText.caps.copyWith(color: AppColors.primarySoft, fontSize: 12)),
              const SizedBox(height: 8),
              FittedBox(fit: BoxFit.scaleDown, child: Text('${s.issued}', style: ClinicText.big(76, color: AppColors.onPrimary).copyWith(height: 1))),
              const Spacer(),
              Text('${Fmt.shortDay(key)}\n$doctorName', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.bodyMedium.copyWith(fontSize: 13, color: AppColors.onPrimaryMuted)),
            ]),
          ),
          line(),
          Expanded(flex: 3, child: zone('HOW THEY ENDED', ended)),
          line(),
          Expanded(flex: 2, child: zone('WHERE THEY CAME FROM', from)),
        ]),
      ),
    );
  }

  Widget _stackedBar(List<(String, int, Color)> parts, double height) {
    final shown = parts.where((p) => p.$2 > 0).toList();
    if (shown.isEmpty) {
      return Container(height: height, decoration: BoxDecoration(color: AppColors.onPrimary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7)));
    }
    return Row(children: [
      for (final (i, p) in shown.indexed) ...[
        if (i > 0) const SizedBox(width: 4),
        Expanded(
          flex: p.$2,
          child: Tooltip(
            message: '${p.$1}: ${p.$2}',
            child: Container(height: height, decoration: BoxDecoration(color: p.$3, borderRadius: BorderRadius.circular(7))),
          ),
        ),
      ],
    ]);
  }

  Widget _stat(String label, int value, int total, Color color) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: AppColors.onPrimary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.onPrimary.withValues(alpha: 0.1)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ClinicText.small.copyWith(color: AppColors.onPrimaryMuted, fontWeight: FontWeight.w700))),
          ]),
          Text('$value', style: ClinicText.big(28, color: AppColors.onPrimary)),
          Text(total == 0 ? '—' : '${(value * 100 / total).round()}%', style: ClinicText.small.copyWith(color: AppColors.primarySoft)),
        ]),
      );

  // ------------------------------------------------------------ wait, hours

  Widget _waitTile(DaySummary s, String doctorName) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.cream, ClinicColors.creamDeep]),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const IconTile(Icons.timer_outlined),
          const SizedBox(height: 14),
          Text('Average wait', style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(WebFmt.minutes(s.avgWait), style: ClinicText.big(42, color: AppColors.primary))),
          const Spacer(),
          Text('per patient, ${doctorName == 'All doctors' ? 'all doctors' : doctorName}', style: ClinicText.small.copyWith(fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _hours(DaySummary s) {
    final hours = s.byHour.keys.toList()..sort();
    final max = s.byHour.values.fold<int>(0, (a, b) => b > a ? b : a);
    return Panel(
      radius: 22,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('BUSIEST HOUR', style: ClinicText.caps),
              Text(s.busiestHour == null ? '—' : _hourRange(s.busiestHour!), style: ClinicText.big(30, color: AppColors.primary)),
            ]),
          ),
          const IconTile(Icons.local_fire_department_outlined, size: 44),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          height: 150,
          child: hours.isEmpty
              ? Center(child: Text('No tokens on this day.', style: AppText.bodyMedium))
              : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (final h in hours)
                    Expanded(
                      child: Tooltip(
                        message: '${_hour(h)}: ${s.byHour[h]} patients',
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          Text('${s.byHour[h]}',
                              style: AppText.labelSmall.copyWith(fontWeight: FontWeight.w800, color: h == s.busiestHour ? AppColors.primary : AppColors.textPrimary)),
                          const SizedBox(height: 6),
                          Container(
                            width: 40,
                            height: 90 * s.byHour[h]! / max,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: h == s.busiestHour ? AppColors.primary : ClinicColors.tint,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(10), bottom: Radius.circular(4)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(_hour(h),
                                style: AppText.labelSmall.copyWith(
                                    fontWeight: h == s.busiestHour ? FontWeight.w800 : FontWeight.w600,
                                    color: h == s.busiestHour ? AppColors.primary : AppColors.textSecondary)),
                          ),
                        ]),
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }

  // -------------------------------------------------------------- by doctor

  static const _flex = [16, 7, 7, 7, 7, 7, 7, 9];

  Widget _line(List<Widget> cells) => Row(children: [
        for (var i = 0; i < cells.length; i++)
          Expanded(flex: _flex[i], child: i == 0 ? cells[i] : Center(child: cells[i])),
      ]);

  Widget _byDoctor(List<Doctor> doctors, List<QueueToken> all) => Panel(
        radius: 22,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('By doctor', style: ClinicText.cardTitle),
          const SizedBox(height: 14),
          _line([
            Align(alignment: Alignment.centerLeft, child: Text('DOCTOR', style: ClinicText.caps)),
            for (final h in ['ISSUED', 'APP', 'WALK-IN', 'DONE', 'CANCEL', 'NO-SHOW', 'AVG WAIT']) FittedBox(fit: BoxFit.scaleDown, child: Text(h, style: ClinicText.caps)),
          ]),
          const SizedBox(height: 4),
          for (final (i, d) in doctors.indexed) _doctorRow(i, d, DaySummary.of(all.where((t) => t.token.doctorId == d.id))),
        ]),
      );

  Widget _doctorRow(int index, Doctor d, DaySummary s) {
    Text number(String v, [Color color = AppColors.textPrimary, FontWeight weight = FontWeight.w500]) =>
        Text(v, style: AppText.bodyMedium.copyWith(color: color, fontWeight: weight));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.cream))),
      child: _line([
        Row(children: [
          index == 0 ? Av.solid(d.name) : Av(d.name),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700)),
              Text(s.busiestHour == null ? 'No tokens' : 'Busiest ${_hourRange(s.busiestHour!)}', style: ClinicText.small),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 6,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (s.completed > 0) Expanded(flex: s.completed, child: const ColoredBox(color: AppColors.primary)),
                    if (s.cancelled > 0) Expanded(flex: s.cancelled, child: const ColoredBox(color: ClinicColors.chartAmber)),
                    if (s.noShow > 0) Expanded(flex: s.noShow, child: const ColoredBox(color: ClinicColors.chartRed)),
                    if (s.issued - s.completed - s.cancelled - s.noShow > 0 || s.issued == 0)
                      Expanded(flex: s.issued == 0 ? 1 : s.issued - s.completed - s.cancelled - s.noShow, child: const ColoredBox(color: AppColors.cream)),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
        Text('${s.issued}', style: AppText.titleMedium.copyWith(fontWeight: FontWeight.w800)),
        number('${s.app}'),
        number('${s.walkIn}'),
        number('${s.completed}', AppColors.successText, FontWeight.w700),
        number('${s.cancelled}', AppColors.warningText, FontWeight.w700),
        number('${s.noShow}', AppColors.dangerText, FontWeight.w700),
        number(WebFmt.minutes(s.avgWait), AppColors.textPrimary, FontWeight.w700),
      ]),
    );
  }
}
