import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/desktop.dart';
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

    return PageScaffold(
      title: 'Billing',
      subtitle: 'Payments are recorded by Asani after you pay.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardGrid(minWidth: 220, children: [
          KpiCard(label: 'Plan', value: c.plan.label, icon: Icons.workspace_premium_outlined, hint: c.plan == Plan.pilot ? 'Then ${c.planAfterPilot.label}' : null),
          KpiCard(label: 'Monthly fee', value: WebFmt.money(c.monthlyFee), icon: Icons.payments_outlined),
          if (c.plan == Plan.pilot)
            KpiCard(label: 'Pilot ends', value: c.pilotEndsAt == null ? '—' : WebFmt.date(c.pilotEndsAt!), icon: Icons.flag_outlined, fg: AppColors.info, bg: AppColors.infoContainer)
          else
            KpiCard(label: 'Paid until', value: c.paidUntil == null ? '—' : WebFmt.date(c.paidUntil!), icon: Icons.event_available_rounded, fg: AppColors.success, bg: AppColors.successContainer),
          KpiCard(label: 'Amount due', value: WebFmt.money(due), icon: Icons.account_balance_wallet_outlined, danger: due > 0),
        ]),
        const SectionTitle('Invoices'),
        AppTable(
          columns: const [
            TableColumn('Month', flex: 2),
            TableColumn('Amount', flex: 2),
            TableColumn('Due date', flex: 2),
            TableColumn('Status', flex: 2),
            TableColumn('Payment', flex: 4),
          ],
          empty: const Padding(padding: EdgeInsets.all(Gap.xl), child: Center(child: Text('No invoices yet. Invoices start after the pilot.'))),
          rows: [
            for (final i in invoices)
              [
                Text(WebFmt.month(i.month), style: AppText.labelMedium),
                Text(WebFmt.money(i.amount), style: AppText.bodyMedium),
                Text(WebFmt.date(i.dueDate), style: AppText.bodyMedium),
                InvoicePill(i.status),
                Text(
                  i.payment != null
                      ? '${i.payment!.method.label} · ${i.payment!.reference ?? ''} · ${WebFmt.date(i.payment!.date)}'
                      : (i.waiveReason ?? (i.dueDate.isBefore(pktNow()) ? '${pktNow().difference(i.dueDate).inDays} days overdue' : '—')),
                  style: AppText.bodyMedium,
                ),
              ],
          ],
        ),
        const SectionTitle('How to pay'),
        AppCard(
          padding: const EdgeInsets.all(Gap.xl),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const IconBox(icon: Icons.account_balance_outlined),
            const SizedBox(width: Gap.lg),
            Expanded(child: Text(settings.paymentInstructions, style: AppText.bodyLarge.copyWith(height: 1.6))),
          ]),
        ),
      ]),
    );
  }
}
