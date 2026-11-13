import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/desktop.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'payment_dialogs.dart';

/// A-14 / A-05: invoices across clinics, record payment, waive.
class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  InvoiceStatus? _status;
  String? _month;
  String? _clinicId;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(invoicesProvider(null));
    final clinics = ref.watch(clinicsProvider);
    final names = {for (final c in clinics) c.id: c.clinic.name};
    final months = all.map((i) => i.month).toSet().toList()..sort((a, b) => b.compareTo(a));
    final now = pktNow();
    // Unpaid past the due date shows as Overdue.
    InvoiceStatus eff(Invoice i) => i.status == InvoiceStatus.unpaid && i.dueDate.isBefore(now) ? InvoiceStatus.overdue : i.status;
    final shown = all.where((i) => (_status == null || eff(i) == _status) && (_month == null || i.month == _month) && (_clinicId == null || i.clinicId == _clinicId)).toList();
    final total = shown.fold<int>(0, (a, i) => a + i.amount);

    return PageScaffold(
      title: 'Payments & invoices',
      subtitle: 'Invoices are created on each billing day (not during pilot).',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          for (final s in [null, ...InvoiceStatus.values]) ...[
            ChoiceChip(
              label: Text('${s?.label ?? 'All'} (${all.where((i) => s == null || eff(i) == s).length})'),
              selected: _status == s,
              onSelected: (_) => setState(() => _status = s),
            ),
            const SizedBox(width: Gap.sm),
          ],
          const Spacer(),
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<String?>(
              initialValue: _month,
              items: [const DropdownMenuItem(value: null, child: Text('All months')), for (final m in months) DropdownMenuItem(value: m, child: Text(WebFmt.month(m)))],
              onChanged: (v) => setState(() => _month = v),
            ),
          ),
          const SizedBox(width: Gap.md),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              initialValue: _clinicId,
              items: [const DropdownMenuItem(value: null, child: Text('All clinics')), for (final c in clinics) DropdownMenuItem(value: c.id, child: Text(c.clinic.name))],
              onChanged: (v) => setState(() => _clinicId = v),
            ),
          ),
        ]),
        const SizedBox(height: Gap.md),
        Text('${shown.length} invoices · ${WebFmt.money(total)}', style: AppText.labelMedium),
        const SizedBox(height: Gap.md),
        AppTable(
          columns: const [
            TableColumn('Clinic', flex: 4),
            TableColumn('Month', flex: 2),
            TableColumn('Amount', flex: 2),
            TableColumn('Due', flex: 2),
            TableColumn('Status', flex: 2),
            TableColumn('Payment', flex: 3),
            TableColumn('', flex: 3, align: TextAlign.right),
          ],
          empty: const Padding(padding: EdgeInsets.all(Gap.xl), child: Center(child: Text('No invoices for these filters.'))),
          rows: [
            for (final i in shown)
              [
                InkWell(onTap: () => context.go('/admin/clinics/${i.clinicId}'), child: Text(names[i.clinicId] ?? '—', style: AppText.labelMedium.copyWith(color: AppColors.primary))),
                Text(WebFmt.month(i.month), style: AppText.bodyMedium),
                Text(WebFmt.money(i.amount), style: AppText.labelMedium),
                Text(WebFmt.date(i.dueDate), style: AppText.bodyMedium),
                InvoicePill(eff(i)),
                Text(i.payment != null ? '${i.payment!.method.label} · ${WebFmt.date(i.payment!.date)}' : (i.waiveReason ?? '—'), style: AppText.bodyMedium),
                InvoiceActions(invoice: i),
              ],
          ],
        ),
      ]),
    );
  }
}
