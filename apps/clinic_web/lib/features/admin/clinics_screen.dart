import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'admin_kit.dart';

/// Tokens this month at one clinic (not cancelled).
final clinicMonthTokensProvider = Provider.family<int, String>((ref, clinicId) {
  ref.watch(repoTickProvider);
  final (app, walk) = ref.watch(repositoryProvider).monthTokens(clinicId: clinicId);
  return app + walk;
});

/// A-11 / A-02: all clinics.
class ClinicsScreen extends ConsumerStatefulWidget {
  const ClinicsScreen({super.key, this.initialStatus, this.initialQuery});
  final String? initialStatus;

  /// Typed in the search box of another admin page.
  final String? initialQuery;

  @override
  ConsumerState<ClinicsScreen> createState() => _ClinicsScreenState();
}

class _ClinicsScreenState extends ConsumerState<ClinicsScreen> {
  static const _pageSize = 10;

  late ClinicStatus? _status = _statusOf(widget.initialStatus);
  String? _city;
  Plan? _plan;
  int _page = 0;
  late final _q = TextEditingController(text: widget.initialQuery ?? '');

  static ClinicStatus? _statusOf(String? name) => ClinicStatus.values.where((s) => s.name == name).firstOrNull;

  @override
  void didUpdateWidget(ClinicsScreen old) {
    super.didUpdateWidget(old);
    if (old.initialStatus != widget.initialStatus || old.initialQuery != widget.initialQuery) {
      _status = _statusOf(widget.initialStatus);
      _q.text = widget.initialQuery ?? '';
      _page = 0;
    }
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _filter(VoidCallback change) => setState(() {
        change();
        _page = 0;
      });

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(clinicsProvider);
    final repo = ref.watch(repositoryProvider);
    final cities = all.map((c) => c.clinic.city).toSet().toList()..sort();
    final q = _q.text.trim().toLowerCase();
    final shown = all.where((c) {
      if (_status != null && c.status != _status) return false;
      if (_city != null && c.clinic.city != _city) return false;
      if (_plan != null && c.plan != _plan) return false;
      if (q.isEmpty) return true;
      return c.clinic.name.toLowerCase().contains(q) || c.email.contains(q) || c.clinic.phone.contains(q) || c.ownerPhone.contains(q);
    }).toList();
    final pages = shown.isEmpty ? 1 : (shown.length / _pageSize).ceil();
    final page = _page.clamp(0, pages - 1);
    final visible = shown.skip(page * _pageSize).take(_pageSize).toList();

    return AdminPage(
      title: 'Clinics',
      subtitle: '${all.length} clinics · ${cities.length} ${cities.length == 1 ? 'city' : 'cities'}',
      searchBox: AdminSearch(controller: _q, onChanged: (_) => _filter(() {})),
      actions: [FilledButton.icon(onPressed: () => context.go('/admin/clinics/new'), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('New clinic'))],
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              FilterPill('All ${all.length}', selected: _status == null, onTap: () => _filter(() => _status = null)),
              for (final s in ClinicStatus.values)
                FilterPill('${clinicStatusLabel(s)} ${all.where((c) => c.status == s).length}', selected: _status == s, onTap: () => _filter(() => _status = s)),
            ]),
          ),
          const SizedBox(width: 10),
          FilterDrop<String>(value: _city, items: cities, label: (c) => c, allLabel: 'City: All', onChanged: (v) => _filter(() => _city = v)),
          const SizedBox(width: 10),
          FilterDrop<Plan>(value: _plan, items: Plan.values, label: (p) => p.label, allLabel: 'Plan: All', onChanged: (v) => _filter(() => _plan = v)),
        ]),
        const SizedBox(height: 14),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SimpleTable(
              columns: const [
                TableColumn('Clinic', flex: 9),
                TableColumn('Plan', flex: 3),
                TableColumn('Status', flex: 5),
                TableColumn('Doctors', flex: 3),
                TableColumn('Tokens (month)', flex: 4),
                TableColumn('Paid until', flex: 5),
                TableColumn('Clinic login', flex: 4),
                TableColumn('Last activity', flex: 4),
                TableColumn('', flex: 1, align: TextAlign.right),
              ],
              onTap: (i) => context.go('/admin/clinics/${visible[i].id}'),
              empty: Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('No clinics match these filters.', style: AppText.bodyMedium))),
              rows: [for (final c in visible) _row(c, repo.activity(clinicId: c.id).firstOrNull?.at, repo.clinicLogin(c.id))],
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.cream))),
              child: Row(children: [
                Expanded(child: Text('Showing ${visible.length} of ${shown.length} clinics', style: AppText.bodyMedium.copyWith(fontSize: 13))),
                if (pages > 1) ...[
                  IconButton(tooltip: 'Previous page', onPressed: page > 0 ? () => setState(() => _page = page - 1) : null, icon: const Icon(Icons.chevron_left_rounded)),
                  for (var i = 0; i < pages; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: FilterPill('${i + 1}', selected: i == page, onTap: () => setState(() => _page = i)),
                    ),
                  IconButton(tooltip: 'Next page', onPressed: page < pages - 1 ? () => setState(() => _page = page + 1) : null, icon: const Icon(Icons.chevron_right_rounded)),
                ],
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Text('Click a clinic to open its detail page.', style: ClinicText.small),
      ],
    );
  }

  List<Widget> _row(ClinicAccount c, DateTime? lastActivity, UserAccount? login) {
    final now = pktNow();
    final pilot = c.plan == Plan.pilot;
    final overdue = !pilot && c.paidUntil != null && c.paidUntil!.isBefore(now);
    final daysLeft = c.pilotEndsAt?.difference(now).inDays;
    final until = pilot
        ? (daysLeft == null ? 'Pilot' : (daysLeft < 0 ? 'Pilot ended' : 'Pilot · ${daysLeft + 1} days left'))
        : (c.paidUntil == null ? '—' : WebFmt.date(c.paidUntil!));
    return [
      Row(children: [
        Av(c.clinic.name, size: 36, radius: 11),
        const SizedBox(width: 10),
        Expanded(child: TwoLine(c.clinic.name, '${c.clinic.area}, ${c.clinic.city}')),
      ]),
      Text(c.plan.label, style: ClinicText.body),
      ClinicStatusChip(c.status),
      Text('${c.clinic.doctorCount}', style: ClinicText.body),
      Text('${ref.watch(clinicMonthTokensProvider(c.id))}', style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700)),
      Text(until, style: ClinicText.body.copyWith(color: overdue ? AppColors.dangerText : AppColors.textPrimary)),
      login == null ? Text('—', style: ClinicText.body) : LoginChip(login.status),
      Text(lastActivity == null ? '—' : WebFmt.ago(lastActivity, now: now), style: ClinicText.small),
      const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted),
    ];
  }
}
