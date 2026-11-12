import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/desktop.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../staff/staff_screen.dart';
import 'activity_screen.dart';
import 'payment_dialogs.dart';

/// A-12 / A-03: one clinic, in tabs, with admin actions.
class ClinicDetailScreen extends ConsumerWidget {
  const ClinicDetailScreen({super.key, required this.clinicId});
  final String clinicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(clinicProvider(clinicId));
    if (c == null) return const Center(child: EmptyState(icon: Icons.search_off_rounded, title: 'Clinic not found', message: 'It may have been removed.'));
    final repo = ref.watch(repositoryProvider);
    final suspended = c.status == ClinicStatus.suspended || c.status == ClinicStatus.cancelled;

    return DefaultTabController(
      length: 5,
      child: PageScaffold(
        scroll: false,
        title: c.clinic.name,
        subtitle: '${c.clinic.area}, ${c.clinic.city} · ${c.email}',
        leading: HeaderBackButton(dark: true, onPressed: () => context.go('/admin/clinics')),
        actions: [
          ClinicStatusPill(c.status),
          OutlinedButton.icon(
            onPressed: () => context.go('/admin/clinics/$clinicId/queue'),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('View queue'),
          ),
          suspended
              ? FilledButton.icon(
                  onPressed: () => runAction(context, () => repo.setClinicStatus(clinicId, ClinicStatus.active), success: 'Clinic reactivated.'),
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  label: const Text('Reactivate'),
                )
              : OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
                  onPressed: () async {
                    final r = await askReason(context, title: 'Suspend ${c.clinic.name}?', options: const ['Unpaid', 'Clinic request', 'Other'], confirmLabel: 'Suspend');
                    if (r != null && context.mounted) await runAction(context, () => repo.setClinicStatus(clinicId, ClinicStatus.suspended, reason: r), success: 'Clinic suspended. The queue is read-only.');
                  },
                  icon: const Icon(Icons.block_rounded, size: 18),
                  label: const Text('Suspend'),
                ),
          PopupMenuButton<String>(
            tooltip: 'More actions',
            onSelected: (v) async {
              switch (v) {
                case 'plan':
                  await _changePlan(context, ref, c);
                case 'pilot':
                  await _extendPilot(context, ref, c);
                case 'invite':
                  final main = repo.staff(clinicId).where((s) => s.isMainAccount).firstOrNull;
                  if (main != null) await runAction(context, () => repo.resendInvite(main.uid), success: 'Invite sent again to ${main.email}.');
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'plan', child: Text('Change plan / fee')),
              const PopupMenuItem(value: 'pilot', child: Text('Extend pilot')),
              const PopupMenuItem(value: 'invite', child: Text('Resend clinic admin invite')),
            ],
          ),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'Info'),
            Tab(text: 'Doctors & Staff'),
            Tab(text: 'Payments'),
            Tab(text: 'Activity'),
            Tab(text: 'Usage'),
          ]),
          const SizedBox(height: Gap.lg),
          Expanded(
            child: TabBarView(children: [
              _scroll(_InfoTab(c)),
              _scroll(_PeopleTab(clinicId)),
              _scroll(_PaymentsTab(clinicId)),
              _scroll(AppCard(padding: const EdgeInsets.all(Gap.xl), child: ActivityFeed(clinicId: clinicId, limit: 200))),
              _scroll(_UsageTab(clinicId)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _scroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.only(bottom: Gap.xl), child: child);

  Future<void> _changePlan(BuildContext context, WidgetRef ref, ClinicAccount c) async {
    var plan = c.plan;
    final fee = TextEditingController(text: '${c.monthlyFee}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AppDialog(
          title: 'Change plan / fee',
          width: 440,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FieldLabel(
              'Plan',
              child: Wrap(spacing: Gap.sm, children: [
                for (final p in Plan.values)
                  ChoiceChip(
                    label: Text(p.label),
                    selected: plan == p,
                    onSelected: (_) => setState(() {
                      plan = p;
                      fee.text = '${ref.read(adminSettingsProvider).prices[p] ?? 0}';
                    }),
                  ),
              ]),
            ),
            FieldLabel(
              'Monthly fee',
              child: TextField(controller: fee, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(prefixText: 'Rs  ')),
            ),
          ]),
        ),
      ),
    );
    final amount = int.tryParse(fee.text);
    fee.dispose();
    if (ok == true && amount != null && context.mounted) {
      await runAction(context, () => ref.read(repositoryProvider).changePlan(c.id, plan: plan, monthlyFee: amount), success: 'Plan updated.');
    }
  }

  Future<void> _extendPilot(BuildContext context, WidgetRef ref, ClinicAccount c) async {
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Extend pilot',
        subtitle: c.pilotEndsAt == null ? null : 'Currently ends ${WebFmt.date(c.pilotEndsAt!)}',
        width: 420,
        child: Wrap(spacing: Gap.sm, children: [
          for (final d in const [7, 15, 30]) ActionChip(label: Text('+$d days'), onPressed: () => Navigator.pop(ctx, d)),
        ]),
      ),
    );
    if (days != null && context.mounted) await runAction(context, () => ref.read(repositoryProvider).extendPilot(c.id, days), success: 'Pilot extended by $days days.');
  }
}

class _InfoTab extends ConsumerWidget {
  const _InfoTab(this.c);
  final ClinicAccount c;

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.sm),
        child: Row(children: [SizedBox(width: 180, child: Text(k, style: AppText.bodyMedium)), Expanded(child: Text(v, style: AppText.labelMedium))]),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: AppCard(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Clinic', style: AppText.titleMedium),
              const SizedBox(height: Gap.md),
              _row('Name', c.clinic.name),
              _row('Address', c.clinic.address),
              _row('Area / City', '${c.clinic.area}, ${c.clinic.city}'),
              _row('Phone', c.clinic.phone),
              _row('Clinic email', c.email),
              _row('Print format', c.printFormat.label),
              _row('Onboarded', WebFmt.date(c.createdAt)),
            ]),
          ),
        ),
        const SizedBox(width: Gap.xl),
        Expanded(
          child: AppCard(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Owner & billing', style: AppText.titleMedium),
              const SizedBox(height: Gap.md),
              _row('Owner', c.ownerName),
              _row('Owner phone', Fmt.phone(c.ownerPhone)),
              _row('Plan', c.plan == Plan.pilot ? 'Pilot, then ${c.planAfterPilot.label}' : c.plan.label),
              _row('Monthly fee', WebFmt.money(c.monthlyFee)),
              _row('Billing day', '${c.billingDay} of each month'),
              _row('Pilot ends', c.pilotEndsAt == null ? '—' : WebFmt.date(c.pilotEndsAt!)),
              _row('Paid until', c.paidUntil == null ? '—' : WebFmt.date(c.paidUntil!)),
            ]),
          ),
        ),
      ]);
}

class _PeopleTab extends ConsumerWidget {
  const _PeopleTab(this.clinicId);
  final String clinicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctors = ref.watch(allDoctorsProvider(clinicId));
    final logs = ref.watch(activityProvider(clinicId)).where((a) => a.action == 'added doctor').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('Doctors', style: AppText.titleMedium)),
      ]),
      const SizedBox(height: Gap.md),
      AppTable(
        columns: const [TableColumn('Doctor', flex: 4), TableColumn('Speciality', flex: 3), TableColumn('Status', flex: 2), TableColumn('Added by', flex: 3)],
        rows: [
          for (final d in doctors)
            () {
              final log = logs.where((l) => l.target == d.name).firstOrNull;
              return <Widget>[
                Row(children: [LetterBadge(d.tokenPrefix, size: 30), const SizedBox(width: Gap.md), Expanded(child: Text(d.name, style: AppText.labelMedium))]),
                Text(d.speciality, style: AppText.bodyMedium),
                d.active
                    ? const Pill(label: 'Active', fg: AppColors.success, bg: AppColors.successContainer, dot: true)
                    : const Pill(label: 'Inactive', fg: AppColors.textSecondary, bg: AppColors.muted, dot: true),
                Text(log == null ? 'At onboarding' : '${log.actorName} · ${WebFmt.date(log.at)}', style: AppText.bodyMedium),
              ];
            }(),
        ],
      ),
      const SizedBox(height: Gap.xl),
      Row(children: [
        Expanded(child: Text('Staff', style: AppText.titleMedium)),
        OutlinedButton.icon(onPressed: () => showAddStaffDialog(context, ref, clinicId), icon: const Icon(Icons.person_add_alt_1_rounded, size: 18), label: const Text('Add staff')),
      ]),
      const SizedBox(height: Gap.md),
      StaffTable(clinicId: clinicId, showInvitedBy: true),
    ]);
  }
}

class _PaymentsTab extends ConsumerWidget {
  const _PaymentsTab(this.clinicId);
  final String clinicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(invoicesProvider(clinicId));
    return AppTable(
      columns: const [
        TableColumn('Month', flex: 2),
        TableColumn('Amount', flex: 2),
        TableColumn('Due', flex: 2),
        TableColumn('Status', flex: 2),
        TableColumn('Payment', flex: 4),
        TableColumn('', flex: 3, align: TextAlign.right),
      ],
      empty: const Padding(padding: EdgeInsets.all(Gap.xl), child: Center(child: Text('No invoices yet (pilot).'))),
      rows: [
        for (final i in invoices)
          [
            Text(WebFmt.month(i.month), style: AppText.labelMedium),
            Text(WebFmt.money(i.amount), style: AppText.bodyMedium),
            Text(WebFmt.date(i.dueDate), style: AppText.bodyMedium),
            InvoicePill(i.status),
            Text(
              i.payment != null
                  ? '${i.payment!.method.label} · ${i.payment!.reference ?? '—'} · by ${i.payment!.recordedBy}'
                  : (i.waiveReason == null ? '—' : 'Waived: ${i.waiveReason}'),
              style: AppText.bodyMedium,
            ),
            InvoiceActions(invoice: i),
          ],
      ],
    );
  }
}

class _UsageTab extends ConsumerWidget {
  const _UsageTab(this.clinicId);
  final String clinicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(repoTickProvider);
    final repo = ref.watch(repositoryProvider);
    final today = parseDayKey(dayKey(pktNow()));
    final days = [for (var i = 13; i >= 0; i--) today.subtract(Duration(days: i))];
    final perDay = {for (final d in days) d: DaySummary.of(repo.tokens(clinicId, dayKey(d)).where((t) => t.status != TokenStatus.cancelled))};
    final all = DaySummary.of(days.expand((d) => repo.tokens(clinicId, dayKey(d))).where((t) => t.status != TokenStatus.cancelled));
    final max = perDay.values.fold<int>(1, (a, s) => s.issued > a ? s.issued : a);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CardGrid(minWidth: 220, children: [
        KpiCard(label: 'Tokens (14 days)', value: '${all.issued}', icon: Icons.confirmation_number_outlined),
        KpiCard(label: 'App bookings', value: all.issued == 0 ? '0' : '${(all.app * 100 / all.issued).round()}%', icon: Icons.phone_iphone_rounded, fg: AppColors.secondary, bg: AppColors.avatarCool),
        KpiCard(label: 'Walk-ins', value: '${all.walkIn}', icon: Icons.directions_walk_rounded, fg: AppColors.textSecondary, bg: AppColors.muted),
        KpiCard(label: 'Average wait', value: WebFmt.minutes(all.avgWait), icon: Icons.timer_outlined, fg: AppColors.info, bg: AppColors.infoContainer),
      ]),
      const SectionTitle('Tokens per day'),
      AppCard(
        padding: const EdgeInsets.all(Gap.xl),
        child: SizedBox(
          height: 200,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final d in days)
              Expanded(
                child: Tooltip(
                  message: '${Fmt.shortDay(dayKey(d))}: ${perDay[d]!.app} app, ${perDay[d]!.walkIn} walk-in',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text('${perDay[d]!.issued}', style: AppText.labelSmall),
                      const SizedBox(height: 4),
                      Container(height: 130 * perDay[d]!.walkIn / max, color: AppColors.primaryLight.withValues(alpha: 0.45)),
                      Container(
                        height: 130 * perDay[d]!.app / max,
                        decoration: const BoxDecoration(color: AppColors.primary),
                      ),
                      const SizedBox(height: 6),
                      Text('${d.day}', style: AppText.labelSmall),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    ]);
  }
}
