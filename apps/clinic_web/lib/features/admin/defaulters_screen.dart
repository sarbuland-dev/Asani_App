import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../core/web/download.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'admin_kit.dart';
import 'dashboard_screen.dart';
import 'payment_dialogs.dart';

/// A-15 / A-06: clinics with overdue invoices.
class DefaultersScreen extends ConsumerWidget {
  const DefaultersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(defaultersProvider);
    final s = ref.watch(adminSettingsProvider);
    final sum = list.fold<int>(0, (a, d) => a + d.amount);

    return AdminPage(
      title: 'Defaulters',
      subtitle: list.isEmpty ? 'Every clinic is paid up' : '${list.length} clinic${list.length == 1 ? '' : 's'} · ${WebFmt.money(sum)} overdue',
      children: [
        _timeline(s),
        const SizedBox(height: 16),
        if (list.isEmpty)
          const EmptyState(icon: Icons.verified_rounded, title: 'No defaulters', message: 'Every clinic is paid up.')
        else
          Panel(
            padding: EdgeInsets.zero,
            child: SimpleTable(
              columns: const [
                TableColumn('Clinic', flex: 8),
                TableColumn('Due', flex: 3),
                TableColumn('Overdue', flex: 6),
                TableColumn('Status', flex: 4),
                TableColumn('Contact', flex: 6),
                TableColumn('', flex: 10, align: TextAlign.right),
              ],
              rows: [for (final d in list) _row(context, ref, d, s.suspendDays)],
            ),
          ),
      ],
    );
  }

  Widget _timeline(AdminSettings s) {
    final steps = [
      ('Billing day', 'Invoice made', AppColors.primary, AppColors.onPrimary),
      ('Due date passed', 'Overdue · clinic Grace · banner', ClinicColors.chartAmber, AppColors.textPrimary),
      ('+${s.graceDays} days', 'Reminder recorded', ClinicColors.chartAmber, AppColors.textPrimary),
      ('+${s.suspendDays} days', 'Clinic Suspended', ClinicColors.chartRed, AppColors.textPrimary),
      ('Payment recorded', 'Active again at once', ClinicColors.live, AppColors.textPrimary),
    ];
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('What happens automatically', style: ClinicText.cardTitle.copyWith(fontSize: 16))),
          Text('checked every night · days are set in Settings', style: ClinicText.small),
        ]),
        const SizedBox(height: 16),
        Stack(children: [
          const Positioned(left: 80, right: 80, top: 14, child: SizedBox(height: 2, child: ColoredBox(color: AppColors.border))),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (i, step) in steps.indexed)
              Expanded(
                child: Column(children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: step.$3, shape: BoxShape.circle),
                    child: Text('${i + 1}', style: AppText.labelSmall.copyWith(fontWeight: FontWeight.w800, color: step.$4)),
                  ),
                  const SizedBox(height: 8),
                  Text(step.$1, textAlign: TextAlign.center, style: AppText.labelMedium.copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
                  Text(step.$2, textAlign: TextAlign.center, style: ClinicText.small),
                ]),
              ),
          ]),
        ]),
      ]),
    );
  }

  List<Widget> _row(BuildContext context, WidgetRef ref, Defaulter d, int suspendDays) {
    final repo = ref.read(repositoryProvider);
    final c = d.clinic;
    final suspended = c.status == ClinicStatus.suspended;
    final left = suspendDays - d.daysOverdue;
    final after = suspended ? 'Suspended' : (left > 0 ? 'suspends in $left day${left == 1 ? '' : 's'}' : 'due for suspension');
    const compact = ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(0, 34)), padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)));

    return [
      InkWell(
        onTap: () => context.go('/admin/clinics/${c.id}'),
        child: Row(children: [
          Av(c.clinic.name, size: 36, radius: 11, bg: AppColors.dangerContainer, fg: AppColors.dangerText),
          const SizedBox(width: 10),
          Expanded(child: TwoLine(c.clinic.name, '${c.clinic.area}, ${c.clinic.city}')),
        ]),
      ),
      Text(WebFmt.money(d.amount), style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700)),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text.rich(TextSpan(
          text: '${d.daysOverdue} days',
          style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700),
          children: [TextSpan(text: ' · $after', style: ClinicText.small)],
        )),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: suspendDays <= 0 ? 1 : (d.daysOverdue / suspendDays).clamp(0.0, 1.0),
            minHeight: 8,
            color: suspended || left <= 0 ? ClinicColors.chartRed : ClinicColors.chartAmber,
            backgroundColor: AppColors.cream,
          ),
        ),
      ]),
      ClinicStatusChip(c.status),
      Row(children: [
        Expanded(child: TwoLine(Fmt.phone(c.ownerPhone), c.ownerName)),
        IconButton(
          tooltip: 'Copy phone',
          icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.primary),
          onPressed: () async {
            await copyText(c.ownerPhone);
            if (context.mounted) showSnack(context, 'Phone number copied.');
          },
        ),
      ]),
      Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.end, children: [
        FilledButton(
          style: compact,
          onPressed: () => showRecordPaymentDialog(context, ref, ([...d.invoices]..sort((a, b) => a.dueDate.compareTo(b.dueDate))).first),
          child: const Text('Record payment'),
        ),
        OutlinedButton(
          style: compact,
          onPressed: () async {
            final date = await pickNewDueDate(context);
            if (date == null || !context.mounted) return;
            await runAction(context, () async {
              for (final i in d.invoices) {
                await repo.giveExtension(i.id, date);
              }
            }, success: 'Extension given until ${WebFmt.date(date)}.');
          },
          child: const Text('Give extension'),
        ),
        if (!suspended)
          OutlinedButton(
            style: compact.copyWith(foregroundColor: const WidgetStatePropertyAll(AppColors.danger)),
            onPressed: () async {
              final ok = await confirmDialog(context,
                  title: 'Suspend ${c.clinic.name} now?',
                  message: "The queue becomes read-only and patients can't book there until a payment is recorded.",
                  confirmLabel: 'Suspend clinic',
                  danger: true);
              if (ok && context.mounted) {
                await runAction(context, () => repo.setClinicStatus(c.id, ClinicStatus.suspended, reason: 'unpaid ${d.daysOverdue} days'), success: 'Clinic suspended.');
              }
            },
            child: const Text('Suspend now'),
          ),
      ]),
    ];
  }
}
