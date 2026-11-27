import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Upcoming bookings (PRD D-42): tokens booked for a later day, per doctor.
/// View only: check-in still happens on the day (BW-5).
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

    return ClinicPage(
      title: 'Upcoming bookings',
      subtitle: 'Tokens booked for a later day. Patients are checked in on the day itself.',
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in days) FilterPill(Fmt.relativeDay(d), selected: d == _date, onTap: () => setState(() => _date = d)),
        ]),
        const SizedBox(height: 18),
        tokens.when(
          loading: () => const Shimmer(height: 220),
          error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(_upcomingProvider((widget.clinicId, _date)))),
          data: (list) {
            if (list.isEmpty) {
              return EmptyState(icon: Icons.event_available_rounded, title: 'No bookings yet', message: 'No bookings for ${Fmt.longDay(_date)} yet.');
            }
            final active = list.where((t) => t.token.status != TokenStatus.cancelled).toList();
            final cancelled = list.length - active.length;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${Fmt.longDay(_date)} · ${active.length} booked${cancelled > 0 ? ' · $cancelled cancelled' : ''}', style: AppText.labelMedium),
              for (final d in doctors)
                if (list.any((t) => t.token.doctorId == d.id)) ...[
                  const SizedBox(height: 14),
                  _DoctorDay(doctor: d, tokens: list.where((t) => t.token.doctorId == d.id).toList()),
                ],
            ]);
          },
        ),
      ],
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
    return Panel(
      radius: 18,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(children: [
            Av(doctor.name, size: 34),
            const SizedBox(width: 10),
            Expanded(child: Text('${doctor.name} (${doctor.tokenPrefix})', style: AppText.titleSmall.copyWith(fontWeight: FontWeight.w800))),
            CChip.tint('$booked of ${doctor.maxTokensPerDay} booked'),
          ]),
        ),
        SimpleTable(
          columns: const [
            TableColumn('Token', flex: 2),
            TableColumn('Patient', flex: 6),
            TableColumn('Source', flex: 2),
            TableColumn('Booked', flex: 3),
            TableColumn('Status', flex: 4),
          ],
          rows: [
            for (final t in sorted)
              [
                Text(t.token.label, style: AppText.labelMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                Text(t.token.patientSnapshot.name, style: AppText.labelMedium),
                Text(t.source.label, style: AppText.bodyMedium),
                Text(Fmt.dateTime(t.token.createdAt), style: ClinicText.body),
                if (t.token.status == TokenStatus.cancelled)
                  CChip.red('Cancelled${t.cancelReason == null ? '' : ' · ${t.cancelReason}'}')
                else
                  TokenStatusChip(t.token.status),
              ],
          ],
        ),
      ]),
    );
  }
}
