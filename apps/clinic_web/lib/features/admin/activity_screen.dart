import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'admin_kit.dart';

/// Icon of a log line, from the words of its action.
IconData activityIcon(String action) {
  final s = action.toLowerCase();
  bool has(String w) => s.contains(w);
  if (has('payment') || has('invoice') || has('extension')) return Icons.credit_card_rounded;
  if (has('grace') || has('suspend')) return Icons.warning_amber_rounded;
  if (has('pin') || has('password')) return Icons.lock_outline_rounded;
  if (has('invite') || has('login')) return Icons.mail_outline_rounded;
  if (has('link')) return Icons.link_rounded;
  if (has('leave')) return Icons.calendar_today_outlined;
  if (has('export')) return Icons.description_outlined;
  if (has('doctor')) return Icons.medical_services_outlined;
  return Icons.local_hospital_outlined;
}

/// Compact activity list ("Al-Shifa added Dr. Ayesha Malik · 2h ago").
class ActivityFeed extends ConsumerWidget {
  const ActivityFeed({super.key, this.clinicId, this.limit = 50});
  final String? clinicId;
  final int limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(activityProvider(clinicId)).take(limit).toList();
    final clinics = {for (final c in ref.watch(clinicsProvider)) c.id: c.clinic.name};
    if (logs.isEmpty) return Text('No activity yet.', style: AppText.bodyMedium);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final a in logs)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.cream))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconTile(activityIcon(a.action), size: 32, bg: AppColors.cream),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: a.actorName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: ' ${a.action} ${a.target}'),
                  ]),
                  style: AppText.bodyMedium.copyWith(fontSize: 13, color: AppColors.textPrimary),
                ),
                Text(
                  [WebFmt.ago(a.at, now: pktNow()), if (clinicId == null && a.clinicId != null) clinics[a.clinicId] ?? ''].where((x) => x.isNotEmpty).join(' · '),
                  style: ClinicText.small,
                ),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

/// A-16 / A-07: activity log with filters, one card per day.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  String? _clinicId;
  String? _type;
  int _days = 30;
  final _person = TextEditingController();

  static const _types = {
    'clinic': 'Clinic',
    'doctor': 'Doctors',
    'leave': 'Leave',
    'login': 'Clinic login',
    'payment': 'Payments',
    'invoice': 'Invoices',
    'export': 'Exports',
    'settings': 'Settings',
  };

  static const _ranges = {1: 'Last 24 hours', 7: 'Last 7 days', 30: 'Last 30 days', 365: 'Last year'};

  bool _matchType(ActivityLog a) {
    final s = a.action.toLowerCase();
    return switch (_type) {
      null => true,
      'login' => s.contains('login') || s.contains('password'),
      'payment' => s.contains('payment') || s.contains('extension'),
      'invoice' => s.contains('invoice') || s.contains('grace'),
      'export' => s.contains('export'),
      'settings' => s.contains('settings') || s.contains('plan') || s.contains('pilot'),
      _ => s.contains(_type!),
    };
  }

  @override
  void dispose() {
    _person.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clinics = ref.watch(clinicsProvider);
    final names = {for (final c in clinics) c.id: c.clinic.name};
    final since = pktNow().subtract(Duration(days: _days));
    final p = _person.text.trim().toLowerCase();
    final logs = ref.watch(activityProvider(_clinicId)).where((a) => a.at.isAfter(since) && _matchType(a) && (p.isEmpty || a.actorName.toLowerCase().contains(p))).toList();

    // Newest first, grouped by day.
    final byDay = <String, List<ActivityLog>>{};
    for (final a in logs) {
      (byDay[dayKey(a.at)] ??= []).add(a);
    }
    final today = dayKey(pktNow());
    final yesterday = dayKey(pktNow().subtract(const Duration(days: 1)));

    return AdminPage(
      title: 'Activity',
      subtitle: 'Everything that changed, by whom',
      children: [
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilterDrop<String>(
            value: _clinicId,
            items: [for (final c in clinics) c.id],
            label: (id) => names[id] ?? id,
            allLabel: 'All clinics',
            onChanged: (v) => setState(() => _clinicId = v),
          ),
          FilterDrop<String>(
            value: _type,
            items: _types.keys.toList(),
            label: (k) => _types[k]!,
            allLabel: 'All actions',
            onChanged: (v) => setState(() => _type = v),
          ),
          FilterDrop<int>(
            value: _days,
            items: _ranges.keys.toList(),
            label: (d) => _ranges[d]!,
            allLabel: 'Last 30 days',
            onChanged: (v) => setState(() => _days = v ?? 30),
          ),
          SizedBox(
            width: 200,
            child: TextField(
              controller: _person,
              style: ClinicText.body,
              decoration: const InputDecoration(hintText: 'Anyone', prefixIcon: Icon(Icons.person_search_outlined, size: 18)),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Text('Recorded by the system · cannot be edited', style: ClinicText.small),
        ]),
        if (logs.isEmpty)
          const EmptyState(icon: Icons.history_rounded, title: 'No activity', message: 'No activity for these filters.'),
        for (final e in byDay.entries) ...[
          const SizedBox(height: 18),
          Text((e.key == today ? 'Today' : (e.key == yesterday ? 'Yesterday' : Fmt.shortDay(e.key))).toUpperCase(), style: ClinicText.caps),
          const SizedBox(height: 8),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Column(children: [for (final (i, a) in e.value.indexed) _line(i, a, names)]),
          ),
        ],
      ],
    );
  }

  Widget _line(int index, ActivityLog a, Map<String, String> names) {
    final admin = a.actorRole == UserRole.superAdmin;
    final clinic = a.clinicId == null ? null : names[a.clinicId];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: index == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.cream))),
      child: Row(children: [
        SizedBox(width: 74, child: Text(Fmt.clock(a.at), style: ClinicText.small)),
        IconTile(activityIcon(a.action), size: 34, bg: AppColors.cream),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              admin ? CChip.tint(a.actorName) : CChip(a.actorName),
              Text(a.action, style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 3),
            Text([a.target, if (admin && clinic != null) clinic].join(' · '), style: ClinicText.small),
          ]),
        ),
      ]),
    );
  }
}
