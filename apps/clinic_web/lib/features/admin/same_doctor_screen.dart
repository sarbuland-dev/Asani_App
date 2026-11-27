import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'admin_kit.dart';

enum _Tab { suggestions, linked }

/// A-18 / A-09: "Possible same doctor" (D-32, D-33).
class SameDoctorScreen extends ConsumerStatefulWidget {
  const SameDoctorScreen({super.key});

  @override
  ConsumerState<SameDoctorScreen> createState() => _SameDoctorScreenState();
}

class _SameDoctorScreenState extends ConsumerState<SameDoctorScreen> {
  _Tab _tab = _Tab.suggestions;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final all = ref.watch(linkSuggestionsProvider);
    // Strong first, then newest.
    final open = all.where((s) => s.status == LinkStatus.open).toList()
      ..sort((a, b) {
        final c = a.strength.index.compareTo(b.strength.index);
        return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
      });
    final decided = all.where((s) => s.status == LinkStatus.notSame || s.status == LinkStatus.unlinked).toList();
    final clinics = {for (final c in ref.watch(clinicsProvider)) c.id: c.clinic};
    final addedAt = ref.watch(doctorAddedAtProvider);
    final linked = <String, List<Doctor>>{};
    for (final c in clinics.keys) {
      for (final d in ref.watch(allDoctorsProvider(c))) {
        if (d.doctorGroupId != null) (linked[d.doctorGroupId!] ??= []).add(d);
      }
    }

    return AdminPage(
      title: 'Possible same doctor',
      subtitle: 'Doctors at different clinics that may be one person',
      children: [
        Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AdminTabs<_Tab>(
            values: _Tab.values,
            selected: _tab,
            label: (t) => t == _Tab.suggestions ? 'Suggestions ${open.length}' : 'Linked doctors ${linked.length}',
            onChanged: (t) => setState(() => _tab = t),
          ),
          Text('The system never links on its own. Strong first, newest first.', style: ClinicText.small),
        ]),
        const SizedBox(height: 16),
        if (_tab == _Tab.suggestions) ...[
          if (open.isEmpty) const EmptyState(icon: Icons.verified_rounded, title: 'No open suggestions', message: 'There is nothing to review.'),
          for (final s in open) ...[_suggestion(s, clinics, addedAt), const SizedBox(height: 16)],
          if (decided.isNotEmpty) ...[
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Decided: not the same / unlinked (${decided.length})', style: ClinicText.cardTitle.copyWith(fontSize: 15)),
                const SizedBox(height: 8),
                for (final s in decided)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('${s.doctorIds.map((id) => repo.doctorById(id)?.name ?? id).join(' + ')} · ${s.status == LinkStatus.notSame ? 'not the same' : 'unlinked'}',
                        style: ClinicText.body),
                  ),
              ]),
            ),
            const SizedBox(height: 16),
          ],
        ] else ...[
          if (linked.isEmpty) const EmptyState(icon: Icons.link_off_rounded, title: 'No linked doctors', message: 'Link two records from a suggestion.'),
          for (final group in linked.values) ...[
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Column(children: [
                for (final (i, d) in group.indexed)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.cream))),
                    child: Row(children: [
                      Av.solid(d.name, size: 38),
                      const SizedBox(width: 12),
                      Expanded(child: TwoLine('${d.name} (${d.tokenPrefix})', '${d.specialityEnum.display} · ${_where(clinics[d.clinicId], d.clinicId)}')),
                      OutlinedButton(onPressed: () => runAction(context, () => repo.unlinkDoctor(d.id), success: 'Unlinked.'), child: const Text('Unlink')),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 14),
          ],
        ],
        const NoteBox.tint(
          'Link: the patient app shows one card with "Also sits at". Not the same and Unlink: this pair is never suggested again. '
          'Each clinic keeps its own record, queue and letter.',
          icon: Icons.people_alt_outlined,
        ),
      ],
    );
  }

  static String _where(Clinic? c, String id) => c == null ? id : '${c.name} · ${c.area}, ${c.city}';

  Widget _suggestion(LinkSuggestion s, Map<String, Clinic> clinics, Map<String, DateTime> addedAt) {
    final repo = ref.read(repositoryProvider);
    final strong = s.strength == LinkStrength.strong;
    final title = strong ? 'Same PMDC ${s.pmdcNumbers.whereType<String>().firstOrNull ?? ''}' : 'Same name and speciality';
    final cities = s.clinicIds.map((id) => clinics[id]?.city).whereType<String>().toSet().join(' / ');

    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          strong ? const CChip.red('Strong') : const CChip.amber('Weak'),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700))),
          Text(cities, style: ClinicText.small),
        ]),
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _record(repo.doctorById(s.doctorIds[0]), clinics, s.pmdcNumbers[0], addedAt)),
            const SizedBox(width: 12),
            const Center(child: IconTile(Icons.link_rounded)),
            const SizedBox(width: 12),
            Expanded(child: _record(repo.doctorById(s.doctorIds[1]), clinics, s.pmdcNumbers[1], addedAt)),
          ]),
        ),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          OutlinedButton(onPressed: () => runAction(context, () => repo.markNotSame(s.pairId), success: 'Marked not the same.'), child: const Text('Not the same')),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: () => runAction(context, () => repo.linkDoctors(s.pairId), success: 'Linked.'),
            icon: const Icon(Icons.link_rounded, size: 18),
            label: const Text('Link as one doctor'),
          ),
        ]),
      ]),
    );
  }

  Widget _record(Doctor? d, Map<String, Clinic> clinics, String? pmdc, Map<String, DateTime> addedAt) {
    final box = BoxDecoration(color: ClinicColors.quiet, borderRadius: BorderRadius.circular(16));
    if (d == null) return Container(padding: const EdgeInsets.all(14), decoration: box, child: Text('Doctor not found', style: AppText.bodyMedium));
    final c = clinics[d.clinicId];
    final timings = [
      for (final k in weekdayKeys)
        if (d.schedule[k] != null) '${k[0].toUpperCase()}${k.substring(1)} ${Fmt.timeRangeShort(d.schedule[k]!)}',
    ].join(', ');
    final added = addedAt[d.id];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: box,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Av.solid(d.name, size: 36),
          const SizedBox(width: 10),
          Expanded(child: TwoLine(d.name, d.specialityEnum.display)),
        ]),
        const SizedBox(height: 10),
        InfoLine('Clinic', c?.name ?? d.clinicId),
        InfoLine('Area', c == null ? '—' : '${c.area}, ${c.city}'),
        InfoLine('PMDC', pmdc ?? '—'),
        InfoLine('Timings', timings.isEmpty ? '—' : timings),
        InfoLine('Added', added == null ? '—' : WebFmt.ago(added, now: pktNow())),
      ]),
    );
  }
}
