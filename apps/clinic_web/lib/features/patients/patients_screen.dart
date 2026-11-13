import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/desktop.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// W-14 / C-08: search this clinic's patients by phone or name.
class PatientsScreen extends ConsumerStatefulWidget {
  const PatientsScreen(this.clinicId, {super.key});
  final String clinicId;

  @override
  ConsumerState<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends ConsumerState<PatientsScreen> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(repoTickProvider);
    final query = _q.text.trim();
    final results = query.length < 2 ? const <ClinicPatient>[] : ref.read(repositoryProvider).searchPatients(widget.clinicId, query);
    final shown = results;

    return PageScaffold(
      title: 'Patients',
      subtitle: 'Only patients who visited or booked at this clinic. Visits at other clinics are never shown.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _q,
          autofocus: true,
          style: AppText.bodyLarge,
          decoration: InputDecoration(
            hintText: 'Search by phone number (0300 1234567) or name',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _q.text.isEmpty ? null : IconButton(onPressed: () => setState(_q.clear), icon: const Icon(Icons.close_rounded)),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: Gap.xl),
        if (query.length < 2)
          const EmptyState(icon: Icons.person_search_rounded, title: 'Find a patient', message: 'Type at least 2 characters of a phone number or name.')
        else if (shown.isEmpty)
          const EmptyState(icon: Icons.search_off_rounded, title: 'No patients found', message: 'No one with this phone or name has visited this clinic.')
        else
          AppTable(
            columns: const [
              TableColumn('Patient', flex: 4),
              TableColumn('Phone', flex: 3),
              TableColumn('Relation', flex: 2),
              TableColumn('Age / Sex', flex: 2),
              TableColumn('Visits here', flex: 2),
              TableColumn('Last visit', flex: 2),
            ],
            onTap: (i) => context.go('/patients/${shown[i].patient.id}'),
            rows: [
              for (final p in shown)
                [
                  Row(children: [
                    InitialsAvatar(name: p.patient.name, size: 34, bg: InitialsAvatar.colorsFor(p.patient.relation).$1, fg: InitialsAvatar.colorsFor(p.patient.relation).$2),
                    const SizedBox(width: Gap.md),
                    Expanded(child: Text(p.patient.name, style: AppText.labelMedium, overflow: TextOverflow.ellipsis)),
                  ]),
                  Text(Fmt.phone(p.patient.phone), style: AppText.bodyMedium),
                  Text(p.patient.relation.label, style: AppText.bodyMedium),
                  Text('${p.patient.age(pktNow()) ?? '—'} / ${p.patient.gender.short}', style: AppText.bodyMedium),
                  Text('${p.visitCount}', style: AppText.labelMedium),
                  Text(p.lastVisit == null ? '—' : Fmt.shortDay(p.lastVisit!.token.date), style: AppText.bodyMedium),
                ],
            ],
          ),
      ]),
    );
  }
}
