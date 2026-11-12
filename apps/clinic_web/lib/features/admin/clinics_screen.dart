import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/desktop.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Tokens this month at one clinic (not cancelled).
final clinicMonthTokensProvider = Provider.family<int, String>((ref, clinicId) {
  ref.watch(repoTickProvider);
  final repo = ref.watch(repositoryProvider);
  final now = pktNow();
  var n = 0;
  for (var d = 1; d <= now.day; d++) {
    n += repo.tokens(clinicId, dayKey(DateTime(now.year, now.month, d))).where((t) => t.status != TokenStatus.cancelled).length;
  }
  return n;
});

/// A-11 / A-02: all clinics.
class ClinicsScreen extends ConsumerStatefulWidget {
  const ClinicsScreen({super.key, this.initialStatus});
  final String? initialStatus;

  @override
  ConsumerState<ClinicsScreen> createState() => _ClinicsScreenState();
}

class _ClinicsScreenState extends ConsumerState<ClinicsScreen> {
  late ClinicStatus? _status = ClinicStatus.values.where((s) => s.name == widget.initialStatus).firstOrNull;
  String? _city;
  Plan? _plan;
  final _q = TextEditingController();

  @override
  void didUpdateWidget(ClinicsScreen old) {
    super.didUpdateWidget(old);
    if (old.initialStatus != widget.initialStatus) {
      _status = ClinicStatus.values.where((s) => s.name == widget.initialStatus).firstOrNull;
    }
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

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

    return PageScaffold(
      title: 'Clinics',
      subtitle: '${all.length} clinics',
      actions: [FilledButton.icon(onPressed: () => context.go('/admin/clinics/new'), icon: const Icon(Icons.add_business_rounded), label: const Text('New clinic'))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _q,
              decoration: const InputDecoration(hintText: 'Search by name, phone or email', prefixIcon: Icon(Icons.search_rounded)),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: Gap.md),
          _drop<ClinicStatus>('All statuses', _status, ClinicStatus.values, (s) => ClinicStatusPill.style(s).$1, (v) => setState(() => _status = v)),
          const SizedBox(width: Gap.md),
          _drop<String>('All cities', _city, cities, (s) => s, (v) => setState(() => _city = v)),
          const SizedBox(width: Gap.md),
          _drop<Plan>('All plans', _plan, Plan.values, (p) => p.label, (v) => setState(() => _plan = v)),
        ]),
        const SizedBox(height: Gap.lg),
        AppTable(
          columns: const [
            TableColumn('Clinic', flex: 4),
            TableColumn('Plan', flex: 2),
            TableColumn('Status', flex: 2),
            TableColumn('Doctors', flex: 2, align: TextAlign.center),
            TableColumn('Staff', flex: 1, align: TextAlign.center),
            TableColumn('Tokens (month)', flex: 2, align: TextAlign.center),
            TableColumn('Paid until', flex: 3),
            TableColumn('Last activity', flex: 2),
          ],
          onTap: (i) => context.go('/admin/clinics/${shown[i].id}'),
          empty: const Padding(padding: EdgeInsets.all(Gap.xl), child: Center(child: Text('No clinics match these filters.'))),
          rows: [
            for (final c in shown)
              () {
                final last = repo.activity(clinicId: c.id).firstOrNull;
                return <Widget>[
                  TwoLine(c.clinic.name, '${c.clinic.area}, ${c.clinic.city}'),
                  Text(c.plan.label, style: AppText.bodyMedium),
                  ClinicStatusPill(c.status),
                  Text('${c.clinic.doctorCount}', style: AppText.labelMedium),
                  Text('${repo.staff(c.id).where((s) => s.status != StaffStatus.disabled).length}', style: AppText.labelMedium),
                  Text('${ref.watch(clinicMonthTokensProvider(c.id))}', style: AppText.labelMedium),
                  Text(
                    c.plan == Plan.pilot ? 'Pilot to ${c.pilotEndsAt == null ? '—' : WebFmt.date(c.pilotEndsAt!)}' : (c.paidUntil == null ? '—' : WebFmt.date(c.paidUntil!)),
                    style: AppText.bodyMedium.copyWith(color: c.paidUntil != null && c.paidUntil!.isBefore(pktNow()) && c.plan != Plan.pilot ? AppColors.danger : null),
                  ),
                  Text(last == null ? '—' : WebFmt.ago(last.at, now: pktNow()), style: AppText.bodyMedium),
                ];
              }(),
          ],
        ),
      ]),
    );
  }

  Widget _drop<T>(String hint, T? value, List<T> items, String Function(T) label, ValueChanged<T?> onChanged) => SizedBox(
        width: 160,
        child: DropdownButtonFormField<T?>(
          initialValue: value,
          key: ValueKey('$hint-$value'),
          items: [DropdownMenuItem(value: null, child: Text(hint)), for (final i in items) DropdownMenuItem(value: i, child: Text(label(i)))],
          onChanged: onChanged,
        ),
      );
}
