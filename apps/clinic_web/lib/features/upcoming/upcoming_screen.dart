import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/desktop.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Upcoming bookings (PRD D-42): tokens booked for a later day, per doctor.
/// View only: check-in still happens on the day (BW-5). Plain placeholder UI.
final _upcomingProvider = FutureProvider.autoDispose.family<List<QueueToken>, (String, String)>((ref, a) {
  ref.watch(repoTickProvider); // reload when the backend changes
  return ref.watch(repositoryProvider).loadTokens(a.$1, a.$2, a.$2);
});

class UpcomingScreen extends ConsumerStatefulWidget {
  const UpcomingScreen(this.clinicId, {super.key});
  final String clinicId;

  @override
  ConsumerState<UpcomingScreen> createState() => _UpcomingScreenState();
}

class _UpcomingScreenState extends ConsumerState<UpcomingScreen> {
  late final DateTime _today = parseDayKey(dayKey(pktNow()));
  late String _date = dayKey(_today.add(const Duration(days: 1)));

  @override
  Widget build(BuildContext context) {
    final doctors = ref.watch(allDoctorsProvider(widget.clinicId));
    // Tomorrow up to the longest booking window of this clinic's doctors (default 7).
    final window = doctors.isEmpty ? 7 : doctors.map((d) => d.bookingWindowDays).reduce((a, b) => a > b ? a : b).clamp(1, 60);
    final days = [for (var i = 1; i <= window; i++) dayKey(_today.add(Duration(days: i)))];
    final tokens = ref.watch(_upcomingProvider((widget.clinicId, _date)));

    return PageScaffold(
      title: 'Upcoming bookings',
      subtitle: 'Tokens booked for a later day. Patients are checked in on the day itself.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in days)
            ChoiceChip(label: Text(Fmt.relativeDay(d)), selected: d == _date, onSelected: (_) => setState(() => _date = d)),
        ]),
        const SizedBox(height: 16),
        tokens.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Could not load bookings: $e'),
          data: (list) {
            final active = list.where((t) => t.token.status != TokenStatus.cancelled).toList();
            final cancelled = list.length - active.length;
            if (list.isEmpty) return Text('No bookings for ${Fmt.longDay(_date)} yet.');
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${Fmt.longDay(_date)} · ${active.length} booked${cancelled > 0 ? ' · $cancelled cancelled' : ''}'),
              for (final d in doctors)
                if (list.any((t) => t.token.doctorId == d.id)) _DoctorDay(doctor: d, tokens: list.where((t) => t.token.doctorId == d.id).toList()),
            ]);
          },
        ),
      ]),
    );
  }
}

class _DoctorDay extends StatelessWidget {
  const _DoctorDay({required this.doctor, required this.tokens});
  final Doctor doctor;
  final List<QueueToken> tokens;

  @override
  Widget build(BuildContext context) {
    final sorted = [...tokens]..sort((a, b) => a.token.number.compareTo(b.token.number));
    final booked = sorted.where((t) => t.token.status != TokenStatus.cancelled).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${doctor.name} (${doctor.tokenPrefix}) · $booked of ${doctor.maxTokensPerDay} booked',
              style: Theme.of(context).textTheme.titleMedium),
          for (final t in sorted)
            ListTile(
              dense: true,
              leading: Text(t.token.label),
              title: Text(t.token.patientSnapshot.name),
              subtitle: Text([
                t.source == TokenSource.walkIn ? 'Walk-in' : 'App',
                'booked ${Fmt.dateTime(t.token.createdAt)}',
                if (t.token.status == TokenStatus.cancelled) 'CANCELLED${t.cancelReason == null ? '' : ' · ${t.cancelReason}'}',
              ].join(' · ')),
            ),
        ]),
      ),
    );
  }
}
