import 'package:asani_core/asani_core.dart';
import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/error_state.dart';
import '../../data/location_service.dart';
import '../../data/providers.dart';
import 'doctor_search_providers.dart';

/// Search → Doctors tab (PRD F-13, F-14). Plain Material placeholder UI:
/// the real design replaces this file; data comes from doctor_search_providers.dart.
class DoctorsTab extends ConsumerStatefulWidget {
  const DoctorsTab({super.key, this.initialSpeciality});
  final Speciality? initialSpeciality;

  @override
  ConsumerState<DoctorsTab> createState() => _DoctorsTabState();
}

class _DoctorsTabState extends ConsumerState<DoctorsTab> {
  late Speciality? _picked = widget.initialSpeciality;

  @override
  Widget build(BuildContext context) {
    final counts = ref.watch(specialityCountsProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in Speciality.values)
              ChoiceChip(
                label: Text('${s.display} (${counts[s] ?? 0})'),
                selected: _picked == s,
                onSelected: (_) => setState(() => _picked = s),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_picked == null)
          const Text('Pick a speciality to see doctors.')
        else
          _Results(speciality: _picked!),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.speciality});
  final Speciality speciality;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final city = ref.watch(selectedCityProvider);
    final location = ref.watch(userLocationProvider).value;
    return ref.watch(doctorCardsProvider(speciality)).when(
          loading: () => const Center(child: AsaniLoader()),
          error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(clinicsProvider(city))),
          data: (cards) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${speciality.display} · ${cards.length} in $city'),
              if (location == null) const Text('Location is off: same area first, then the rest of the city.'),
              const SizedBox(height: 8),
              if (cards.isEmpty) Text('No ${speciality.display} doctors on Asani in $city yet.'),
              for (final c in cards) _DoctorCardView(card: c),
            ],
          ),
        );
  }
}

class _DoctorCardView extends ConsumerWidget {
  const _DoctorCardView({required this.card});
  final DoctorCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = card.main;
    final d = m.doctor;
    final now = ref.watch(clockProvider).value ?? pktNow();
    final day = ref.watch(queueDayProvider((doctorId: d.id, date: dayKey(now)))).value;
    final timing = d.scheduleOn(now);
    final canBook = m.availability.canBook;
    final ahead = day?.activeNumbers.length ?? 0;

    return Card(
      color: canBook ? null : Theme.of(context).disabledColor.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${d.name} (${d.tokenPrefix})', style: Theme.of(context).textTheme.titleMedium),
            Text(d.specialityEnum.display),
            Text([m.clinic.name, m.clinic.area, if (m.km != null) '${m.km!.toStringAsFixed(1)} km'].join(' · ')),
            Text(canBook ? 'Available today' : 'Not available today (${_reason(m.availability)})'),
            if (timing != null) Text('Today: ${Fmt.timeRange(timing)}'),
            if (day != null)
              Text('Tokens ${day.bookedCount} / ${d.maxTokensPerDay}'
                  ' · Now serving ${day.currentToken == 0 ? '—' : d.tokenLabel(day.currentToken)}'
                  ' · Wait ${Fmt.wait(estimatedWaitMinutes(ahead, d.avgConsultMinutes))}'),
            if (card.alsoAt.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Also sits at:'),
              for (final o in card.alsoAt)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${o.clinic.name} · ${o.clinic.area}${o.km == null ? '' : ' · ${o.km!.toStringAsFixed(1)} km'}'),
                  subtitle: Text(weeklyTimings(o.doctor)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/book/${o.clinic.id}/${o.doctor.id}'),
                ),
            ],
            const SizedBox(height: 8),
            Row(children: [
              TextButton(onPressed: () => context.push('/clinic/${m.clinic.id}'), child: const Text('Clinic')),
              const Spacer(),
              FilledButton(
                onPressed: () => context.push('/book/${m.clinic.id}/${d.id}'),
                child: Text(canBook ? 'Book token' : 'Book another day'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  static String _reason(DoctorAvailability a) => switch (a) {
        DoctorAvailability.onLeave => 'on leave',
        DoctorAvailability.full => 'tokens full',
        DoctorAvailability.ended => 'session ended',
        _ => 'no clinic today',
      };
}

/// "Mon Tue Wed · 10:00 AM – 1:00 PM" (first working day's timing).
String weeklyTimings(Doctor d) {
  const keys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  final on = [for (final k in keys) if (d.schedule[k] != null) k];
  if (on.isEmpty) return 'No timings';
  final names = on.map((k) => k[0].toUpperCase() + k.substring(1)).join(' ');
  return '$names · ${Fmt.timeRange(d.schedule[on.first]!)}';
}
