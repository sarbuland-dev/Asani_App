import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  return ref.watch(repositoryProvider).monthTokens();
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
        const NewDoctorsCard(),
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


/// When the Super Admin last marked new doctors as seen (unseen badge, A-01).
/// Kept for this browser session; the Firebase version stores it per admin.
class NewDoctorsSeen extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;
  void markSeen() => state = pktNow();
}

final newDoctorsSeenProvider = NotifierProvider<NewDoctorsSeen, DateTime?>(NewDoctorsSeen.new);

/// A-01 (D-19): doctors added by clinics in the last 7 days.
class NewDoctorsCard extends ConsumerWidget {
  const NewDoctorsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addedAt = ref.watch(doctorAddedAtProvider);
    final seen = ref.watch(newDoctorsSeenProvider);
    final now = pktNow();
    final rows = <(ClinicAccount, Doctor, DateTime)>[];
    for (final c in ref.watch(clinicsProvider)) {
      for (final d in ref.watch(allDoctorsProvider(c.id))) {
        final at = addedAt[d.id];
        // Doctors set up at onboarding are not news; only later additions.
        if (isNewDoctor(at) && at!.isAfter(c.createdAt.add(const Duration(minutes: 1)))) rows.add((c, d, at));
      }
    }
    rows.sort((a, b) => b.$3.compareTo(a.$3));
    final unseen = rows.where((r) => seen == null || r.$3.isAfter(seen)).length;

    return AppCard(
      padding: const EdgeInsets.all(Gap.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const IconBox(icon: Icons.medical_services_outlined),
          const SizedBox(width: Gap.md),
          Text('New doctors', style: AppText.titleMedium),
          const SizedBox(width: Gap.sm),
          if (unseen > 0) Pill(label: '$unseen new', fg: AppColors.onPrimary, bg: AppColors.danger),
          const Spacer(),
          Text('Added by clinics · last 7 days', style: AppText.labelSmall),
          if (unseen > 0) ...[
            const SizedBox(width: Gap.md),
            TextButton(onPressed: () => ref.read(newDoctorsSeenProvider.notifier).markSeen(), child: const Text('Mark as seen')),
          ],
        ]),
        const SizedBox(height: Gap.md),
        if (rows.isEmpty)
          Text('No new doctors this week.', style: AppText.bodyMedium)
        else
          for (final (c, d, at) in rows)
            InkWell(
              borderRadius: BorderRadius.circular(Radii.button),
              onTap: () => context.go('/admin/clinics/${c.id}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.sm, horizontal: Gap.xs),
                child: Row(children: [
                  LetterBadge(d.tokenPrefix, size: 32),
                  const SizedBox(width: Gap.md),
                  Expanded(child: TwoLine('${d.name} · ${d.speciality}', c.clinic.name)),
                  if (seen == null || at.isAfter(seen)) ...[
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle)),
                    const SizedBox(width: Gap.sm),
                  ],
                  Text(WebFmt.ago(at, now: now), style: AppText.labelSmall),
                ]),
              ),
            ),
      ]),
    );
  }
}
