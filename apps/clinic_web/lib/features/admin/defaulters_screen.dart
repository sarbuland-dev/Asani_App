import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/web/download.dart';
import '../../core/widgets/desktop.dart';
import '../../data/providers.dart';
import 'dashboard_screen.dart';
import 'payment_dialogs.dart';

/// A-15 / A-06: clinics with overdue invoices.
class DefaultersScreen extends ConsumerWidget {
  const DefaultersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(defaultersProvider);
    final s = ref.watch(adminSettingsProvider);
    final repo = ref.watch(repositoryProvider);

    return PageScaffold(
      title: 'Defaulters',
      subtitle: 'Due date passed → Grace. +${s.graceDays} days → reminder email. +${s.suspendDays} days → Suspended. Payment recorded → Active.',
      child: list.isEmpty
          ? const EmptyState(icon: Icons.verified_rounded, title: 'No defaulters', message: 'Every clinic is paid up.')
          : AppTable(
              columns: const [
                TableColumn('Clinic', flex: 4),
                TableColumn('Status', flex: 2),
                TableColumn('Amount due', flex: 2),
                TableColumn('Days overdue', flex: 2),
                TableColumn('Contact', flex: 4),
                TableColumn('', flex: 3, align: TextAlign.right),
              ],
              rows: [
                for (final d in list)
                  [
                    InkWell(
                      onTap: () => context.go('/admin/clinics/${d.clinic.id}'),
                      child: TwoLine(d.clinic.clinic.name, '${d.invoices.length} open invoice${d.invoices.length == 1 ? '' : 's'}'),
                    ),
                    ClinicStatusPill(d.clinic.status),
                    Text(WebFmt.money(d.amount), style: AppText.labelMedium.copyWith(color: AppColors.danger)),
                    Text('${d.daysOverdue} days', style: AppText.labelMedium),
                    Row(children: [
                      Flexible(child: TwoLine(d.clinic.ownerName, Fmt.phone(d.clinic.ownerPhone))),
                      IconButton(
                        tooltip: 'Copy phone',
                        iconSize: 16,
                        onPressed: () async {
                          await copyText(d.clinic.ownerPhone);
                          if (context.mounted) showSnack(context, 'Phone number copied.');
                        },
                        icon: const Icon(Icons.copy_rounded),
                      ),
                    ]),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: Gap.md), textStyle: AppText.labelMedium),
                        onPressed: () => showRecordPaymentDialog(context, ref, (d.invoices..sort((a, b) => a.dueDate.compareTo(b.dueDate))).first),
                        child: const Text('Record payment'),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        onSelected: (v) async {
                          if (v == 'suspend') {
                            final ok = await confirmDialog(context,
                                title: 'Suspend ${d.clinic.clinic.name} now?', message: 'No new tokens or Next until payment is recorded.', confirmLabel: 'Suspend', danger: true);
                            if (ok && context.mounted) {
                              await runAction(context, () => repo.setClinicStatus(d.clinic.id, ClinicStatus.suspended, reason: 'unpaid ${d.daysOverdue} days'), success: 'Clinic suspended.');
                            }
                            return;
                          }
                          final today = parseDayKey(dayKey(pktNow()));
                          final date = await showDatePicker(
                            context: context,
                            helpText: 'New due date',
                            firstDate: today.add(const Duration(days: 1)),
                            lastDate: today.add(const Duration(days: 60)),
                            initialDate: today.add(const Duration(days: 7)),
                          );
                          if (date == null || !context.mounted) return;
                          await runAction(context, () async {
                            for (final i in d.invoices) {
                              await repo.giveExtension(i.id, date);
                            }
                          }, success: 'Extension given until ${WebFmt.date(date)}.');
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'ext', child: Text('Give extension')),
                          if (d.clinic.status != ClinicStatus.suspended)
                            PopupMenuItem(value: 'suspend', child: Text('Suspend now', style: AppText.labelMedium.copyWith(color: AppColors.danger))),
                        ],
                      ),
                    ]),
                  ],
              ],
            ),
    );
  }
}
