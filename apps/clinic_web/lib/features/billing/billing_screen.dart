import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// W-20 / C-15: plan, paid until, invoices, payment instructions.
class BillingScreen extends ConsumerWidget {
  const BillingScreen(this.clinicId, {super.key});
  final String clinicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(clinicProvider(clinicId));
    final invoices = ref.watch(invoicesProvider(clinicId));
    final settings = ref.watch(adminSettingsProvider);
    if (c == null) return const SizedBox.shrink();
    final due = invoices.where((i) => i.isOpen).fold<int>(0, (a, i) => a + i.amount);
    final pilot = c.plan == Plan.pilot;
    final until = pilot ? c.pilotEndsAt : c.paidUntil;

    return ClinicPage(
      title: 'Billing',
      subtitle: 'Payments are recorded by Asani after you pay.',
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _card('Current plan', c.plan.label, pilot ? 'Then ${c.planAfterPilot.label} · ${WebFmt.money(c.monthlyFee)} / month' : '${WebFmt.money(c.monthlyFee)} / month', dark: true),
                  const SizedBox(width: 12),
                  _card(pilot ? 'Pilot ends' : 'Paid until', until == null ? '—' : WebFmt.date(until), null, chip: _statusChip(c.status)),
                  if (due > 0) ...[const SizedBox(width: 12), _card('Amount due', WebFmt.money(due), null, danger: true)],
                ]),
              ),
              const SizedBox(height: 18),
              Panel(
                radius: 16,
                padding: EdgeInsets.zero,
                child: SimpleTable(
                  columns: const [
                    TableColumn('Month', flex: 4),
                    TableColumn('Amount', flex: 3),
                    TableColumn('Due', flex: 3),
                    TableColumn('Status', flex: 3),
                    TableColumn('Payment', flex: 6),
                  ],
                  empty: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text('No invoices yet. Invoices start after the pilot.', style: AppText.bodyMedium)),
                  ),
                  rows: [
                    for (final i in invoices)
                      [
                        Text(WebFmt.month(i.month), style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700)),
                        Text(WebFmt.money(i.amount), style: ClinicText.body),
                        Text(WebFmt.date(i.dueDate), style: ClinicText.body),
                        _invoiceChip(i.status),
                        Text(
                          i.payment != null
                              ? '${i.payment!.method.label} · ${i.payment!.reference ?? ''} · ${WebFmt.date(i.payment!.date)}'
                              : (i.waiveReason ?? (i.dueDate.isBefore(pktNow()) ? '${pktNow().difference(i.dueDate).inDays} days overdue' : '—')),
                          style: AppText.bodyMedium.copyWith(fontSize: 13),
                        ),
                      ],
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(width: 18),
          SizedBox(width: 340, child: _howToPay(settings.paymentInstructions)),
        ]),
      ],
    );
  }

  Widget _statusChip(ClinicStatus status) => switch (status) {
        ClinicStatus.active => CChip.green(status.name[0].toUpperCase() + status.name.substring(1)),
        ClinicStatus.grace => const CChip.amber('Grace'),
        ClinicStatus.suspended => const CChip.red('Suspended'),
        ClinicStatus.pilot => const CChip.tint('Pilot', dot: true),
        ClinicStatus.cancelled => const CChip('Cancelled', dot: true),
      };

  Widget _invoiceChip(InvoiceStatus status) => switch (status) {
        InvoiceStatus.unpaid => CChip.amber(status.label),
        InvoiceStatus.overdue => CChip.red(status.label),
        InvoiceStatus.paid => CChip.tint(status.label, dot: true),
        InvoiceStatus.waived => CChip(status.label, dot: true),
      };

  Widget _card(String label, String value, String? hint, {bool dark = false, bool danger = false, Widget? chip}) {
    final fg = dark ? AppColors.onPrimary : (danger ? AppColors.dangerText : AppColors.textPrimary);
    final soft = dark ? AppColors.onPrimaryMuted : (danger ? AppColors.dangerText : AppColors.textSecondary);
    return Expanded(
      child: Panel(
        radius: 16,
        color: dark ? AppColors.primary : (danger ? AppColors.dangerContainer : AppColors.surface),
        borderColor: dark ? AppColors.primary : (danger ? AppColors.dangerContainer : AppColors.border),
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppText.bodyMedium.copyWith(fontSize: 13, color: soft)),
          Text(value, style: ClinicText.big(24, color: fg)),
          if (hint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint, style: AppText.bodyMedium.copyWith(color: soft))),
          if (chip != null) Padding(padding: const EdgeInsets.only(top: 6), child: chip),
        ]),
      ),
    );
  }

  /// The Super Admin writes the instructions as plain lines. A "Name: details"
  /// line is shown with its name in bold.
  Widget _howToPay(String instructions) {
    final lines = instructions.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    return Panel(
      radius: 16,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const IconTile(Icons.account_balance_outlined, size: 38),
          const SizedBox(width: 10),
          Text('How to pay', style: ClinicText.cardTitle),
        ]),
        const SizedBox(height: 8),
        for (final (i, line) in lines.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: i == lines.length - 1 ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.cream))),
            child: _payLine(line),
          ),
      ]),
    );
  }

  Widget _payLine(String line) {
    final at = line.indexOf(':');
    if (at <= 0 || at > 30) return Text(line, style: AppText.bodyMedium.copyWith(fontSize: 13));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(line.substring(0, at).trim(), style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      SelectableText(line.substring(at + 1).trim(), style: AppText.bodyMedium),
    ]);
  }
}
