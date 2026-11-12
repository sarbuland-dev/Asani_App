import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/desktop.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'activity_screen.dart';

/// A clinic with unpaid invoices past their due date (A-06).
class Defaulter {
  const Defaulter(this.clinic, this.invoices);
  final ClinicAccount clinic;
  final List<Invoice> invoices;
  int get amount => invoices.fold(0, (a, i) => a + i.amount);
  int get daysOverdue => invoices.map((i) => pktNow().difference(i.dueDate).inDays).fold(0, (a, b) => b > a ? b : a);
}

final defaultersProvider = Provider<List<Defaulter>>((ref) {
  final now = pktNow();
  final invoices = ref.watch(invoicesProvider(null)).where((i) => i.isOpen && i.dueDate.isBefore(now)).toList();
  final out = <Defaulter>[];
  for (final c in ref.watch(clinicsProvider)) {
    final mine = invoices.where((i) => i.clinicId == c.id).toList();
    if (mine.isNotEmpty) out.add(Defaulter(c, mine));
  }
  return out..sort((a, b) => b.daysOverdue.compareTo(a.daysOverdue));
});

/// This month's tokens across all clinics: (app, walk-in).
final monthTokensProvider = Provider<(int, int)>((ref) {
  ref.watch(repoTickProvider);
  final repo = ref.watch(repositoryProvider);
  final now = pktNow();
  var app = 0, walk = 0;
  for (final c in repo.clinics()) {
    for (var d = 1; d <= now.day; d++) {
      for (final t in repo.tokens(c.id, dayKey(DateTime(now.year, now.month, d)))) {
        if (t.status == TokenStatus.cancelled) continue;
        t.source == TokenSource.app ? app++ : walk++;
      }
    }
  }
  return (app, walk);
});

String _thisMonth() {
  final n = pktNow();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}';
}

/// A-10 / A-01: Admin Dashboard.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinics = ref.watch(clinicsProvider);
    final month = ref.watch(invoicesProvider(null)).where((i) => i.month == _thisMonth()).toList();
    final expected = month.where((i) => i.status != InvoiceStatus.waived).fold<int>(0, (a, i) => a + i.amount);
    final collected = month.where((i) => i.status == InvoiceStatus.paid).fold<int>(0, (a, i) => a + (i.payment?.amount ?? i.amount));
    final defaulters = ref.watch(defaultersProvider);
    final (app, walk) = ref.watch(monthTokensProvider);
    final total = app + walk;
    final user = ref.watch(currentUserProvider)!;

    return PageScaffold(
      title: 'Assalam-o-Alaikum, ${user.name.split(' ').first}',
      subtitle: 'All clinics at a glance · ${WebFmt.month(_thisMonth())}',
      actions: [FilledButton.icon(onPressed: () => context.go('/admin/clinics/new'), icon: const Icon(Icons.add_business_rounded), label: const Text('New clinic'))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('CLINICS BY STATUS', style: AppText.overline),
        const SizedBox(height: Gap.md),
        CardGrid(minWidth: 170, children: [
          for (final s in ClinicStatus.values)
            () {
              final (label, fg, bg) = ClinicStatusPill.style(s);
              return KpiCard(
                label: label,
                value: '${clinics.where((c) => c.status == s).length}',
                icon: switch (s) {
                  ClinicStatus.pilot => Icons.flag_outlined,
                  ClinicStatus.active => Icons.check_circle_outline_rounded,
                  ClinicStatus.grace => Icons.hourglass_bottom_rounded,
                  ClinicStatus.suspended => Icons.block_rounded,
                  ClinicStatus.cancelled => Icons.cancel_outlined,
                },
                fg: fg,
                bg: bg,
                onTap: () => context.go('/admin/clinics?status=${s.name}'),
              );
            }(),
        ]),
        const SizedBox(height: Gap.xl),
        Text('THIS MONTH', style: AppText.overline),
        const SizedBox(height: Gap.md),
        CardGrid(minWidth: 220, children: [
          KpiCard(label: 'Expected revenue', value: WebFmt.money(expected), icon: Icons.trending_up_rounded),
          KpiCard(label: 'Collected', value: WebFmt.money(collected), icon: Icons.savings_outlined, fg: AppColors.success, bg: AppColors.successContainer),
          KpiCard(label: 'Pending', value: WebFmt.money(expected - collected), icon: Icons.pending_actions_rounded, fg: AppColors.warning, bg: AppColors.warningContainer),
          KpiCard(
            label: 'Defaulters',
            value: '${defaulters.length}',
            icon: Icons.warning_amber_rounded,
            danger: defaulters.isNotEmpty,
            hint: defaulters.isEmpty ? 'All paid' : WebFmt.money(defaulters.fold(0, (a, d) => a + d.amount)),
            onTap: () => context.go('/admin/defaulters'),
          ),
        ]),
        const SizedBox(height: Gap.xl),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 2,
            child: AppCard(
              padding: const EdgeInsets.all(Gap.xl),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Tokens booked this month', style: AppText.titleMedium),
                Text('All clinics', style: AppText.bodyMedium),
                const SizedBox(height: Gap.lg),
                Text('$total', style: AppText.displaySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                const SizedBox(height: Gap.lg),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: SizedBox(
                    height: 14,
                    child: Row(children: [
                      if (app > 0) Expanded(flex: app, child: Container(color: AppColors.primary)),
                      if (walk > 0) Expanded(flex: walk, child: Container(color: AppColors.primaryLight.withValues(alpha: 0.4))),
                      if (total == 0) Expanded(child: Container(color: AppColors.muted)),
                    ]),
                  ),
                ),
                const SizedBox(height: Gap.md),
                Row(children: [
                  _legend(AppColors.primary, 'App $app', total == 0 ? '' : '${(app * 100 / total).round()}%'),
                  const SizedBox(width: Gap.xl),
                  _legend(AppColors.primaryLight.withValues(alpha: 0.4), 'Walk-in $walk', total == 0 ? '' : '${(walk * 100 / total).round()}%'),
                ]),
              ]),
            ),
          ),
          const SizedBox(width: Gap.xl),
          Expanded(
            flex: 3,
            child: AppCard(
              padding: const EdgeInsets.all(Gap.xl),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text('Latest activity', style: AppText.titleMedium)),
                  TextButton(onPressed: () => context.go('/admin/activity'), child: const Text('See all')),
                ]),
                const SizedBox(height: Gap.sm),
                ActivityFeed(limit: 7),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _legend(Color c, String label, String pct) => Row(children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: Gap.sm),
        Text(label, style: AppText.labelMedium),
        const SizedBox(width: Gap.xs),
        Text(pct, style: AppText.labelSmall),
      ]);
}
