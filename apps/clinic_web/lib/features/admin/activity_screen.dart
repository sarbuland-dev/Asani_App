import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/desktop.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

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
    return Column(children: [
      for (final a in logs)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InitialsAvatar(name: a.actorName, size: 32, bg: a.actorRole == UserRole.superAdmin ? AppColors.avatarCool : AppColors.primaryContainer, fg: a.actorRole == UserRole.superAdmin ? AppColors.secondary : AppColors.primary),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: a.actorName, style: AppText.labelMedium),
                  TextSpan(text: ' ${a.action} ', style: AppText.bodyMedium),
                  TextSpan(text: a.target, style: AppText.labelMedium),
                  if (clinicId == null && a.clinicId != null) TextSpan(text: '  ·  ${clinics[a.clinicId] ?? ''}', style: AppText.labelSmall),
                ]),
              ),
            ),
            Text(WebFmt.ago(a.at, now: pktNow()), style: AppText.labelSmall),
          ]),
        ),
    ]);
  }
}

/// A-16 / A-07: activity log with filters.
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

    return PageScaffold(
      title: 'Activity log',
      subtitle: 'Recorded by the backend. Clinics cannot edit or skip it.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(
            width: 240,
            child: DropdownButtonFormField<String?>(
              initialValue: _clinicId,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.local_hospital_outlined)),
              items: [const DropdownMenuItem(value: null, child: Text('All clinics')), for (final c in clinics) DropdownMenuItem(value: c.id, child: Text(c.clinic.name))],
              onChanged: (v) => setState(() => _clinicId = v),
            ),
          ),
          const SizedBox(width: Gap.md),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String?>(
              initialValue: _type,
              items: [const DropdownMenuItem(value: null, child: Text('All actions')), for (final e in _types.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _type = v),
            ),
          ),
          const SizedBox(width: Gap.md),
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<int>(
              initialValue: _days,
              items: const [
                DropdownMenuItem(value: 1, child: Text('Last 24 hours')),
                DropdownMenuItem(value: 7, child: Text('Last 7 days')),
                DropdownMenuItem(value: 30, child: Text('Last 30 days')),
                DropdownMenuItem(value: 365, child: Text('Last year')),
              ],
              onChanged: (v) => setState(() => _days = v ?? 30),
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: TextField(
              controller: _person,
              decoration: const InputDecoration(hintText: 'Person', prefixIcon: Icon(Icons.person_search_outlined)),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
        const SizedBox(height: Gap.lg),
        AppTable(
          columns: const [
            TableColumn('Time', flex: 2),
            TableColumn('Clinic', flex: 3),
            TableColumn('Who', flex: 3),
            TableColumn('Action', flex: 3),
            TableColumn('Target', flex: 4),
          ],
          empty: const Padding(padding: EdgeInsets.all(Gap.xl), child: Center(child: Text('No activity for these filters.'))),
          rows: [
            for (final a in logs)
              [
                TwoLine(WebFmt.ago(a.at, now: pktNow()), Fmt.dateTime(a.at)),
                Text(a.clinicId == null ? '—' : names[a.clinicId] ?? '—', style: AppText.bodyMedium),
                TwoLine(a.actorName, a.actorRole.label),
                Text(a.action, style: AppText.labelMedium),
                Text(a.target, style: AppText.bodyMedium),
              ],
          ],
        ),
      ]),
    );
  }
}
