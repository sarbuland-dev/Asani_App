import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/web/download.dart';
import '../../core/widgets/desktop.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

enum _Tab { today, upcoming, missed }

/// W-15 / C-09: Today / Upcoming / Missed follow-ups.
class FollowUpsScreen extends ConsumerStatefulWidget {
  const FollowUpsScreen(this.clinicId, {super.key});
  final String clinicId;

  @override
  ConsumerState<FollowUpsScreen> createState() => _FollowUpsScreenState();
}

class _FollowUpsScreenState extends ConsumerState<FollowUpsScreen> {
  _Tab _tab = _Tab.today;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider)!;
    final today = ref.watch(todayProvider).value ?? dayKey(pktNow());
    var all = ref.watch(followUpsProvider(widget.clinicId));
    if (user.role == StaffRole.doctor) all = all.where((f) => f.doctorId == user.doctorId).toList();
    final doctors = ref.watch(allDoctorsProvider(widget.clinicId));
    final repo = ref.watch(repositoryProvider);

    bool inTab(FollowUp f, _Tab t) => switch (t) {
          _Tab.today => f.dueDate == today,
          _Tab.upcoming => f.dueDate.compareTo(today) > 0,
          _Tab.missed => effectiveFollowUpStatus(f, today) == FollowUpStatus.missed,
        };
    int count(_Tab t) => all.where((f) => inTab(f, t)).length;
    final shown = all.where((f) => inTab(f, _tab)).toList();
    if (_tab == _Tab.missed) shown.sort((a, b) => b.dueDate.compareTo(a.dueDate));

    return PageScaffold(
      title: 'Follow-ups',
      subtitle: 'Patients get app reminders automatically. Use the Missed list to call patients back.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          for (final t in _Tab.values) ...[
            ChoiceChip(
              label: Text('${switch (t) { _Tab.today => 'Today', _Tab.upcoming => 'Upcoming', _Tab.missed => 'Missed' }} (${count(t)})'),
              selected: _tab == t,
              onSelected: (_) => setState(() => _tab = t),
            ),
            const SizedBox(width: Gap.sm),
          ],
        ]),
        const SizedBox(height: Gap.lg),
        AppTable(
          columns: const [
            TableColumn('Patient', flex: 4),
            TableColumn('Phone', flex: 3),
            TableColumn('Doctor', flex: 3),
            TableColumn('Due', flex: 2),
            TableColumn('Note', flex: 2),
            TableColumn('Status', flex: 2),
          ],
          empty: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: EmptyState(
              icon: Icons.event_available_rounded,
              title: switch (_tab) { _Tab.today => 'No follow-ups today', _Tab.upcoming => 'Nothing upcoming', _Tab.missed => 'No missed follow-ups' },
              message: 'Set a follow-up from the Called token on the Queue Board.',
            ),
          ),
          onTap: user.role.canSearchPatients ? (i) => context.go('/patients/${shown[i].patientId}') : null,
          rows: [
            for (final f in shown)
              () {
                final p = repo.patient(f.patientId);
                return <Widget>[
                  TwoLine(p?.name ?? '—', p == null ? null : '${p.relation.label} · ${p.age(pktNow()) ?? '—'} / ${p.gender.short}'),
                  Row(children: [
                    Flexible(child: Text(p == null ? '—' : Fmt.phone(p.phone), style: AppText.bodyMedium)),
                    if (p != null)
                      IconButton(
                        tooltip: 'Copy phone',
                        iconSize: 16,
                        onPressed: () async {
                          await copyText(p.phone);
                          if (context.mounted) showSnack(context, 'Phone number copied.');
                        },
                        icon: const Icon(Icons.copy_rounded),
                      ),
                  ]),
                  Text(doctors.where((d) => d.id == f.doctorId).firstOrNull?.name ?? '—', style: AppText.bodyMedium),
                  Text(Fmt.relativeDay(f.dueDate), style: AppText.labelMedium),
                  Text(f.note ?? '—', style: AppText.bodyMedium),
                  FollowUpPill(effectiveFollowUpStatus(f, today)),
                ];
              }(),
          ],
        ),
      ]),
    );
  }
}
