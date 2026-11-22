import 'package:asani_core/asani_core.dart';
import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/error_state.dart';
import '../../data/location_service.dart';
import '../../data/providers.dart';
import 'doctor_search_providers.dart';
import 'speciality_icons.dart';

/// Search → Doctors tab (PRD F-13, F-14; board P3 S-06b). A grid of
/// speciality tiles ("What do you need help with?"); picking one shows that
/// speciality's doctor cards, nearest clinic first. The S-18 location sheet
/// is shown once, the first time this tab opens.
class DoctorsTab extends ConsumerStatefulWidget {
  const DoctorsTab({super.key, this.initialSpeciality});
  final Speciality? initialSpeciality;

  @override
  ConsumerState<DoctorsTab> createState() => _DoctorsTabState();
}

class _DoctorsTabState extends ConsumerState<DoctorsTab> {
  late Speciality? _picked = widget.initialSpeciality;
  bool _more = false;
  bool _askedLocation = false;

  /// The 11 tiles on the board; the rest open with "More".
  static const _main = [
    Speciality.generalPhysician,
    Speciality.child,
    Speciality.heart,
    Speciality.teeth,
    Speciality.skin,
    Speciality.womensHealth,
    Speciality.eye,
    Speciality.ent,
    Speciality.bones,
    Speciality.diabetes,
    Speciality.stomach,
  ];

  void _maybeAskLocation() {
    if (_askedLocation) return;
    final seen = ref.read(locationPrimerSeenProvider).value;
    final access = ref.read(locationAccessProvider).value;
    if (seen == null || access == null) return;
    _askedLocation = true;
    if (seen || access == LocationAccess.granted) return;
    // S-18 (D-31): asked once, the first time the Doctors tab is used.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showLocationPrimer(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(locationPrimerSeenProvider);
    ref.watch(locationAccessProvider);
    _maybeAskLocation();
    final picked = _picked;
    if (picked != null) {
      return _Results(speciality: picked, onBack: () => setState(() => _picked = null));
    }
    final tiles = _more ? Speciality.values : _main;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text('What do you need help with?',
              style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.textSecondary)),
        ),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            // Icon + two text lines; taller when the text is bigger.
            mainAxisExtent: 84 + 36 * MediaQuery.textScalerOf(context).scale(14) / 14,
          ),
          children: [
            for (final s in tiles) _SpecialityTile(s: s, onTap: () => setState(() => _picked = s)),
            if (!_more) _SpecialityTile(s: null, onTap: () => setState(() => _more = true)),
          ],
        ),
      ],
    );
  }
}

/// Board tile: soft green gradient, white icon circle, short name and term.
class _SpecialityTile extends StatelessWidget {
  const _SpecialityTile({required this.s, required this.onTap});

  /// null = "More".
  final Speciality? s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sp = s;
    final title = sp == null ? 'More' : _short(sp);
    final sub = sp == null ? 'Kidney, Brain…' : (sp.term ?? _sub(sp));
    return Semantics(
      button: true,
      label: sp == null ? 'More specialities' : sp.display,
      excludeSemantics: true,
      child: Material(
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFB9D3CA)),
              gradient: const LinearGradient(
                begin: Alignment(-0.3, -1),
                end: Alignment(0.3, 1),
                colors: [Color(0xFFE8F1EE), Color(0xFFCDE2DA)],
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Center(child: SpecialityIcon(sp, color: AppColors.primary)),
              ),
              const SizedBox(height: Gap.sm),
              Text(title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.labelMedium.copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
              Text(sub,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.labelSmall.copyWith(fontSize: 11, color: const Color(0xFF3D5D57))),
            ]),
          ),
        ),
      ),
    );
  }

  static String _short(Speciality s) => switch (s) {
        Speciality.generalPhysician => 'General',
        Speciality.child => 'Child',
        Speciality.womensHealth => "Women's",
        Speciality.ent => 'ENT',
        _ => s.label.split(RegExp(r' & | ')).first,
      };

  static String _sub(Speciality s) => switch (s) {
        Speciality.generalPhysician => 'Physician',
        Speciality.child => 'Specialist',
        Speciality.ent => 'Ear Nose Throat',
        _ => s.label,
      };
}

class _Results extends ConsumerWidget {
  const _Results({required this.speciality, required this.onBack});
  final Speciality speciality;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final city = ref.watch(selectedCityProvider);
    final location = ref.watch(userLocationProvider).value;
    return ref.watch(doctorCardsProvider(speciality)).when(
          loading: () => const Center(child: AsaniLoader()),
          error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(clinicsProvider(city))),
          data: (cards) => ListView(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.xxl),
            children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${speciality.label} doctors', style: AppText.titleMedium.copyWith(fontWeight: FontWeight.w800)),
                    Text('${cards.length} in $city${location == null ? '' : ' · nearest first'}', style: AppText.labelSmall),
                  ]),
                ),
                TextButton.icon(onPressed: onBack, icon: const Icon(Icons.grid_view_rounded, size: 18), label: const Text('All')),
              ]),
              if (location == null) ...[
                const SizedBox(height: Gap.sm),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                  decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    const Icon(Icons.location_on_outlined, size: 18, color: AppColors.primary),
                    const SizedBox(width: Gap.sm),
                    Expanded(child: Text('Turn on location to see the nearest first.', style: AppText.labelSmall)),
                    TextButton(onPressed: () => askForLocation(ref), child: const Text('Turn on')),
                  ]),
                ),
              ],
              const SizedBox(height: Gap.md),
              if (cards.isEmpty)
                EmptyState(
                  icon: Icons.medical_services_outlined,
                  title: 'No ${speciality.label} doctors yet',
                  message: 'No ${speciality.display} doctors on Asani in $city yet.',
                  actionLabel: 'Pick another',
                  onAction: onBack,
                ),
              for (final c in cards) _DoctorCardView(card: c),
            ],
          ),
        );
  }
}

/// Board P3 doctor card: initials with a status dot, name, speciality and
/// distance; a cream tile with today's clinic and timing and the queue;
/// "Also sits at"; Book token (or "Book another day" when not today).
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
    final running = day?.sessionStatus == SessionStatus.running || day?.sessionStatus == SessionStatus.paused;
    final km = m.km == null ? null : '${m.km! < 10 ? m.km!.toStringAsFixed(1) : m.km!.round()} km';

    final head = Row(children: [
      SizedBox.square(
        dimension: 48,
        child: Stack(children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: canBook ? AppColors.primaryContainer : AppColors.cream, shape: BoxShape.circle),
            child: Text(Fmt.initials(d.name),
                style: AppText.labelLarge.copyWith(color: canBook ? AppColors.primary : AppColors.textSecondary, fontWeight: FontWeight.w700)),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: canBook ? AppColors.success : AppColors.danger,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(width: Gap.md),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d.name,
              style: AppText.labelLarge.copyWith(
                  fontSize: 15, fontWeight: FontWeight.w700, color: canBook ? AppColors.textPrimary : AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text(
            canBook ? d.specialityEnum.display : _reason(m.availability),
            style: AppText.labelSmall.copyWith(color: canBook ? AppColors.textSecondary : AppColors.dangerText),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ]),
      ),
      if (km != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(Radii.pill)),
          child: Text(km, style: AppText.labelSmall.copyWith(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
    ]);

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: canBook ? AppColors.surface : AppColors.background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          head,
          if (canBook) ...[
            const SizedBox(height: Gap.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(14)),
              child: IntrinsicHeight(
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Available today',
                          style: AppText.labelMedium.copyWith(color: AppColors.success, fontWeight: FontWeight.w700)),
                      Text('${m.clinic.name}${timing == null ? '' : ' · ${Fmt.timeRangeShort(timing)}'}',
                          style: AppText.labelSmall.copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  const VerticalDivider(width: 24, color: AppColors.border),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        running && day != null
                            ? '${day.currentToken == 0 ? '—' : d.tokenLabel(day.currentToken)} · ${day.bookedCount}/${d.maxTokensPerDay}'
                            : '~${Fmt.wait(estimatedWaitMinutes(ahead, d.avgConsultMinutes))}',
                        style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(running ? 'Serving · booked' : 'Est. wait', style: AppText.labelSmall.copyWith(fontSize: 11)),
                    ]),
                  ),
                ]),
              ),
            ),
          ],
          for (final o in card.alsoAt)
            InkWell(
              onTap: () => context.push('/book/${o.clinic.id}/${o.doctor.id}'),
              child: Padding(
                padding: const EdgeInsets.only(top: Gap.md),
                child: Row(children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'Also sits at '),
                        TextSpan(text: o.clinic.name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                        TextSpan(text: ' · ${weeklyTimings(o.doctor)}'),
                      ]),
                      style: AppText.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.primary),
                ]),
              ),
            ),
          const SizedBox(height: Gap.md),
          if (canBook)
            FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => context.push('/book/${m.clinic.id}/${d.id}'),
              child: const Text('Book token ›'),
            )
          else
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                side: const BorderSide(color: AppColors.primary, width: 1.5),
                backgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => context.push('/book/${m.clinic.id}/${d.id}'),
              child: const Text('Book another day'),
            ),
        ]),
      ),
    );
  }

  static String _reason(DoctorAvailability a) => switch (a) {
        DoctorAvailability.onLeave => 'On leave today',
        DoctorAvailability.full => 'Tokens full today',
        DoctorAvailability.ended => 'Session ended today',
        _ => 'No clinic today',
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

/// S-18 location primer as a bottom sheet (board P3): pin in a cream circle,
/// "Find doctors near you", Allow location / Not now. Shown once per phone.
Future<void> showLocationPrimer(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.xl, Gap.xl),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(color: AppColors.cream, shape: BoxShape.circle),
              child: Center(
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.location_on_outlined, size: 30, color: AppColors.onPrimary),
                ),
              ),
            ),
          ),
          const SizedBox(height: Gap.lg),
          Text('Find doctors near you',
              textAlign: TextAlign.center, style: AppText.titleLarge.copyWith(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: Gap.sm),
          Text('We use your location only to show the nearest clinics first. It is never saved or shared.',
              textAlign: TextAlign.center, style: AppText.bodyLarge.copyWith(fontSize: 15, color: AppColors.textSecondary, height: 1.55)),
          const SizedBox(height: Gap.lg),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await askForLocation(ref);
            },
            child: const Text('Allow location'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Not now')),
        ]),
      ),
    ),
  );
  // Either way, never shown again on this phone (D-31).
  await ref.read(locationPrimerSeenProvider.notifier).markSeen();
}
