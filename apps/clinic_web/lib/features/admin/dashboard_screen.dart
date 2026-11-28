import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'activity_screen.dart';
import 'admin_kit.dart';

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

String thisMonthKey() {
  final n = pktNow();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}';
}

/// A-10 / A-01: Admin Dashboard.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(adminDataLoadingProvider)) return const AdminLoading(title: 'Dashboard');
    final clinics = ref.watch(clinicsProvider);
    final month = ref.watch(invoicesProvider(null)).where((i) => i.month == thisMonthKey()).toList();
    final expected = month.where((i) => i.status != InvoiceStatus.waived).fold<int>(0, (a, i) => a + i.amount);
    final collected = month.where((i) => i.status == InvoiceStatus.paid).fold<int>(0, (a, i) => a + (i.payment?.amount ?? i.amount));
    final defaulters = ref.watch(defaultersProvider);
    final (app, walk) = ref.watch(monthTokensProvider);
    final total = app + walk;
    final suggestions = ref.watch(linkSuggestionsProvider).where((s) => s.status == LinkStatus.open).toList();
    final strong = suggestions.where((s) => s.strength == LinkStrength.strong).length;

    final now = pktNow();
    final ending = clinics
        .where((c) => c.status == ClinicStatus.pilot && c.pilotEndsAt != null && c.pilotEndsAt!.difference(now).inDays <= 14 && c.pilotEndsAt!.isAfter(now))
        .toList()
      ..sort((a, b) => a.pilotEndsAt!.compareTo(b.pilotEndsAt!));
    final endingText = ending.isEmpty
        ? 'None in the next 14 days'
        : ending.take(2).map((c) => '${c.clinic.name} in ${c.pilotEndsAt!.difference(now).inDays + 1} days').join(' · ');

    return AdminPage(
      title: 'Dashboard',
      subtitle: '${DateFormat('EEEE, d MMMM').format(now)} · all clinics',
      actions: [FilledButton.icon(onPressed: () => context.go('/admin/clinics/new'), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('New clinic'))],
      children: [
        _hero(context, clinics, expected, collected),
        const SizedBox(height: 14),
        CardRow(gap: 14, children: [
          _tile(
            icon: Icons.warning_amber_rounded,
            label: 'Defaulters',
            value: '${defaulters.length}',
            note: defaulters.isEmpty ? 'All paid' : '${WebFmt.money(defaulters.fold(0, (a, d) => a + d.amount))} overdue · open list ›',
            onTap: () => context.go('/admin/defaulters'),
            danger: defaulters.isNotEmpty,
          ),
          _tile(
            icon: Icons.confirmation_number_outlined,
            label: 'Tokens this month',
            value: NumberFormat.decimalPattern('en_PK').format(total),
            extra: SplitBar([(app, AppColors.primary), (walk, AppColors.onPrimaryMuted)]),
            note: total == 0 ? 'No tokens yet' : '${(app * 100 / total).round()}% app · ${100 - (app * 100 / total).round()}% walk-in',
          ),
          _tile(
            icon: Icons.medical_services_outlined,
            label: 'Possible same doctor',
            value: '${suggestions.length}',
            note: suggestions.isEmpty ? 'Nothing to review' : '$strong strong · ${suggestions.length - strong} weak · review ›',
            onTap: () => context.go('/admin/doctors'),
          ),
          _tile(
            icon: Icons.people_alt_outlined,
            label: 'Pilots ending soon',
            value: '${ending.length}',
            note: endingText,
            onTap: () => context.go('/admin/clinics?status=${ClinicStatus.pilot.name}'),
          ),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Expanded(flex: 5, child: NewDoctorsCard()),
          const SizedBox(width: 16),
          Expanded(
            flex: 6,
            child: Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text('Latest activity', style: ClinicText.cardTitle.copyWith(fontSize: 16))),
                  TextButton(onPressed: () => context.go('/admin/activity'), child: const Text('See all')),
                ]),
                const ActivityFeed(limit: 6),
              ]),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _hero(BuildContext context, List<ClinicAccount> clinics, int expected, int collected) {
    int count(ClinicStatus s) => clinics.where((c) => c.status == s).length;
    const order = [ClinicStatus.active, ClinicStatus.pilot, ClinicStatus.grace, ClinicStatus.suspended, ClinicStatus.cancelled];
    Text caps(String t) => Text(t, style: ClinicText.caps.copyWith(color: AppColors.primarySoft, fontSize: 12));

    Widget stat(String label, String value, {Color? dot, Color color = AppColors.onPrimary, VoidCallback? onTap}) => Material(
          color: AppColors.onPrimary.withValues(alpha: 0.07),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.onPrimary.withValues(alpha: 0.1))),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (dot != null) ...[Container(width: 9, height: 9, decoration: BoxDecoration(color: dot, borderRadius: BorderRadius.circular(3))), const SizedBox(width: 6)],
                  Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ClinicText.small.copyWith(color: AppColors.primarySoft, fontWeight: FontWeight.w600))),
                ]),
                FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: ClinicText.big(24, color: color))),
              ]),
            ),
          ),
        );

    return HeroBlock(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      child: SizedBox(
        height: 190,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            flex: 13,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              caps('CLINICS BY STATUS'),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${clinics.length}', style: ClinicText.big(52, color: AppColors.onPrimary)),
                const SizedBox(width: 12),
                Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('clinics on Asani', style: AppText.bodyMedium.copyWith(color: AppColors.onPrimaryMuted))),
              ]),
              const SizedBox(height: 10),
              SplitBar([for (final s in order) (count(s), clinicStatusBar(s))], height: 16, gap: 3, track: AppColors.onPrimary.withValues(alpha: 0.12)),
              const Spacer(),
              Row(children: [
                for (final (i, s) in order.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: stat(clinicStatusLabel(s), '${count(s)}', dot: clinicStatusBar(s), onTap: () => context.go('/admin/clinics?status=${s.name}')),
                  ),
                ],
              ]),
            ]),
          ),
          Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 24), color: AppColors.onPrimary.withValues(alpha: 0.12)),
          Expanded(
            flex: 10,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              caps('THIS MONTH · ${DateFormat('MMMM').format(pktNow()).toUpperCase()}'),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(TextSpan(
                  text: WebFmt.money(expected),
                  style: ClinicText.big(38, color: AppColors.onPrimary),
                  children: [TextSpan(text: '  expected', style: AppText.bodyMedium.copyWith(color: AppColors.onPrimaryMuted))],
                )),
              ),
              const SizedBox(height: 12),
              SplitBar([(collected, AppColors.cream), (expected > collected ? expected - collected : 0, AppColors.onPrimary.withValues(alpha: 0.12))], height: 12),
              const Spacer(),
              Row(children: [
                Expanded(child: stat('Collected', WebFmt.money(collected))),
                const SizedBox(width: 8),
                Expanded(child: stat('Pending', WebFmt.money(expected - collected), color: ClinicColors.chartAmber)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _tile({required IconData icon, required String label, required String value, required String note, Widget? extra, VoidCallback? onTap, bool danger = false}) {
    final soft = danger ? AppColors.dangerText : AppColors.textSecondary;
    return Panel(
      color: danger ? AppColors.dangerContainer : AppColors.surface,
      borderColor: danger ? AppColors.dangerContainer : AppColors.border,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IconTile(icon, size: 38, bg: danger ? AppColors.surface : ClinicColors.tint, fg: danger ? AppColors.danger : AppColors.primary),
        const SizedBox(height: 8),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.labelMedium.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: soft)),
        Text(value, style: ClinicText.big(30, color: danger ? AppColors.dangerText : AppColors.primary)),
        if (extra != null) ...[const SizedBox(height: 4), extra],
        const SizedBox(height: 4),
        Text(note, maxLines: 2, overflow: TextOverflow.ellipsis, style: ClinicText.small.copyWith(color: soft)),
      ]),
    );
  }
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

    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('New doctors · last 7 days', style: ClinicText.cardTitle.copyWith(fontSize: 16))),
          if (unseen > 0) ...[
            CChip('$unseen unseen', fg: AppColors.infoDark, bg: AppColors.infoContainer),
            TextButton(onPressed: () => ref.read(newDoctorsSeenProvider.notifier).markSeen(), child: const Text('Mark as seen')),
          ],
        ]),
        const SizedBox(height: 6),
        if (rows.isEmpty)
          Text('No new doctors this week.', style: AppText.bodyMedium)
        else
          for (final (c, d, at) in rows)
            InkWell(
              onTap: () => context.go('/admin/clinics/${c.id}'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.cream))),
                child: Row(children: [
                  Av(d.name, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(d.name, overflow: TextOverflow.ellipsis, style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700))),
                        if (seen == null || at.isAfter(seen)) ...[const SizedBox(width: 6), const CChip('New', fg: AppColors.infoDark, bg: AppColors.infoContainer, fontSize: 11)],
                      ]),
                      Text('${d.specialityEnum.display} · ${c.clinic.name}', overflow: TextOverflow.ellipsis, style: ClinicText.small),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Text(WebFmt.ago(at, now: now), style: ClinicText.small),
                ]),
              ),
            ),
      ]),
    );
  }
}
