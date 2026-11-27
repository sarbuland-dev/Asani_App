import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// A-14 Record payment in a dialog (defaulters, clinic page, small screens).
Future<void> showRecordPaymentDialog(BuildContext context, WidgetRef ref, Invoice invoice) => showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 420, maxHeight: MediaQuery.sizeOf(ctx).height - 48),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: RecordPaymentForm(invoice: invoice, onDone: () => Navigator.pop(ctx), onCancel: () => Navigator.pop(ctx)),
          ),
        ),
      ),
    );

/// Amount, method, reference and date. Also the side panel of the payments page.
class RecordPaymentForm extends ConsumerStatefulWidget {
  const RecordPaymentForm({super.key, required this.invoice, this.onDone, this.onCancel, this.onWaive});
  final Invoice invoice;
  final VoidCallback? onDone;
  final VoidCallback? onCancel;
  final VoidCallback? onWaive;

  @override
  ConsumerState<RecordPaymentForm> createState() => _RecordPaymentFormState();
}

class _RecordPaymentFormState extends ConsumerState<RecordPaymentForm> {
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

  Future<void> _record(int amount) async {
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
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final clinic = ref.watch(clinicProvider(widget.invoice.clinicId));
    final amount = int.tryParse(_amount.text) ?? 0;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('Record payment', style: ClinicText.cardTitle)),
        if (widget.onCancel != null) IconButton(tooltip: 'Close (Esc)', onPressed: widget.onCancel, icon: const Icon(Icons.close_rounded, size: 20)),
      ]),
      Text('${clinic?.clinic.name ?? ''} · ${WebFmt.month(widget.invoice.month)} · ${WebFmt.money(widget.invoice.amount)} due', style: ClinicText.small),
      const SizedBox(height: 14),
      LabeledField(
        'Amount',
        child: TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(prefixText: 'Rs  '),
          onChanged: (_) => setState(() {}),
        ),
      ),
      const SizedBox(height: 12),
      LabeledField(
        'Method',
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final m in PaymentMethod.values) FilterPill(m.label, selected: _method == m, onTap: () => setState(() => _method = m)),
        ]),
      ),
      const SizedBox(height: 12),
      LabeledField('Reference / transaction ID', child: TextField(controller: _ref, decoration: const InputDecoration(hintText: 'Optional'))),
      const SizedBox(height: 12),
      LabeledField(
        'Date paid',
        child: OutlinedButton.icon(
          onPressed: () async {
            final d = await showDatePicker(context: context, firstDate: DateTime(2026), lastDate: pktNow(), initialDate: _date);
            if (d != null && mounted) setState(() => _date = d);
          },
          icon: const Icon(Icons.calendar_today_rounded, size: 16),
          label: Text(WebFmt.date(_date)),
        ),
      ),
      const SizedBox(height: 14),
      const NoteBox(
        'Saves the invoice as Paid, moves "paid until" one month on and makes the clinic Active.',
        fg: AppColors.successText,
        bg: AppColors.successContainer,
        icon: Icons.check_rounded,
      ),
      const SizedBox(height: 14),
      SizedBox(
        height: 46,
        child: FilledButton(
          onPressed: amount <= 0 || _busy ? null : () => _record(amount),
          child: BusyLabel(busy: _busy, busyText: 'Recording…', color: AppColors.textSecondary, child: const Text('Record payment')),
        ),
      ),
      if (widget.onWaive != null)
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
          onPressed: widget.onWaive,
          child: const Text('Waive this invoice…'),
        ),
    ]);
  }
}

/// Asks why, then waives the invoice.
Future<void> waiveInvoice(BuildContext context, WidgetRef ref, Invoice invoice) async {
  final reason = await askReason(context, title: 'Waive ${WebFmt.month(invoice.month)} invoice?', options: const ['Pilot extension', 'Goodwill', 'Other'], confirmLabel: 'Waive');
  if (reason != null && context.mounted) {
    await runAction(context, () => ref.read(repositoryProvider).waiveInvoice(invoice.id, reason), success: 'Invoice waived.');
  }
}

/// A new due date, up to 60 days ahead. Null when dismissed.
Future<DateTime?> pickNewDueDate(BuildContext context) {
  final today = parseDayKey(dayKey(pktNow()));
  return showDatePicker(
    context: context,
    helpText: 'New due date',
    firstDate: today.add(const Duration(days: 1)),
    lastDate: today.add(const Duration(days: 60)),
    initialDate: today.add(const Duration(days: 7)),
  );
}

/// Invoice row actions: Record payment, Waive, Give extension.
class InvoiceActions extends ConsumerWidget {
  const InvoiceActions({super.key, required this.invoice, this.compact = false});
  final Invoice invoice;

  /// Only the menu, with Record payment inside it.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!invoice.isOpen) return const SizedBox.shrink();
    final repo = ref.watch(repositoryProvider);
    return Row(mainAxisAlignment: MainAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
      if (!compact)
        Flexible(
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12)),
            onPressed: () => showRecordPaymentDialog(context, ref, invoice),
            child: const Text('Record payment', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      PopupMenuButton<String>(
        tooltip: 'More',
        onSelected: (v) async {
          if (v == 'record') {
            await showRecordPaymentDialog(context, ref, invoice);
          } else if (v == 'waive') {
            await waiveInvoice(context, ref, invoice);
          } else {
            final d = await pickNewDueDate(context);
            if (d != null && context.mounted) await runAction(context, () => repo.giveExtension(invoice.id, d), success: 'Extension given until ${WebFmt.date(d)}.');
          }
        },
        itemBuilder: (_) => [
          if (compact) const PopupMenuItem(value: 'record', child: Text('Record payment')),
          const PopupMenuItem(value: 'ext', child: Text('Give extension')),
          const PopupMenuItem(value: 'waive', child: Text('Waive invoice')),
        ],
      ),
    ]);
  }
}
