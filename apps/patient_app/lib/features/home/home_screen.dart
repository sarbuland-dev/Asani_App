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

/// S-05 Home (PRD F-02). Design "ticket stack" (2026-11-17): a green header
/// with the greeting, the city and the user's active tokens drawn as stacked
/// paper slips; then search, follow-ups, recent clinics and all clinics.
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

    return StatusBarScrim(
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: () async => ref.invalidate(clinicsProvider(city)),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Header(name: user?.name ?? '', city: city, tokens: active)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.lg, Gap.screen, kNavBarClearance),
                sliver: SliverList.list(
                  children: [
                    const _SearchBar(),
                    if (followUps.isNotEmpty) ...[
                      const SizedBox(height: Gap.md),
                      for (final f in followUps.take(2)) _FollowUpCard(followUp: f),
                    ],
                    if (recent.isNotEmpty) ...[
                      const SectionTitle('Recent clinics'),
                      _RecentClinics(clinics: recent),
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
      ),
    );
  }
}

/// Green header: avatar, date, greeting, city pill and the ticket stack.
class _Header extends ConsumerWidget {
  const _Header({required this.name, required this.city, required this.tokens});
  final String name;
  final String city;
  final List<Token> tokens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstName = name.split(' ').first;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.md, Gap.screen, Gap.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  InitialsAvatar(name: name, size: 44, bg: AppColors.headerChip),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(Fmt.greeting(),
                            style: AppText.bodyMedium.copyWith(color: AppColors.primaryContainer),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(firstName,
                            style: AppText.titleLarge.copyWith(color: AppColors.onPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Material(
                    color: AppColors.headerChip,
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
                ],
              ),
              if (tokens.isEmpty) ...[
                const SizedBox(height: Gap.lg),
                const _NoTokenSlip(),
              ],
              if (tokens.isNotEmpty) ...[
                const SizedBox(height: Gap.lg),
                Row(children: [
                  Expanded(
                    child: Text(tokens.length == 1 ? 'Your token' : 'Your tokens',
                        style: AppText.labelLarge.copyWith(color: AppColors.onPrimary)),
                  ),
                  Text('${tokens.length} active', style: AppText.bodyMedium.copyWith(color: AppColors.primaryContainer)),
                ]),
                const SizedBox(height: Gap.sm),
                _TicketStack(tokens: tokens),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// What the token area shows when there is no active token: an outlined
/// "ghost" slip that invites the first (or next) booking.
class _NoTokenSlip extends ConsumerWidget {
  const _NoTokenSlip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final everBooked = (ref.watch(myTokensProvider).value ?? const []).isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: AppColors.headerChip,
        borderRadius: BorderRadius.circular(Radii.card + 2),
        border: Border.all(color: AppColors.primarySoft.withValues(alpha: 0.6), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(Radii.button)),
              child: const Icon(Icons.confirmation_number_outlined, color: AppColors.primaryContainer),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(everBooked ? 'No active token' : 'Book your first token',
                    style: AppText.titleSmall.copyWith(color: AppColors.onPrimary)),
                const SizedBox(height: 2),
                Text('Find a clinic, pick a doctor and get your number in under a minute.',
                    style: AppText.bodyMedium.copyWith(color: AppColors.primaryContainer)),
              ]),
            ),
          ]),
          const SizedBox(height: Gap.md),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.onPrimary,
              foregroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => context.push('/search'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Book a token'),
          ),
        ],
      ),
    );
  }
}

/// Active tokens as stacked paper slips; swipe sideways when there are
/// several. The paler slips peeking out behind say "there is more than one".
class _TicketStack extends StatefulWidget {
  const _TicketStack({required this.tokens});
  final List<Token> tokens;

  @override
  State<_TicketStack> createState() => _TicketStackState();
}

class _TicketStackState extends State<_TicketStack> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final many = tokens.length > 1;
    // Grows with the user's text size (body-text factor: Android 14+ scales
    // big sizes less, so a factor from a big size would come out too small).
    final f = MediaQuery.textScalerOf(context).scale(14) / 14;
    // Matches the ticket's content (padding, chip row, tear line, name line,
    // token code) so the slip hugs it with no empty band.
    final ticketHeight = 50 + 76 * f;
    const peek = 20.0;
    final page = _page.clamp(0, tokens.length - 1);

    return Column(children: [
      SizedBox(
        height: ticketHeight + (many ? peek : 0),
        child: Stack(children: [
          if (many) ...[
            Positioned(
              left: Gap.lg,
              right: Gap.lg,
              top: 0,
              height: ticketHeight - Gap.md,
              child: DecoratedBox(
                decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(Radii.card + 2)),
              ),
            ),
            Positioned(
              left: Gap.sm,
              right: Gap.sm,
              top: peek / 2,
              height: ticketHeight - Gap.md,
              child: DecoratedBox(
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(Radii.card + 2)),
              ),
            ),
          ],
          Positioned(
            left: 0,
            right: 0,
            top: many ? peek : 0,
            height: ticketHeight,
            child: PageView.builder(
              controller: _controller,
              itemCount: tokens.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Align(alignment: Alignment.topCenter, child: TokenTicket(token: tokens[i])),
              ),
            ),
          ),
        ]),
      ),
      if (many)
        Padding(
          padding: const EdgeInsets.only(top: Gap.md),
          child: Semantics(
            label: 'Token ${page + 1} of ${tokens.length}. Swipe for more.',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < tokens.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == page ? AppColors.onPrimary : AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
              ],
            ),
          ),
        ),
    ]);
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Search clinic or area',
        excludeSemantics: true,
        child: Material(
          color: AppColors.surface,
          shape: const StadiumBorder(side: BorderSide(color: AppColors.border)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => context.push('/search'),
            child: SizedBox(
              height: 54,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                child: Row(children: [
                  const Icon(Icons.search_rounded, color: AppColors.primary),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text('Search clinic or area',
                        style: AppText.bodyLarge.copyWith(color: AppColors.textSecondary), overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
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
        color: AppColors.muted,
        borderColor: AppColors.muted,
        padding: const EdgeInsets.all(Gap.md),
        child: Row(children: [
          const IconBox(icon: Icons.event_outlined),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Follow-up due ${Fmt.shortDay(followUp.dueDate)}',
                  style: AppText.labelSmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
              Text(patient?.name ?? '', style: AppText.titleSmall),
              Text(doctor?.name ?? '', style: AppText.bodyMedium),
            ]),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(72, 48)),
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

/// Recent clinics as one tidy card of rows (initials, name, area, open state).
class _RecentClinics extends ConsumerWidget {
  const _RecentClinics({required this.clinics});
  final List<Clinic> clinics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byClinic = ref.watch(doctorsByClinicProvider).value ?? const <String, List<Doctor>>{};
    final now = nowFrom(ref);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < clinics.length; i++) ...[
          if (i > 0) const Divider(indent: Gap.lg, endIndent: Gap.lg),
          _RecentRow(clinic: clinics[i], info: clinicOpenInfo(byClinic[clinics[i].id] ?? const [], now)),
        ],
      ]),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.clinic, required this.info});
  final Clinic clinic;
  final ({bool open, String label, String? hours, String? nextOpen}) info;

  @override
  Widget build(BuildContext context) {
    final suspended = !clinic.status.acceptsBookings;
    final open = info.open && !suspended;
    final status = suspended ? 'Unavailable' : (open ? 'Open' : 'Closed');
    return InkWell(
      onTap: () => context.push('/clinic/${clinic.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
        child: Row(children: [
          ClinicInitials(name: clinic.name, active: open),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(clinic.name, style: AppText.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                open || suspended ? clinic.area : '${clinic.area} · ${info.nextOpen ?? info.label}',
                style: AppText.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          const SizedBox(width: Gap.sm),
          Text(status, style: AppText.labelMedium.copyWith(color: open ? AppColors.success : AppColors.textSecondary)),
        ]),
      ),
    );
  }
}
