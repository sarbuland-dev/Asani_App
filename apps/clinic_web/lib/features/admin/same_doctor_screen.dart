import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/desktop.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// A-18 / A-09: "Possible same doctor" (D-32, D-33). Plain placeholder UI:
/// the real design replaces this file; data comes from linkSuggestionsProvider.
class SameDoctorScreen extends ConsumerWidget {
  const SameDoctorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final all = ref.watch(linkSuggestionsProvider);
    final open = all.where((s) => s.status == LinkStatus.open).toList();
    final decided = all.where((s) => s.status == LinkStatus.notSame || s.status == LinkStatus.unlinked).toList();
    final clinics = {for (final c in ref.watch(clinicsProvider)) c.id: c.clinic};
    final linked = <String, List<Doctor>>{};
    for (final c in clinics.keys) {
      for (final d in ref.watch(allDoctorsProvider(c))) {
        if (d.doctorGroupId != null) (linked[d.doctorGroupId!] ??= []).add(d);
      }
    }

    String where(Doctor d) {
      final c = clinics[d.clinicId];
      return c == null ? d.clinicId : '${c.name} · ${c.area}, ${c.city}';
    }

    return PageScaffold(
      title: 'Possible same doctor',
      subtitle: 'The system only suggests. Link shows one card in the app; Not the same is never suggested again.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Suggestions (${open.length})', style: Theme.of(context).textTheme.titleMedium),
        if (open.isEmpty) const Text('No open suggestions.'),
        for (final s in open)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.strength.label),
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (var i = 0; i < 2; i++)
                    Expanded(child: _DoctorInfo(doctor: repo.doctorById(s.doctorIds[i]), where: where, pmdc: s.pmdcNumbers[i])),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  FilledButton(
                    onPressed: () => runAction(context, () => repo.linkDoctors(s.pairId), success: 'Linked.'),
                    child: const Text('Link'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => runAction(context, () => repo.markNotSame(s.pairId), success: 'Marked not the same.'),
                    child: const Text('Not the same'),
                  ),
                ]),
              ]),
            ),
          ),
        const SizedBox(height: 24),
        Text('Linked doctors (${linked.length})', style: Theme.of(context).textTheme.titleMedium),
        if (linked.isEmpty) const Text('No linked doctors.'),
        for (final group in linked.values)
          Card(
            child: Column(children: [
              for (final d in group)
                ListTile(
                  title: Text('${d.name} (${d.tokenPrefix})'),
                  subtitle: Text('${d.specialityEnum.display} · ${where(d)}'),
                  trailing: OutlinedButton(
                    onPressed: () => runAction(context, () => repo.unlinkDoctor(d.id), success: 'Unlinked.'),
                    child: const Text('Unlink'),
                  ),
                ),
            ]),
          ),
        const SizedBox(height: 24),
        Text('Decided: not the same / unlinked (${decided.length})', style: Theme.of(context).textTheme.titleMedium),
        for (final s in decided)
          Text('${s.doctorIds.map((id) => repo.doctorById(id)?.name ?? id).join(' + ')} · ${s.status.name}'),
      ]),
    );
  }
}

class _DoctorInfo extends StatelessWidget {
  const _DoctorInfo({required this.doctor, required this.where, this.pmdc});
  final Doctor? doctor;
  final String Function(Doctor) where;
  final String? pmdc;

  @override
  Widget build(BuildContext context) {
    final d = doctor;
    if (d == null) return const Text('Doctor not found');
    const keys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    final timings = [
      for (final k in keys)
        if (d.schedule[k] != null) '$k ${Fmt.timeRange(d.schedule[k]!)}',
    ].join(', ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${d.name} (${d.tokenPrefix})', style: Theme.of(context).textTheme.titleSmall),
      Text(d.specialityEnum.display),
      Text(where(d)),
      Text('PMDC: ${pmdc ?? '—'}'),
      Text('Timings: ${timings.isEmpty ? '—' : timings}'),
    ]);
  }
}
