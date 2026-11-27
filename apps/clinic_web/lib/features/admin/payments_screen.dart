import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'admin_kit.dart';
import 'dashboard_screen.dart';
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

  /// The open invoice in the side panel.
  String? _selectedId;

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
    final selected = all.where((i) => i.id == _selectedId && i.isOpen).firstOrNull;

    final thisMonth = all.where((i) => i.month == thisMonthKey()).toList();
    final collected = thisMonth.where((i) => i.status == InvoiceStatus.paid).fold<int>(0, (a, i) => a + (i.payment?.amount ?? i.amount));
    final pending = thisMonth.where((i) => i.isOpen).toList();
    final pendingSum = pending.fold<int>(0, (a, i) => a + i.amount);
    final overdue = all.where((i) => eff(i) == InvoiceStatus.overdue).toList();
    final overdueClinics = overdue.map((i) => i.clinicId).toSet().length;
    final monthName = DateFormat('MMMM').format(now);

    return AdminPage(
      title: 'Payments and invoices',
      subtitle: "Invoices are made on each clinic's billing day (not during pilot)",
      children: [
        CardRow(gap: 14, children: [
          _total('Collected · $monthName', WebFmt.money(collected), AppColors.primary,
              foot: SplitBar([(collected, AppColors.primary), (pendingSum, AppColors.cream)])),
          _total('Pending · $monthName', WebFmt.money(pendingSum), AppColors.warningText,
              foot: Text('${pending.length} invoice${pending.length == 1 ? '' : 's'}', style: ClinicText.small)),
          _total('Overdue', WebFmt.money(overdue.fold(0, (a, i) => a + i.amount)), AppColors.dangerText,
              danger: true,
              onTap: () => context.go('/admin/defaulters'),
              foot: Text('$overdueClinics clinic${overdueClinics == 1 ? '' : 's'} · see Defaulters ›', style: ClinicText.small.copyWith(color: AppColors.dangerText))),
        ]),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, box) {
          // Wide screens keep "Record payment" beside the list.
          final side = box.maxWidth >= 1080;
          final table = Panel(
            padding: EdgeInsets.zero,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.spaceBetween, children: [
                  AdminTabs<InvoiceStatus?>(
                    values: const [null, ...InvoiceStatus.values],
                    selected: _status,
                    label: (s) => '${s?.label ?? 'All'} ${all.where((i) => s == null || eff(i) == s).length}',
                    onChanged: (s) => setState(() => _status = s),
                  ),
                  Wrap(spacing: 10, children: [
                    FilterDrop<String>(value: _month, items: months, label: WebFmt.month, allLabel: 'All months', onChanged: (v) => setState(() => _month = v)),
                    FilterDrop<String>(
                      value: _clinicId,
                      items: [for (final c in clinics) c.id],
                      label: (id) => names[id] ?? id,
                      allLabel: 'All clinics',
                      onChanged: (v) => setState(() => _clinicId = v),
                    ),
                  ]),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('${shown.length} invoices · ${WebFmt.money(total)}', style: ClinicText.small),
              ),
              SimpleTable(
                columns: const [
                  TableColumn('Clinic', flex: 7),
                  TableColumn('Month', flex: 4),
                  TableColumn('Amount', flex: 4),
                  TableColumn('Due', flex: 4),
                  TableColumn('Status', flex: 4),
                  TableColumn('Payment', flex: 6),
                  TableColumn('', flex: 2, align: TextAlign.right),
                ],
                empty: Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('No invoices for these filters.', style: AppText.bodyMedium))),
                onTap: (i) {
                  final invoice = shown[i];
                  if (!invoice.isOpen) {
                    context.go('/admin/clinics/${invoice.clinicId}');
                  } else if (side) {
                    setState(() => _selectedId = invoice.id);
                  } else {
                    showRecordPaymentDialog(context, ref, invoice);
                  }
                },
                rowColor: (i) => shown[i].id == _selectedId && side ? ClinicColors.tint : null,
                rows: [
                  for (final i in shown)
                    [
                      Text(names[i.clinicId] ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700)),
                      Text(WebFmt.month(i.month), style: ClinicText.body),
                      Text(WebFmt.money(i.amount), style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700)),
                      Text(WebFmt.date(i.dueDate), style: ClinicText.body),
                      InvoiceChip(eff(i)),
                      Text(
                        i.payment != null
                            ? '${i.payment!.method.label} · ${WebFmt.date(i.payment!.date)}'
                            : (i.waiveReason ?? (eff(i) == InvoiceStatus.overdue ? '${now.difference(i.dueDate).inDays} days late' : '—')),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: ClinicText.small,
                      ),
                      InvoiceActions(invoice: i, compact: true),
                    ],
                ],
              ),
            ]),
          );
          if (!side || selected == null) return table;
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: table),
            const SizedBox(width: 16),
            SizedBox(
              width: 340,
              child: Panel(
                child: RecordPaymentForm(
                  key: ValueKey(selected.id),
                  invoice: selected,
                  onCancel: () => setState(() => _selectedId = null),
                  onDone: () => setState(() => _selectedId = null),
                  onWaive: () => waiveInvoice(context, ref, selected),
                ),
              ),
            ),
          ]);
        }),
        const SizedBox(height: 10),
        Text('Click an unpaid or overdue invoice to record its payment.', style: ClinicText.small),
      ],
    );
  }

  Widget _total(String label, String value, Color color, {required Widget foot, bool danger = false, VoidCallback? onTap}) => Panel(
        color: danger ? AppColors.dangerContainer : AppColors.surface,
        borderColor: danger ? AppColors.dangerContainer : AppColors.border,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, style: ClinicText.small.copyWith(fontWeight: FontWeight.w700, color: danger ? AppColors.dangerText : AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(value, style: ClinicText.big(30, color: color)),
          const SizedBox(height: 8),
          foot,
        ]),
      );
}
