import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../doctors/doctors_screen.dart';
import 'activity_screen.dart';
import 'admin_kit.dart';
import 'payment_dialogs.dart';

enum _Tab { info, doctors, payments, activity, usage }

/// A-12 / A-03: one clinic, in tabs, with admin actions.
class ClinicDetailScreen extends ConsumerStatefulWidget {
  const ClinicDetailScreen({super.key, required this.clinicId});
  final String clinicId;

  @override
  ConsumerState<ClinicDetailScreen> createState() => _ClinicDetailScreenState();
}

class _ClinicDetailScreenState extends ConsumerState<ClinicDetailScreen> {
  _Tab _tab = _Tab.info;

  @override
  Widget build(BuildContext context) {
    final id = widget.clinicId;
    final c = ref.watch(clinicProvider(id));
    if (c == null) return const Center(child: EmptyState(icon: Icons.search_off_rounded, title: 'Clinic not found', message: 'It may have been removed.'));
    final doctors = ref.watch(allDoctorsProvider(id));

    return AdminPage(
      title: 'Clinics › ${c.clinic.name}',
      subtitle: 'Clinic detail',
      children: [
        _header(c),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: AdminTabs<_Tab>(
            values: _Tab.values,
            selected: _tab,
            label: (t) => switch (t) {
              _Tab.info => 'Info',
              _Tab.doctors => 'Doctors ${doctors.length}',
              _Tab.payments => 'Payments',
              _Tab.activity => 'Activity',
              _Tab.usage => 'Usage',
            },
            onChanged: (t) => setState(() => _tab = t),
          ),
        ),
        const SizedBox(height: 16),
        switch (_tab) {
          _Tab.info => _InfoTab(c),
          _Tab.doctors => DoctorList(clinicId: id),
          _Tab.payments => _PaymentsTab(id),
          _Tab.activity => Panel(child: ActivityFeed(clinicId: id, limit: 200)),
          _Tab.usage => _UsageTab(id),
        },
      ],
    );
  }

  Widget _header(ClinicAccount c) {
    final repo = ref.read(repositoryProvider);
    final off = c.status == ClinicStatus.suspended || c.status == ClinicStatus.cancelled;
    final line = [
      '${c.clinic.area}, ${c.clinic.city}',
      c.plan.label,
      '${WebFmt.money(c.monthlyFee)} / month',
      if (c.plan != Plan.pilot && c.paidUntil != null) 'paid until ${WebFmt.date(c.paidUntil!)}',
      if (c.plan == Plan.pilot && c.pilotEndsAt != null) 'pilot ends ${WebFmt.date(c.pilotEndsAt!)}',
    ].join(' · ');

    ButtonStyle style(Color bg, Color fg, [Color? line]) => FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          side: line == null ? null : BorderSide(color: line),
        );
    final glass = AppColors.onPrimary.withValues(alpha: 0.1);

    return HeroBlock(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      child: Row(children: [
        IconButton(
          tooltip: 'Back to clinics',
          onPressed: () => context.go('/admin/clinics'),
          icon: const Icon(Icons.chevron_left_rounded, color: AppColors.onPrimary),
        ),
        const SizedBox(width: 6),
        Av(c.clinic.name, size: 56, radius: 18, bg: AppColors.cream),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(c.clinic.name, style: AppText.titleLarge.copyWith(color: AppColors.onPrimary)),
              ClinicStatusChip(c.status),
            ]),
            const SizedBox(height: 2),
            Text(line, style: AppText.bodyMedium.copyWith(fontSize: 13, color: AppColors.onPrimaryMuted)),
          ]),
        ),
        const SizedBox(width: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            style: style(glass, AppColors.onPrimary, AppColors.onPrimary.withValues(alpha: 0.18)),
            onPressed: () => context.go('/admin/clinics/${c.id}/queue'),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('View queue'),
          ),
          FilledButton(style: style(AppColors.cream, AppColors.primary), onPressed: () => _changePlan(c), child: const Text('Change plan / fee')),
          off
              ? FilledButton.icon(
                  style: style(AppColors.successContainer, AppColors.successText),
                  onPressed: () => runAction(context, () => repo.setClinicStatus(c.id, ClinicStatus.active), success: 'Clinic reactivated.'),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Reactivate'),
                )
              : FilledButton.icon(
                  style: style(AppColors.dangerContainer, AppColors.dangerText),
                  onPressed: () async {
                    final r = await askReason(context, title: 'Suspend ${c.clinic.name}?', options: const ['Unpaid', 'Clinic request', 'Other'], confirmLabel: 'Suspend');
                    if (r != null && mounted) {
                      await runAction(context, () => repo.setClinicStatus(c.id, ClinicStatus.suspended, reason: r), success: 'Clinic suspended. The queue is read-only.');
                    }
                  },
                  icon: const Icon(Icons.pause_rounded, size: 18),
                  label: const Text('Suspend'),
                ),
        ]),
      ]),
    );
  }

  Future<void> _changePlan(ClinicAccount c) async {
    var plan = c.plan;
    final fee = TextEditingController(text: '${c.monthlyFee}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AppDialog(
          title: 'Change plan / fee',
          width: 440,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            LabeledField(
              'Plan',
              child: Wrap(spacing: 8, children: [
                for (final p in Plan.values)
                  FilterPill(
                    p.label,
                    selected: plan == p,
                    onTap: () => setDialog(() {
                      plan = p;
                      fee.text = '${ref.read(adminSettingsProvider).prices[p] ?? 0}';
                    }),
                  ),
              ]),
            ),
            const SizedBox(height: 14),
            LabeledField(
              'Monthly fee',
              child: TextField(
                  controller: fee, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(prefixText: 'Rs  ')),
            ),
          ]),
        ),
      ),
    );
    final amount = int.tryParse(fee.text);
    fee.dispose();
    if (ok == true && amount != null && mounted) {
      await runAction(context, () => ref.read(repositoryProvider).changePlan(c.id, plan: plan, monthlyFee: amount), success: 'Plan updated.');
    }
  }
}

class _InfoTab extends ConsumerWidget {
  const _InfoTab(this.c);
  final ClinicAccount c;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardRow(children: [
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Clinic details', style: ClinicText.cardTitle.copyWith(fontSize: 16)),
              const SizedBox(height: 10),
              InfoLine('Owner', '${c.ownerName} · ${Fmt.phone(c.ownerPhone)}'),
              InfoLine('Clinic phone', c.clinic.phone),
              InfoLine('Address', c.clinic.address),
              InfoLine('Area / City', '${c.clinic.area}, ${c.clinic.city}'),
              InfoLine('Location', c.clinic.location == null ? 'Not set' : formatLatLng(c.clinic.location!)),
              InfoLine('Print format', c.printFormat.label),
              InfoLine('Joined', WebFmt.date(c.createdAt)),
            ]),
          ),
          _ClinicLoginCard(c),
          _billing(context, ref),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 4, child: _doctors(ref)),
          const SizedBox(width: 16),
          Expanded(flex: 7, child: _UsageChart(c.id)),
        ]),
      ]);

  Widget _box(String label, String value, {bool good = false}) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: good ? AppColors.successContainer : ClinicColors.quiet, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: ClinicText.small.copyWith(color: good ? AppColors.successText : AppColors.textSecondary)),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w800, color: good ? AppColors.successText : AppColors.textPrimary)),
          ]),
        ),
      );

  Widget _billing(BuildContext context, WidgetRef ref) {
    final pilot = c.plan == Plan.pilot;
    final open = ref.watch(invoicesProvider(c.id)).where((i) => i.isOpen).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final until = pilot ? c.pilotEndsAt : c.paidUntil;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Plan and billing', style: ClinicText.cardTitle.copyWith(fontSize: 16)),
        const SizedBox(height: 12),
        Row(children: [_box('Plan', pilot ? 'Pilot → ${c.planAfterPilot.label}' : c.plan.label), const SizedBox(width: 8), _box('Monthly fee', WebFmt.money(c.monthlyFee))]),
        const SizedBox(height: 8),
        Row(children: [
          _box('Billing day', '${c.billingDay} of month'),
          const SizedBox(width: 8),
          _box(pilot ? 'Pilot ends' : 'Paid until', until == null ? '—' : WebFmt.date(until), good: until != null && until.isAfter(pktNow())),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: () => _extendPilot(context, ref), child: const Text('Extend pilot')),
          OutlinedButton(onPressed: open.isEmpty ? null : () => showRecordPaymentDialog(context, ref, open.first), child: const Text('Record payment')),
        ]),
      ]),
    );
  }

  Future<void> _extendPilot(BuildContext context, WidgetRef ref) async {
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Extend pilot',
        subtitle: c.pilotEndsAt == null ? null : 'Currently ends ${WebFmt.date(c.pilotEndsAt!)}',
        width: 420,
        child: Wrap(spacing: 8, children: [
          for (final d in const [7, 15, 30]) ActionChip(label: Text('+$d days'), onPressed: () => Navigator.pop(ctx, d)),
        ]),
      ),
    );
    if (days != null && context.mounted) await runAction(context, () => ref.read(repositoryProvider).extendPilot(c.id, days), success: 'Pilot extended by $days days.');
  }

  Widget _doctors(WidgetRef ref) {
    final doctors = ref.watch(allDoctorsProvider(c.id));
    final addedAt = ref.watch(doctorAddedAtProvider);
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Doctors', style: ClinicText.cardTitle.copyWith(fontSize: 16))),
          Text('added by the clinic', style: ClinicText.small),
        ]),
        const SizedBox(height: 6),
        if (doctors.isEmpty) Text('No doctors yet.', style: AppText.bodyMedium),
        for (final d in doctors)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.cream))),
            child: Row(children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(9)),
                child: Text(d.tokenPrefix, style: AppText.labelSmall.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(child: TwoLine(d.name, d.specialityEnum.display)),
              if (d.doctorGroupId != null) const CChip.tint('Linked', icon: Icons.link_rounded),
              if (isNewDoctor(addedAt[d.id])) ...[const SizedBox(width: 6), const CChip('New', fg: AppColors.infoDark, bg: AppColors.infoContainer)],
              if (!d.active) ...[const SizedBox(width: 6), const CChip('Inactive')],
            ]),
          ),
      ]),
    );
  }
}

/// The clinic's single login (D-18): status, resend invite, disable / enable,
/// and the manager PIN reset (D-41).
class _ClinicLoginCard extends ConsumerWidget {
  const _ClinicLoginCard(this.c);
  final ClinicAccount c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final login = ref.watch(clinicLoginProvider(c.id));
    final repo = ref.watch(repositoryProvider);
    final now = pktNow();
    final facts = login == null
        ? 'No login yet'
        : [
            'One login for the whole clinic.',
            'Manager: ${login.name}.',
            if (login.status == LoginStatus.invited && login.invitedAt != null) 'Invite sent ${WebFmt.ago(login.invitedAt!, now: now)}.',
            if (login.lastLoginAt != null) 'Last sign-in ${WebFmt.ago(login.lastLoginAt!, now: now)}.',
            if (login.passwordChangedAt != null) 'Password changed ${WebFmt.ago(login.passwordChangedAt!, now: now)}.',
          ].join(' ');

    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Clinic login', style: ClinicText.cardTitle.copyWith(fontSize: 16))),
          if (login != null) LoginChip(login.status),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(color: ClinicColors.quiet, borderRadius: BorderRadius.circular(ClinicRadii.control), border: Border.all(color: AppColors.border)),
          child: Row(children: [
            const Icon(Icons.mail_outline_rounded, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(login?.email ?? c.email, overflow: TextOverflow.ellipsis, style: ClinicText.body)),
          ]),
        ),
        const SizedBox(height: 8),
        Text(facts, style: ClinicText.small),
        const SizedBox(height: 12),
        if (login != null)
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(
              onPressed: () => runAction(context, () => repo.resendClinicInvite(c.id), success: 'Invite sent again to ${login.email}.'),
              child: const Text('Resend invite'),
            ),
            if (login.status == LoginStatus.disabled)
              FilledButton(
                onPressed: () => runAction(context, () => repo.setClinicLoginStatus(c.id, LoginStatus.active), success: 'Clinic login enabled.'),
                child: const Text('Enable login'),
              )
            else
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () async {
                  final ok = await confirmDialog(context,
                      title: 'Disable the clinic login?',
                      message: '${c.clinic.name} is signed out on every computer within minutes and cannot log in.',
                      confirmLabel: 'Disable login',
                      danger: true);
                  if (ok && context.mounted) await runAction(context, () => repo.setClinicLoginStatus(c.id, LoginStatus.disabled), success: 'Clinic login disabled.');
                },
                child: const Text('Disable login'),
              ),
          ]),
        if (login != null) ...[
          const SizedBox(height: 12),
          const Divider(color: AppColors.cream),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('Manager PIN', style: ClinicText.body)),
            login.pinSet ? const CChip.green('Set', dot: false) : const CChip('Not set'),
            if (login.pinSet) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () => runAction(context, () => repo.resetClinicPin(c.id), success: 'Manager PIN reset. The clinic can set a new one.'),
                child: const Text('Reset'),
              ),
            ],
          ]),
        ],
      ]),
    );
  }
}

class _PaymentsTab extends ConsumerWidget {
  const _PaymentsTab(this.clinicId);
  final String clinicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(invoicesProvider(clinicId));
    return Panel(
      padding: EdgeInsets.zero,
      child: SimpleTable(
        columns: const [
          TableColumn('Month', flex: 3),
          TableColumn('Amount', flex: 3),
          TableColumn('Due', flex: 3),
          TableColumn('Status', flex: 3),
          TableColumn('Payment', flex: 7),
          TableColumn('', flex: 4, align: TextAlign.right),
        ],
        empty: Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('No invoices yet (pilot).', style: AppText.bodyMedium))),
        rows: [
          for (final i in invoices)
            [
              Text(WebFmt.month(i.month), style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700)),
              Text(WebFmt.money(i.amount), style: ClinicText.body),
              Text(WebFmt.date(i.dueDate), style: ClinicText.body),
              InvoiceChip(i.status),
              Text(
                i.payment != null
                    ? '${i.payment!.method.label} · ${i.payment!.reference ?? '—'} · by ${i.payment!.recordedBy}'
                    : (i.waiveReason == null ? '—' : 'Waived: ${i.waiveReason}'),
                style: AppText.bodyMedium.copyWith(fontSize: 13),
              ),
              InvoiceActions(invoice: i),
            ],
        ],
      ),
    );
  }
}

/// The last 14 days of tokens at one clinic.
({List<DateTime> days, Map<DateTime, DaySummary> perDay, DaySummary all}) _usage(WidgetRef ref, String clinicId) {
  ref.watch(repoTickProvider);
  final repo = ref.watch(repositoryProvider);
  final today = parseDayKey(dayKey(pktNow()));
  final days = [for (var i = 13; i >= 0; i--) today.subtract(Duration(days: i))];
  final perDay = {for (final d in days) d: DaySummary.of(repo.tokens(clinicId, dayKey(d)).where((t) => t.status != TokenStatus.cancelled))};
  final all = DaySummary.of(days.expand((d) => repo.tokens(clinicId, dayKey(d))).where((t) => t.status != TokenStatus.cancelled));
  return (days: days, perDay: perDay, all: all);
}

class _UsageChart extends ConsumerWidget {
  const _UsageChart(this.clinicId);
  final String clinicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = _usage(ref, clinicId);
    final max = u.perDay.values.fold<int>(1, (a, s) => s.issued > a ? s.issued : a);
    final appShare = u.all.issued == 0 ? 0 : (u.all.app * 100 / u.all.issued).round();
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Usage · last 14 days', style: ClinicText.cardTitle.copyWith(fontSize: 16))),
          Text('${u.all.issued} tokens · $appShare% app · avg wait ${WebFmt.minutes(u.all.avgWait)}', style: ClinicText.small),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 140,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final (i, d) in u.days.indexed)
              Expanded(
                child: Tooltip(
                  message: '${Fmt.shortDay(dayKey(d))}: ${u.perDay[d]!.app} app, ${u.perDay[d]!.walkIn} walk-in',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text('${u.perDay[d]!.issued}', style: ClinicText.small.copyWith(fontSize: 11)),
                      const SizedBox(height: 4),
                      Container(
                        height: 4 + 96 * u.perDay[d]!.issued / max,
                        decoration: BoxDecoration(
                          color: i == u.days.length - 1 ? AppColors.primary : AppColors.onPrimaryMuted,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('${d.day}', style: ClinicText.small.copyWith(fontSize: 11)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _UsageTab extends ConsumerWidget {
  const _UsageTab(this.clinicId);
  final String clinicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = _usage(ref, clinicId).all;
    Widget stat(String label, String value) => Panel(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: ClinicText.small),
            Text(value, style: ClinicText.big(26, color: AppColors.primary)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CardRow(gap: 14, children: [
        stat('Tokens (14 days)', '${all.issued}'),
        stat('App bookings', all.issued == 0 ? '0%' : '${(all.app * 100 / all.issued).round()}%'),
        stat('Walk-ins', '${all.walkIn}'),
        stat('Average wait', WebFmt.minutes(all.avgWait)),
      ]),
      const SizedBox(height: 16),
      _UsageChart(clinicId),
    ]);
  }
}
