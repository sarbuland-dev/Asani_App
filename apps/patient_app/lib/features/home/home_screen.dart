import 'dart:math' as math;

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
                const _HowItWorks(),
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

/// What the token area shows when there is no active token: "How Asani
/// works" in three steps, with a gentle animation. The steps rise in one by
/// one, then a highlight walks 1 → 2 → 3 (the step's icon gives a small hop)
/// while a bar fills underneath, and starts again. Static when the OS asks
/// for less motion. As soon as a token is active, the ticket cards replace it.
class _HowItWorks extends ConsumerStatefulWidget {
  const _HowItWorks();

  @override
  ConsumerState<_HowItWorks> createState() => _HowItWorksState();
}

class _HowItWorksState extends ConsumerState<_HowItWorks> with TickerProviderStateMixin {
  static const _steps = [
    (Icons.search_rounded, 'Find a clinic'),
    (Icons.confirmation_number_outlined, 'Book a token'),
    (Icons.notifications_active_outlined, 'Come when called'),
  ];

  /// Steps rising in, once.
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  /// Highlight walking over the steps, 2.2 s each, forever.
  late final _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 6600));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
      _loop.value = 0;
    } else {
      _intro.forward().whenComplete(() {
        if (mounted) _loop.repeat();
      });
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      label: 'How Asani works: 1, find a clinic. 2, book a token. 3, come when you are called.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('How Asani works', style: AppText.labelLarge.copyWith(color: AppColors.onPrimary)),
          const SizedBox(height: Gap.sm),
          ExcludeSemantics(
            child: AnimatedBuilder(
              animation: Listenable.merge([_intro, _loop]),
              builder: (context, _) {
                // Which step is lit, and how far through it (0..1).
                final t = _loop.value * _steps.length;
                final active = still ? -1 : t.floor().clamp(0, _steps.length - 1);
                final within = t - t.floor();
                return Column(children: [
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < _steps.length; i++) ...[
                          Expanded(child: _rise(i, _StepTile(n: i + 1, step: _steps[i], lit: i == active, hop: i == active ? within : 0))),
                          if (i < _steps.length - 1)
                            Center(
                              child: Icon(Icons.chevron_right_rounded,
                                  size: 18, color: i < active ? AppColors.onPrimary : AppColors.primarySoft),
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: Gap.md),
                  // Progress bar: one segment per step, filling with the highlight.
                  Row(children: [
                    for (var i = 0; i < _steps.length; i++) ...[
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.pill),
                          child: LinearProgressIndicator(
                            value: still ? 1 : (i < active ? 1 : (i == active ? within : 0)),
                            minHeight: 4,
                            backgroundColor: AppColors.headerChip,
                            valueColor: const AlwaysStoppedAnimation(AppColors.onPrimary),
                          ),
                        ),
                      ),
                      if (i < _steps.length - 1) const SizedBox(width: Gap.xs),
                    ],
                  ]),
                ]);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Step [i] fades and slides up during the intro, one after another.
  Widget _rise(int i, Widget child) {
    final start = i * 0.2;
    final v = Curves.easeOutCubic.transform(((_intro.value - start) / 0.6).clamp(0.0, 1.0));
    return Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: child));
  }
}

/// One step of "How Asani works": number, icon and a short label.
class _StepTile extends StatelessWidget {
  const _StepTile({required this.n, required this.step, required this.lit, required this.hop});
  final int n;
  final (IconData, String) step;
  final bool lit;

  /// 0..1 through the step's turn; the icon hops near the start.
  final double hop;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = step;
    // A short up-and-down hop in the first third of the step's turn.
    final lift = lit && hop < 0.33 ? -6 * math.sin(hop / 0.33 * math.pi) : 0.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: Gap.xs, vertical: Gap.md),
      decoration: BoxDecoration(
        color: lit ? AppColors.primaryLight : AppColors.headerChip,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: lit ? AppColors.primarySoft : Colors.transparent),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Transform.translate(
          offset: Offset(0, lift),
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(color: AppColors.onPrimary, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            Positioned(
              right: -6,
              top: -4,
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.onPrimary, width: 1.5),
                ),
                child: Text('$n', style: AppText.labelSmall.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: Gap.sm),
        Text(label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: AppText.labelMedium.copyWith(color: AppColors.onPrimary)),
      ]),
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
