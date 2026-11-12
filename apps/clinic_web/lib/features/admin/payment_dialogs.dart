import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/desktop.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// A-14 Record payment: amount, method, reference, date. Proof screenshot
/// upload comes with Firebase Storage.
Future<void> showRecordPaymentDialog(BuildContext context, WidgetRef ref, Invoice invoice) =>
    showDialog<void>(context: context, builder: (_) => _RecordPayment(invoice: invoice));

class _RecordPayment extends ConsumerStatefulWidget {
  const _RecordPayment({required this.invoice});
  final Invoice invoice;

  @override
  ConsumerState<_RecordPayment> createState() => _RecordPaymentState();
}

class _RecordPaymentState extends ConsumerState<_RecordPayment> {
  late final _amount = TextEditingController(text: '${widget.invoice.amount}');
  final _ref = TextEditingController();
  PaymentMethod _method = PaymentMethod.jazzCash;
  DateTime _date = pktNow();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clinic = ref.watch(clinicProvider(widget.invoice.clinicId));
    final amount = int.tryParse(_amount.text) ?? 0;
    return AppDialog(
      title: 'Record payment',
      subtitle: '${clinic?.clinic.name ?? ''} · ${WebFmt.month(widget.invoice.month)} · ${WebFmt.money(widget.invoice.amount)}',
      width: 520,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: amount <= 0 || _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final me = ref.read(currentUserProvider)!;
                  final ok = await runAction(
                    context,
                    () => ref.read(repositoryProvider).recordPayment(
                          widget.invoice.id,
                          Payment(amount: amount, method: _method, reference: _ref.text.trim().isEmpty ? null : _ref.text.trim(), date: _date, recordedBy: me.name),
                        ),
                    success: 'Payment recorded. Clinic is Active, paid until +1 month.',
                  );
                  if (!context.mounted) return;
                  setState(() => _busy = false);
                  if (ok) Navigator.pop(context);
                },
          child: const Text('Record payment'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: FieldLabel(
              'Amount',
              child: TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(prefixText: 'Rs  '),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: FieldLabel(
              'Date',
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () async {
                  final d = await showDatePicker(context: context, firstDate: DateTime(2026), lastDate: pktNow(), initialDate: _date);
                  if (d != null) setState(() => _date = d);
                },
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                label: Text(WebFmt.date(_date)),
              ),
            ),
          ),
        ]),
        FieldLabel(
          'Method',
          child: Wrap(spacing: Gap.sm, children: [
            for (final m in PaymentMethod.values) ChoiceChip(label: Text(m.label), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
          ]),
        ),
        FieldLabel('Reference / transaction ID', child: TextField(controller: _ref, decoration: const InputDecoration(hintText: 'Optional'))),
        Text('Proof screenshot upload will be added with Firebase Storage.', style: AppText.labelSmall),
      ]),
    );
  }
}

/// Invoice row actions: Record payment, Waive, Give extension.
class InvoiceActions extends ConsumerWidget {
  const InvoiceActions({super.key, required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!invoice.isOpen) return const SizedBox.shrink();
    final repo = ref.watch(repositoryProvider);
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: Gap.md), textStyle: AppText.labelMedium),
        onPressed: () => showRecordPaymentDialog(context, ref, invoice),
        child: const Text('Record payment'),
      ),
      PopupMenuButton<String>(
        tooltip: 'More',
        onSelected: (v) async {
          if (v == 'waive') {
            final reason = await askReason(context, title: 'Waive ${WebFmt.month(invoice.month)} invoice?', options: const ['Pilot extension', 'Goodwill', 'Other'], confirmLabel: 'Waive');
            if (reason != null && context.mounted) await runAction(context, () => repo.waiveInvoice(invoice.id, reason), success: 'Invoice waived.');
          } else {
            final today = parseDayKey(dayKey(pktNow()));
            final d = await showDatePicker(
              context: context,
              helpText: 'New due date',
              firstDate: today.add(const Duration(days: 1)),
              lastDate: today.add(const Duration(days: 60)),
              initialDate: today.add(const Duration(days: 7)),
            );
            if (d != null && context.mounted) await runAction(context, () => repo.giveExtension(invoice.id, d), success: 'Extension given until ${WebFmt.date(d)}.');
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'ext', child: Text('Give extension')),
          PopupMenuItem(value: 'waive', child: Text('Waive invoice')),
        ],
      ),
    ]);
  }
}
