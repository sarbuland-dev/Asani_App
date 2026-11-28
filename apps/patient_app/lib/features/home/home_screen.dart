import 'dart:math' as math;

import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:asani_ui/asani_ui.dart';
import '../../data/providers.dart';
import '../clinic/clinic_card.dart';
import 'city_sheet.dart';
import '../../core/widgets/error_state.dart';
import '../notifications/notifications_list_screen.dart';
import '../../core/widgets/bottom_clearance.dart';

/// S-05 Home (PRD F-02, board P2, D-43). Green header with the avatar, bell,
/// greeting and city; then ONE top card that depends on the user:
///   * an active token  → the live token card (swipe when there are several),
///   * no token, but has visited before → "Book again",
///   * brand-new user   → "How Asani works" with three animated icons;
/// then the two search cards, follow-ups, and recent clinics (or the city's
/// clinics for a new user).
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
    final past = ref.watch(myPastTokensProvider).value ?? const [];
    final followUps = ref.watch(upcomingFollowUpsProvider);
    // Until the tokens have arrived we can't tell a new user from a returning one.
    final tokensKnown = ref.watch(myTokensProvider.select((t) => t.hasValue));
    final tokensLoading = ref.watch(myTokensProvider.select((t) => t.isLoading && !t.hasValue));
    final isNew = tokensKnown && active.isEmpty && past.isEmpty;
    // Book again: the last visit that really happened, else the last token.
    final lastVisit = past.where((t) => t.status == TokenStatus.completed).firstOrNull ?? past.firstOrNull;

    return StatusBarScrim(
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: () async => ref.invalidate(clinicsProvider(city)),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Header(name: user?.name ?? '', city: city, isNew: isNew)),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(20, Gap.lg, 20, bottomClearance(context)),
                sliver: SliverList.list(
                  children: [
                    if (active.isNotEmpty)
                      _ActiveTokens(tokens: active)
                    else if (lastVisit != null)
                      _BookAgainCard(token: lastVisit)
                    else if (tokensLoading)
                      const SkeletonList(count: 1, height: 150)
                    else if (isNew)
                      const _HowItWorks(),
                    const SizedBox(height: 14),
                    const _SearchCards(),
                    for (final f in followUps.take(2)) ...[
                      const SizedBox(height: 14),
                      _FollowUpCard(followUp: f),
                    ],
                    if (!isNew && recent.isNotEmpty) ...[
                      _SectionHead(title: 'Recent clinics', onAll: () => context.push('/search')),
                      SizedBox(
                        // Grows with the text size so the mini cards never clip.
                        height: 96 + 38 * MediaQuery.textScalerOf(context).scale(14) / 14,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          itemCount: recent.length,
                          separatorBuilder: (_, _) => const SizedBox(width: Gap.md),
                          itemBuilder: (_, i) => Align(alignment: Alignment.topCenter, child: ClinicMiniCard(clinic: recent[i])),
                        ),
                      ),
                    ] else ...[
                      _SectionHead(title: 'Clinics in $city', onAll: () => context.push('/search')),
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
                            : [for (final c in list.take(3)) ClinicCard(clinic: c)],
                      ),
                    ],
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

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, required this.onAll});
  final String title;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Gap.lg, bottom: Gap.sm),
        child: Row(children: [
          Expanded(child: Text(title, style: AppText.titleSmall.copyWith(fontSize: 17, fontWeight: FontWeight.w700))),
          TextButton(onPressed: onAll, child: const Text('View all')),
        ]),
      );
}

/// Green header (board P2): avatar left, bell right; then the greeting and
/// full name with the city pill on the right.
class _Header extends ConsumerWidget {
  const _Header({required this.name, required this.city, required this.isNew});
  final String name;
  final String city;
  final bool isNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, Gap.md, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Semantics(
                  button: true,
                  label: 'Account',
                  excludeSemantics: true,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => context.go('/account'),
                    child: Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.cream,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primaryLight, width: 2),
                      ),
                      child: Text(Fmt.initials(name),
                          style: AppText.titleMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
                const Spacer(),
                // S-19 / D-45: notifications list with the unread count.
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(color: AppColors.primaryMid, shape: BoxShape.circle),
                  child: const Center(child: NotificationsBell(color: AppColors.onPrimary)),
                ),
              ]),
              const SizedBox(height: 18),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(isNew ? 'Welcome to Asani,' : Fmt.greeting(),
                        style: AppText.bodyMedium.copyWith(color: AppColors.onPrimaryMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(name,
                        style: AppText.titleLarge.copyWith(color: AppColors.onPrimary, fontSize: 26, fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ]),
                ),
                const SizedBox(width: Gap.md),
                Material(
                  color: AppColors.primaryMid,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => showCityPicker(context, ref),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.location_on_outlined, size: 18, color: AppColors.onPrimary),
                        const SizedBox(width: 6),
                        Text(city, style: AppText.labelMedium.copyWith(color: AppColors.onPrimary)),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.onPrimary),
                      ]),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cream rounded card used for the top card on Home.
class _Cream extends StatelessWidget {
  const _Cream({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(20)),
        child: child,
      );
}

Widget _chip(String text, Color bg, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.pill)),
      child: Text(text, style: AppText.labelSmall.copyWith(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );

Widget _darkButton(String label, VoidCallback onTap) => Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Center(child: Text(label, style: AppText.labelMedium.copyWith(color: AppColors.onPrimary))),
        ),
      ),
    );

/// Active tokens: one card at a time; swipe sideways when there are several.
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
    final tokens = widget.tokens;
    if (tokens.length == 1) return _ActiveTokenCard(token: tokens.first);
    // Grows with the user's text size so the card never clips.
    final f = MediaQuery.textScalerOf(context).scale(14) / 14;
    final page = _page.clamp(0, tokens.length - 1);
    return Column(children: [
      SizedBox(
        height: 112 + 110 * f,
        child: PageView.builder(
          itemCount: tokens.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Align(alignment: Alignment.topCenter, child: _ActiveTokenCard(token: tokens[i])),
          ),
        ),
      ),
      const SizedBox(height: Gap.sm),
      Semantics(
        label: 'Token ${page + 1} of ${tokens.length}. Swipe for more.',
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < tokens.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == page ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == page ? AppColors.primary : AppColors.border,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
            ),
        ]),
      ),
    ]);
  }
}

/// Board "has an active token": Live chip, clinic · day; patient · doctor;
/// the big token code; how many ahead and the wait; "View live token".
class _ActiveTokenCard extends ConsumerWidget {
  const _ActiveTokenCard({required this.token});
  final Token token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctor = ref.watch(doctorProvider(token.doctorId)).value;
    final clinic = ref.watch(clinicProvider(token.clinicId)).value;
    final pos = ref.watch(tokenPositionProvider(token.id)).value;
    final isToday = token.date == dayKey(pktNow());
    final session = pos?.day.sessionStatus;
    final called = token.status == TokenStatus.called;
    final skipped = token.status == TokenStatus.skipped;
    final running = isToday && session == SessionStatus.running;

    final (chipText, chipBg, chipFg) = called
        ? ('● Your turn', AppColors.info, AppColors.surface)
        : skipped
            ? ('Turn passed', AppColors.warningContainer, AppColors.warningText)
            : running
                ? ('● Live', AppColors.primary, AppColors.onPrimary)
                : (isToday ? 'Today' : Fmt.shortDay(token.date), AppColors.surface, AppColors.primary);

    final serving = pos == null || pos.day.currentToken == 0 ? null : '${token.tokenPrefix}-${pos.day.currentToken}';
    final String big;
    final String small;
    if (called) {
      big = 'Go in now';
      small = 'Please go to ${doctor?.name ?? 'the doctor'}';
    } else if (skipped) {
      big = 'Go to reception';
      small = "You'll be called after the current patient";
    } else if (running && pos != null) {
      big = pos.ahead == 0 ? "You're next" : '${pos.ahead} ahead';
      small = token.isNextUp
          ? 'Called right after the current patient'
          : '~${Fmt.wait(pos.waitMinutes)}${serving == null ? '' : ' · serving $serving'}';
    } else if (isToday) {
      big = '';
      small = switch (session) {
        SessionStatus.notStarted => "Doctor hasn't started yet",
        SessionStatus.paused => 'Queue paused',
        SessionStatus.ended => 'Session ended',
        _ => '',
      };
    } else {
      big = '';
      small = Fmt.relativeDay(token.date);
    }
    final firstName = token.patientSnapshot.name.split(' ').first;

    return Semantics(
      container: true,
      label: 'Token ${token.label} for ${token.patientSnapshot.name} with ${doctor?.name ?? 'the doctor'}. $big. $small',
      child: _Cream(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _chip(chipText, chipBg, chipFg),
            const Spacer(),
            Flexible(
              child: Text('${clinic?.name ?? ''} · ${isToday ? 'Today' : Fmt.shortDay(token.date)}',
                  style: AppText.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: Gap.sm),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$firstName · ${doctor?.name.replaceFirst(RegExp(r'^Dr\.\s*'), 'Dr. ').split(' ').take(2).join(' ') ?? ''}',
                    style: AppText.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(token.label,
                    style: AppText.tokenDisplaySmall.copyWith(
                        fontSize: 40, letterSpacing: -0.8, color: called ? AppColors.info : AppColors.primary)),
              ]),
            ),
            const SizedBox(width: Gap.sm),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (big.isNotEmpty)
                  Text(big,
                      textAlign: TextAlign.right,
                      style: AppText.titleMedium.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                if (small.isNotEmpty)
                  Text(small, textAlign: TextAlign.right, style: AppText.labelSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
          const SizedBox(height: Gap.md),
          _darkButton('View live token ›', () => context.push('/token/${token.id}')),
        ]),
      ),
    );
  }
}

/// Board "returning user, no token": the last visit's doctor, whether they
/// sit today, who it was for, today's bookings, and "Book again".
class _BookAgainCard extends ConsumerWidget {
  const _BookAgainCard({required this.token});
  final Token token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctor = ref.watch(doctorProvider(token.doctorId)).value;
    final clinic = ref.watch(clinicProvider(token.clinicId)).value;
    final now = nowFrom(ref);
    final today = dayKey(now);
    final day = ref.watch(queueDayProvider((doctorId: token.doctorId, date: today))).value;
    final sched = doctor?.scheduleOn(now);
    final sitsToday = doctor != null && doctor.active && sched != null && !doctor.onLeave(now);
    final s = token.patientSnapshot;
    final who = s.relation == Relation.self ? s.name.split(' ').first : '${s.name.split(' ').first} (${s.relation.label})';

    return _Cream(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _chip('Book again', AppColors.surface, AppColors.primary),
          const Spacer(),
          Flexible(
            child: Text('Last visit · ${Fmt.shortDay(token.date)}',
                style: AppText.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: Gap.md),
        Row(children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
            child: Text(Fmt.initials(doctor?.name ?? ''),
                style: AppText.labelLarge.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(doctor?.name ?? '',
                  style: AppText.titleSmall.copyWith(fontSize: 17, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${doctor?.specialityEnum.label ?? ''} · ${clinic?.name ?? ''}',
                  style: AppText.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                sitsToday ? '● Available today · ${Fmt.timeRange(sched)}' : '○ Not available today',
                style: AppText.labelSmall.copyWith(
                    color: sitsToday ? AppColors.success : AppColors.textSecondary, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
        ]),
        const SizedBox(height: Gap.md),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'For '),
                  TextSpan(text: who, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                ]),
                style: AppText.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (sitsToday)
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: '${day?.bookedCount ?? 0} of ${doctor.maxTokensPerDay}',
                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                  const TextSpan(text: ' booked'),
                ]),
                style: AppText.labelSmall,
              ),
          ]),
        ),
        const SizedBox(height: Gap.md),
        _darkButton('Book again ›', () => context.push('/book/${token.clinicId}/${token.doctorId}?patient=${token.patientId}')),
      ]),
    );
  }
}

/// The two big search cards (board P2): by clinic, by doctor speciality.
class _SearchCards extends StatelessWidget {
  const _SearchCards();

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: _SearchCard(
            icon: Icons.local_hospital_outlined,
            title: 'Search by clinic',
            sub: 'Find a clinic by name or area',
            begin: AppColors.primary,
            end: AppColors.primaryLight,
            onTap: () => context.push('/search'),
          ),
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: _SearchCard(
            icon: Icons.medical_services_outlined,
            title: 'Search by doctor',
            sub: 'Pick a speciality near you',
            begin: AppColors.primaryLight,
            end: AppColors.primary,
            onTap: () => context.push('/search?tab=doctors'),
          ),
        ),
      ]),
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.icon,
    required this.title,
    required this.sub,
    required this.begin,
    required this.end,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String sub;
  final Color begin;
  final Color end;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $sub',
      excludeSemantics: true,
      child: Material(
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [begin, end])),
            child: Stack(children: [
              // Faint ring in the corner.
              Positioned(
                right: -26,
                bottom: -26,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.cream.withValues(alpha: 0.08), width: 14),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(color: AppColors.primaryMid, shape: BoxShape.circle),
                  child: const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.onPrimary),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 96),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, size: 22, color: AppColors.primary),
                    ),
                    const SizedBox(height: 10),
                    Text(title, style: AppText.labelMedium.copyWith(color: AppColors.onPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(sub, style: AppText.labelSmall.copyWith(color: AppColors.onPrimaryMuted, height: 1.35)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// New user (board P2): "How Asani works" with three glossy icons that take
/// turns to light up (find, book, go), each floating gently, and a caption
/// that follows. Still when the OS asks for less motion.
class _HowItWorks extends StatefulWidget {
  const _HowItWorks();

  @override
  State<_HowItWorks> createState() => _HowItWorksState();
}

class _HowItWorksState extends State<_HowItWorks> with TickerProviderStateMixin {
  static const _captions = ['1 · Find a clinic or doctor', '2 · Book your token from home', "3 · Go when we say it's your turn"];

  /// 9 s: each icon is "on" for a third.
  late final _turn = AnimationController(vsync: this, duration: const Duration(seconds: 9));

  /// Gentle float, up and down.
  late final _float = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      _turn.stop();
      _float.stop();
    } else if (!_started) {
      _started = true;
      _turn.repeat();
      _float.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      label: 'How Asani works: 1, find a clinic or doctor. 2, book your token from home. 3, go when we say it is your turn.',
      child: ExcludeSemantics(
        child: _Cream(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text('How Asani works', style: AppText.titleSmall.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text('Wait at home, not at the clinic',
                    textAlign: TextAlign.right, style: AppText.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ]),
            const SizedBox(height: Gap.md),
            AnimatedBuilder(
              animation: Listenable.merge([_turn, _float]),
              builder: (context, _) {
                final on = still ? -1 : (_turn.value * 3).floor().clamp(0, 2);
                final lift = still ? 0.0 : -8 * Curves.easeInOut.transform(_float.value);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const RadialGradient(
                        center: Alignment.topCenter,
                        radius: 1.3,
                        colors: [AppColors.surface, Color(0xFFF7F4EC), Color(0xFFECE7DA)],
                        stops: [0, 0.6, 1],
                      ),
                    ),
                    child: Row(children: [
                      for (var i = 0; i < 3; i++)
                        Expanded(
                          child: _IconSlot(
                            kind: i,
                            label: const ['Find', 'Book', 'Go'][i],
                            active: still || on == i,
                            // Each icon floats a little out of step with the others.
                            lift: still ? 0 : lift * (i == 1 ? 0.8 : 1),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: Gap.md),
                  SizedBox(
                    height: 20,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        still ? 'Find · Book · Go when called' : _captions[on],
                        key: ValueKey(on),
                        style: AppText.labelMedium.copyWith(
                            fontSize: 13, color: on == 2 ? AppColors.info : AppColors.primary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ]);
              },
            ),
          ]),
        ),
      ),
    );
  }
}

class _IconSlot extends StatelessWidget {
  const _IconSlot({required this.kind, required this.label, required this.active, required this.lift});
  final int kind;
  final String label;
  final bool active;
  final double lift;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      AnimatedScale(
        scale: active ? 1.14 : 0.86,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: active ? 1 : 0.5,
          duration: const Duration(milliseconds: 350),
          child: Transform.translate(
            offset: Offset(0, lift),
            child: SizedBox.square(dimension: 70, child: CustomPaint(painter: _GlossyIcon(kind))),
          ),
        ),
      ),
      const SizedBox(height: 6),
      // Shadow that shrinks as the icon floats up.
      Transform.scale(
        scaleX: 1 + lift / 32,
        child: Container(
          width: 46,
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.navy.withValues(alpha: 0.16),
            borderRadius: const BorderRadius.all(Radius.elliptical(23, 4)),
          ),
        ),
      ),
      const SizedBox(height: 6),
      AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 300),
        style: AppText.labelSmall.copyWith(fontWeight: FontWeight.w700, color: active ? AppColors.primary : AppColors.textMuted),
        child: Text(label),
      ),
    ]);
  }
}

/// The three "3D glossy" icons from the board, drawn in an 80×80 box:
/// 0 magnifier, 1 ticket "A-11", 2 blue bell.
class _GlossyIcon extends CustomPainter {
  _GlossyIcon(this.kind);
  final int kind;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 80);
    switch (kind) {
      case 0:
        _magnifier(canvas);
      case 1:
        _ticket(canvas);
      default:
        _bell(canvas);
    }
    canvas.restore();
  }

  void _magnifier(Canvas c) {
    // Handle.
    c.save();
    c.translate(53, 59);
    c.rotate(-math.pi / 4);
    final handle = RRect.fromRectAndRadius(const Rect.fromLTWH(-6, -15, 12, 30), const Radius.circular(6));
    c.drawRRect(
        handle,
        Paint()
          ..shader = const LinearGradient(colors: [AppColors.primaryMid, AppColors.primary, AppColors.primaryDeep])
              .createShader(handle.outerRect));
    c.restore();
    // Rim and lens.
    const rim = Rect.fromLTWH(12, 12, 44, 44);
    c.drawOval(
        rim,
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.primaryLight, AppColors.primary, AppColors.navy])
              .createShader(rim));
    final lens = Rect.fromCircle(center: const Offset(34, 34), radius: 15.5);
    c.drawOval(
        lens,
        Paint()
          ..shader = const RadialGradient(
                  center: Alignment(-0.25, -0.35), radius: 0.9, colors: [AppColors.surface, AppColors.primaryContainer, Color(0xFF8FB8AE)])
              .createShader(lens));
    // Shine.
    c.save();
    c.translate(27, 26);
    c.rotate(-0.6);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: 14, height: 8), Paint()..color = AppColors.surface.withValues(alpha: 0.85));
    c.restore();
  }

  void _ticket(Canvas c) {
    c.save();
    c.translate(40, 40);
    c.rotate(-10 * math.pi / 180);
    c.translate(-40, -40);
    Path body(double right) => Path()
      ..moveTo(10, 22)
      ..lineTo(right, 22)
      ..lineTo(right, 58)
      ..lineTo(10, 58)
      ..arcToPoint(const Offset(6, 54), radius: const Radius.circular(4))
      ..lineTo(6, 46)
      ..arcToPoint(const Offset(6, 34), radius: const Radius.circular(6), clockwise: true)
      ..lineTo(6, 26)
      ..arcToPoint(const Offset(10, 22), radius: const Radius.circular(4))
      ..close();
    final full = Path()
      ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(6, 22, 68, 36), const Radius.circular(4)));
    final notches = Path()
      ..addOval(Rect.fromCircle(center: const Offset(6, 40), radius: 6))
      ..addOval(Rect.fromCircle(center: const Offset(74, 40), radius: 6));
    final ticket = Path.combine(PathOperation.difference, full, notches);
    c.drawPath(
        ticket,
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.surface, AppColors.cream, Color(0xFFD9D2C1)])
              .createShader(const Rect.fromLTWH(6, 22, 68, 36)));
    final stub = Path.combine(PathOperation.intersect, ticket, body(26));
    c.drawPath(
        stub,
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.primaryLight, AppColors.navy])
              .createShader(const Rect.fromLTWH(6, 22, 20, 36)));
    // Dashed tear line.
    final dash = Paint()
      ..color = AppColors.borderStrong
      ..strokeWidth = 1.6;
    for (double y = 25; y < 55; y += 6) {
      c.drawLine(Offset(26, y), Offset(26, y + 3), dash);
    }
    // Shine and hole.
    c.drawLine(
        const Offset(12, 25),
        const Offset(68, 25),
        Paint()
          ..color = AppColors.surface.withValues(alpha: 0.9)
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round);
    c.drawCircle(const Offset(16, 40), 3, Paint()..color = AppColors.cream.withValues(alpha: 0.9));
    // "A-11".
    final tp = TextPainter(
      text: const TextSpan(
          text: 'A-11', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(50 - tp.width / 2, 40 - tp.height / 2));
    c.restore();
  }

  void _bell(Canvas c) {
    const deep = Color(0xFF024870);
    c.drawCircle(const Offset(40, 14), 4, Paint()..color = deep);
    final bell = Path()
      ..moveTo(40, 16)
      ..cubicTo(28, 16, 21, 25, 21, 37)
      ..lineTo(21, 48)
      ..lineTo(15, 56)
      ..lineTo(65, 56)
      ..lineTo(59, 48)
      ..lineTo(59, 37)
      ..cubicTo(59, 25, 52, 16, 40, 16)
      ..close();
    c.drawPath(
        bell,
        Paint()
          ..shader = const RadialGradient(
                  center: Alignment(-0.3, -0.4), radius: 0.95, colors: [Color(0xFF4FA3D1), AppColors.info, deep])
              .createShader(const Rect.fromLTWH(15, 16, 50, 40)));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(15, 54, 50, 6), const Radius.circular(3)), Paint()..color = deep);
    c.drawCircle(const Offset(40, 64), 5.5, Paint()..color = AppColors.cream);
    final shine = Path()
      ..moveTo(29, 32)
      ..quadraticBezierTo(30, 23, 39, 21);
    c.drawPath(
        shine,
        Paint()
          ..color = AppColors.surface.withValues(alpha: 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_GlossyIcon old) => old.kind != kind;
}

/// The city pill opens the "Lahore for now" sheet (D-64, board P12). When a
/// second city goes live this becomes a real picker again.
Future<void> showCityPicker(BuildContext context, WidgetRef ref) => showCitySheet(context, ref);

/// Follow-up due (board P2): dark lime card with a Book button (lime 400 is
/// the approved exception for follow-ups).
class _FollowUpCard extends ConsumerWidget {
  const _FollowUpCard({required this.followUp});
  final FollowUp followUp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patient = (ref.watch(myPatientsProvider).value ?? const []).where((p) => p.id == followUp.patientId).firstOrNull;
    final doctor = ref.watch(doctorProvider(followUp.doctorId)).value;
    final clinic = ref.watch(clinicProvider(followUp.clinicId)).value;
    final first = (patient?.name ?? '').split(' ').first;
    final doc = (doctor?.name ?? '').split(' ').take(2).join(' ');
    return Semantics(
      container: true,
      label: 'Follow-up due ${Fmt.shortDay(followUp.dueDate)} for ${patient?.name ?? ''} with ${doctor?.name ?? ''}',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(gradient: AppColors.limeGradient, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: AppColors.onLime.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.event_outlined, size: 20, color: AppColors.onLime),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: ExcludeSemantics(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('FOLLOW-UP DUE',
                    style: AppText.labelSmall.copyWith(color: AppColors.onLimeMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                Text('$first · $doc',
                    style: AppText.labelMedium.copyWith(color: AppColors.onLime, fontSize: 15, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text('${Fmt.shortDay(followUp.dueDate)}${clinic == null ? '' : ' · ${clinic.name}'}',
                    style: AppText.labelSmall.copyWith(color: AppColors.onLimeMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
          const SizedBox(width: Gap.sm),
          Material(
            color: AppColors.onLime,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => context.push(followUpBookingPath(followUp)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text('Book', style: AppText.labelMedium.copyWith(color: AppColors.cream, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Pre-filled booking from a follow-up (PRD F-09).
String followUpBookingPath(FollowUp f) => '/book/${f.clinicId}/${f.doctorId}?patient=${f.patientId}&date=${f.dueDate}';
