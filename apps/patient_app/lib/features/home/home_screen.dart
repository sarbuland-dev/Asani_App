import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:asani_ui/asani_ui.dart';
import '../../data/providers.dart';
import '../clinic/clinic_card.dart';
import '../shell/main_shell.dart';
import '../tokens/token_widgets.dart';
import '../../core/widgets/error_state.dart';

/// S-05 Home (PRD F-02).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final city = ref.watch(selectedCityProvider);
    final clinics = ref.watch(clinicsProvider(city));
    final recent = ref.watch(recentClinicsProvider).value ?? const [];
    // Keeps the city list loaded for the city picker (unwatched providers are paused).
    ref.watch(citiesProvider);
    final active = ref.watch(myActiveTokensProvider).value ?? const [];
    final followUps = ref.watch(upcomingFollowUpsProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(clinicsProvider(city)),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Header(name: user?.name ?? '', city: city)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.lg, Gap.screen, kNavBarClearance),
              sliver: SliverList.list(
                children: [
                  if (active.isNotEmpty) _ActiveTokens(tokens: active),
                  if (followUps.isNotEmpty) ...[
                    const SizedBox(height: Gap.lg),
                    for (final f in followUps.take(2)) _FollowUpCard(followUp: f),
                  ],
                  if (recent.isNotEmpty) ...[
                    const SectionTitle('Recent clinics'),
                    SizedBox(
                      // Grows with the user's text size (up to 1.3×).
                      height: 52 + MediaQuery.textScalerOf(context).scale(84),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        itemCount: recent.length,
                        separatorBuilder: (_, _) => const SizedBox(width: Gap.md),
                        itemBuilder: (_, i) => _RecentClinicCard(clinic: recent[i]),
                      ),
                    ),
                  ],
                  SectionTitle(
                    'All clinics in $city',
                    trailing: TextButton(onPressed: () => context.push('/search'), child: const Text('See all')),
                  ),
                  ...clinics.when(
                    loading: () => [const SkeletonList()],
                    error: (e, _) => [ErrorState(error: e, onRetry: () => ref.invalidate(clinicsProvider(city)))],
                    data: (list) => list.isEmpty
                        ? [
                            EmptyState(
                              icon: Icons.local_hospital_outlined,
                              title: 'No clinics yet',
                              message: 'Asani is not in $city yet. Try another city.',
                              actionLabel: 'Change city',
                              onAction: () => showCityPicker(context, ref),
                            ),
                          ]
                        : [for (final c in list) ClinicCard(clinic: c)],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.name, required this.city});
  final String name;
  final String city;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstName = name.split(' ').first;
    return GradientHeader(
      child: Column(
        children: [
          Row(
            children: [
              InitialsAvatar(name: name, size: 44, bg: AppColors.onPrimary.withValues(alpha: 0.2)),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Fmt.greeting(), style: AppText.bodyMedium.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.85))),
                    Text(firstName,
                        style: AppText.titleLarge.copyWith(color: AppColors.onPrimary), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Material(
                color: AppColors.onPrimary.withValues(alpha: 0.18),
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => showCityPicker(context, ref),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm + 2),
                    child: Row(children: [
                      const Icon(Icons.location_on_outlined, size: 16, color: AppColors.onPrimary),
                      const SizedBox(width: 4),
                      Text(city, style: AppText.labelMedium.copyWith(color: AppColors.onPrimary)),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.onPrimary),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Material(
                color: AppColors.onPrimary.withValues(alpha: 0.18),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'My tokens',
                  onPressed: () => context.go('/tokens'),
                  icon: const Icon(Icons.notifications_none_rounded, color: AppColors.onPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.lg),
          Material(
            color: AppColors.surface,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => context.push('/search'),
              child: Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                child: Row(children: [
                  const Icon(Icons.search_rounded, color: AppColors.textSecondary),
                  const SizedBox(width: Gap.md),
                  Text('Search clinic or area', style: AppText.bodyLarge.copyWith(color: AppColors.textMuted)),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showCityPicker(BuildContext context, WidgetRef ref) async {
  final current = ref.read(selectedCityProvider);
  var loaded = ref.read(citiesProvider).value;
  if (loaded == null) {
    try {
      loaded = await ref.read(citiesProvider.future).timeout(const Duration(seconds: 5));
    } catch (_) {
      loaded = const <String>[]; // offline: show only the current city
    }
    if (!context.mounted) return;
  }
  final cities = loaded.contains(current) ? loaded : [current, ...loaded];
  final picked = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true, // above the floating nav bar
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.sm),
            child: Text('Choose your city', style: AppText.titleLarge),
          ),
          for (final c in cities)
            ListTile(
              minTileHeight: 56,
              contentPadding: const EdgeInsets.symmetric(horizontal: Gap.xl),
              title: Text(c, style: AppText.bodyLarge),
              trailing: c == current ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
              onTap: () => Navigator.pop(ctx, c),
            ),
          const SizedBox(height: Gap.md),
        ],
      ),
    ),
  );
  if (picked != null) await ref.read(authRepositoryProvider).setCity(picked);
}

class _ActiveTokens extends StatefulWidget {
  const _ActiveTokens({required this.tokens});
  final List<Token> tokens;

  @override
  State<_ActiveTokens> createState() => _ActiveTokensState();
}

class _ActiveTokensState extends State<_ActiveTokens> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.tokens.length == 1) return ActiveTokenBanner(token: widget.tokens.first);
    // Several active tokens → swipeable cards sized to their content (DESIGN S-05).
    final width = MediaQuery.sizeOf(context).width - Gap.screen * 2 - 24;
    return Column(children: [
      NotificationListener<ScrollNotification>(
        onNotification: (n) {
          final page = (n.metrics.pixels / (width + Gap.sm)).round().clamp(0, widget.tokens.length - 1);
          if (page != _page) setState(() => _page = page);
          return false;
        },
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final t in widget.tokens)
                  Padding(
                    padding: const EdgeInsets.only(right: Gap.sm),
                    child: SizedBox(width: width, child: ActiveTokenBanner(token: t)),
                  ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: Gap.sm),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < widget.tokens.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _page ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == _page ? AppColors.primary : AppColors.border,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
            ),
        ],
      ),
    ]);
  }
}

class _FollowUpCard extends ConsumerWidget {
  const _FollowUpCard({required this.followUp});
  final FollowUp followUp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patient = (ref.watch(myPatientsProvider).value ?? const []).where((p) => p.id == followUp.patientId).firstOrNull;
    final doctor = ref.watch(doctorProvider(followUp.doctorId)).value;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: AppCard(
        padding: const EdgeInsets.all(Gap.md),
        child: Row(children: [
          const IconBox(icon: Icons.event_outlined, bg: AppColors.warningContainer, fg: AppColors.warning),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Upcoming follow-up', style: AppText.labelSmall.copyWith(color: AppColors.warning, fontWeight: FontWeight.w600)),
              Text(patient?.name ?? '', style: AppText.titleMedium.copyWith(fontSize: 16)),
              Text('${doctor?.name ?? ''} · Due ${Fmt.shortDay(followUp.dueDate)}', style: AppText.bodyMedium),
            ]),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(72, 44)),
            onPressed: () => context.push(followUpBookingPath(followUp)),
            child: const Text('Book'),
          ),
        ]),
      ),
    );
  }
}

/// Pre-filled booking from a follow-up (PRD F-09).
String followUpBookingPath(FollowUp f) => '/book/${f.clinicId}/${f.doctorId}?patient=${f.patientId}&date=${f.dueDate}';

class _RecentClinicCard extends ConsumerWidget {
  const _RecentClinicCard({required this.clinic});
  final Clinic clinic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctors = ref.watch(doctorsByClinicProvider).value?[clinic.id] ?? const <Doctor>[];
    final open = clinicOpenOn(doctors, pktNow());
    final suspended = !clinic.status.acceptsBookings;
    return SizedBox(
      width: 160,
      child: AppCard(
        onTap: () => context.push('/clinic/${clinic.id}'),
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const IconBox(icon: Icons.local_hospital_outlined, size: 36),
            const Spacer(),
            Text(clinic.name, style: AppText.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(clinic.area, style: AppText.labelSmall, maxLines: 1),
            const SizedBox(height: 2),
            Text(
              suspended ? 'Booking unavailable' : (open ? 'Open today' : 'Closed today'),
              style: AppText.labelSmall.copyWith(
                  color: suspended ? AppColors.textSecondary : (open ? AppColors.success : AppColors.textSecondary),
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
