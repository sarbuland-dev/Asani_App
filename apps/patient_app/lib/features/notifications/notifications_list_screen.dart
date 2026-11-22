import 'dart:math' as math;

import 'package:asani_core/asani_core.dart';
import 'package:asani_ui/asani_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/error_state.dart';
import '../../data/providers.dart';

/// S-19 Notifications list (PRD D-45, board P7). Every push of the last 30
/// days; opening the list marks all read; a tap opens the same place as the
/// push. Today: a big blue card for "Your turn now", then each token's 4
/// alerts on one step line; then other notices as cards. Earlier: cards.
class NotificationsListScreen extends ConsumerStatefulWidget {
  const NotificationsListScreen({super.key});

  @override
  ConsumerState<NotificationsListScreen> createState() => _NotificationsListScreenState();
}

enum _Filter { all, tokens, followUps }

class _NotificationsListScreenState extends ConsumerState<NotificationsListScreen> {
  /// Seen time from before this visit, so this visit can still show what was new.
  DateTime? _seenBefore;
  bool _marked = false;
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final seen = ref.watch(notificationsSeenAtProvider);
    if (!_marked && seen.hasValue) {
      _marked = true;
      _seenBefore = seen.value;
      // Mark everything read once the list is open (D-45).
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(notificationRepositoryProvider).markAllSeen());
    }
    final async = ref.watch(notificationsProvider);
    final all = async.value ?? const <AppNotification>[];
    final newCount = all.where((n) => n.unreadSince(_seenBefore)).length;

    return StatusBarScrim(
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, Gap.sm, 20, 18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const HeaderBackButton(),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Notifications',
                            style: AppText.titleMedium.copyWith(color: AppColors.onPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
                        if (all.isNotEmpty)
                          Text(newCount == 0 ? 'All caught up' : '$newCount new',
                              style: AppText.labelSmall.copyWith(color: AppColors.onPrimaryMuted)),
                      ]),
                    ),
                  ]),
                  if (all.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _chip(newCount == 0 ? 'All' : 'All · $newCount', _Filter.all),
                      _chip('Tokens', _Filter.tokens),
                      _chip('Follow-ups', _Filter.followUps),
                    ]),
                  ],
                ]),
              ),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: AsaniLoader()),
              error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(notificationsProvider)),
              data: (list) => list.isEmpty ? const _Empty() : _list(list),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String label, _Filter f) {
    final on = _filter == f;
    return Semantics(
      button: true,
      selected: on,
      child: Material(
        color: on ? AppColors.cream : AppColors.primaryMid,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => setState(() => _filter = f),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(label,
                style: AppText.labelMedium.copyWith(fontSize: 13, color: on ? AppColors.primary : AppColors.onPrimaryMuted)),
          ),
        ),
      ),
    );
  }

  Widget _list(List<AppNotification> list) {
    final shown = list.where((n) => switch (_filter) {
          _Filter.all => true,
          _Filter.tokens => n.type != 'followUp',
          _Filter.followUps => n.type == 'followUp',
        }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (shown.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Text('Nothing here yet.', style: AppText.bodyMedium),
        ),
      );
    }
    final today = dayKey(pktNow());
    final todays = shown.where((n) => dayKey(n.createdAt) == today).toList();
    final earlier = shown.where((n) => dayKey(n.createdAt) != today).toList();

    // Today's queue alerts, grouped per token (newest token first).
    final byToken = <String, List<AppNotification>>{};
    for (final n in todays.where((n) => n.type == 'queue' && n.tokenId != null)) {
      byToken.putIfAbsent(n.tokenId!, () => []).add(n);
    }
    final otherToday = todays.where((n) => !(n.type == 'queue' && n.tokenId != null)).toList();

    return ListView(padding: const EdgeInsets.fromLTRB(18, 0, 18, Gap.xl), children: [
      if (todays.isNotEmpty) _group('Today'),
      for (final entry in byToken.entries) ...[
        if (entry.value.any((n) => _step(n) == 4)) _TurnCard(n: entry.value.firstWhere((n) => _step(n) == 4)),
        _StepsCard(alerts: entry.value),
      ],
      for (final n in otherToday) _NoticeCard(n: n, unread: n.unreadSince(_seenBefore)),
      if (earlier.isNotEmpty) _group('Earlier'),
      for (final n in earlier) _NoticeCard(n: n, unread: n.unreadSince(_seenBefore)),
    ]);
  }

  Widget _group(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
        child: Text(t, style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.textSecondary)),
      );
}

/// Which queue alert a notification is: 1 = 3 ahead … 3 = you're next, 4 = your turn.
int _step(AppNotification n) {
  final t = n.title.toLowerCase();
  if (t.contains('your turn')) return 4;
  if (t.contains("you're next")) return 3;
  if (t.startsWith('2 ')) return 2;
  if (t.startsWith('3 ')) return 1;
  return 0;
}

String _label(AppNotification n) => RegExp(r'Token ([A-Z]+-\d+)').firstMatch(n.body)?.group(1) ?? '';

String _time(DateTime d) => DateFormat('h:mm a').format(d);

/// Big blue "Your turn now" card (board P7).
class _TurnCard extends StatelessWidget {
  const _TurnCard({required this.n});
  final AppNotification n;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push(n.route),
            child: Ink(
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.info, Color(0xFF024F7A)]),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: AppColors.surface.withValues(alpha: 0.18), spreadRadius: 6)],
                    ),
                    child: const Icon(Icons.notifications_active_outlined, color: AppColors.info),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(n.title, style: AppText.titleMedium.copyWith(color: AppColors.surface, fontWeight: FontWeight.w700)),
                      Text(n.body, style: AppText.labelSmall.copyWith(color: AppColors.infoContainer, fontSize: 13), maxLines: 2),
                    ]),
                  ),
                  Text(_time(n.createdAt), style: AppText.labelSmall.copyWith(color: AppColors.infoContainer, fontSize: 11)),
                ]),
                const SizedBox(height: 12),
                const Divider(color: Color(0x59FFFFFF), height: 1),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'Token '),
                        TextSpan(text: _label(n), style: const TextStyle(color: AppColors.surface, fontSize: 16, fontWeight: FontWeight.w800)),
                      ]),
                      style: AppText.labelSmall.copyWith(color: AppColors.infoContainer),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
                    child: Text('View token', style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.info, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      );
}

/// One token's 4 queue alerts on a step line, with the time each was sent.
class _StepsCard extends StatelessWidget {
  const _StepsCard({required this.alerts});
  final List<AppNotification> alerts;

  @override
  Widget build(BuildContext context) {
    final at = <int, DateTime>{for (final n in alerts) _step(n): n.createdAt};
    final label = _label(alerts.first);
    const names = ['3 ahead', '2 ahead', "You're next", 'Your turn'];
    final sent = at.keys.where((k) => k > 0).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(alerts.first.route),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text('Alerts for $label', style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.successContainer, borderRadius: BorderRadius.circular(Radii.pill)),
                  child: Text('$sent of 4 sent',
                      style: AppText.labelSmall.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.successText)),
                ),
              ]),
              const SizedBox(height: 12),
              Stack(children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 15,
                  child: FractionallySizedBox(
                    widthFactor: 0.76,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: const LinearGradient(colors: [AppColors.primary, AppColors.info]),
                      ),
                    ),
                  ),
                ),
                Row(children: [
                  for (var i = 1; i <= 4; i++)
                    Expanded(
                      child: Column(children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: at.containsKey(i) ? (i == 4 ? AppColors.info : AppColors.primary) : AppColors.cream,
                            border: Border.all(color: AppColors.surface, width: 3),
                          ),
                          child: i == 4
                              ? Icon(Icons.check_rounded, size: 14, color: at.containsKey(i) ? AppColors.surface : AppColors.textMuted)
                              : Text('${4 - i}',
                                  style: AppText.labelSmall.copyWith(
                                      fontWeight: FontWeight.w800, color: at.containsKey(i) ? AppColors.onPrimary : AppColors.textMuted)),
                        ),
                        const SizedBox(height: 4),
                        Text(names[i - 1], textAlign: TextAlign.center, style: AppText.labelSmall.copyWith(fontSize: 10)),
                        Text(at.containsKey(i) ? DateFormat('h:mm').format(at[i]!) : '—',
                            style: AppText.labelSmall.copyWith(
                                fontSize: 10, fontWeight: FontWeight.w700, color: i == 4 ? AppColors.info : AppColors.textPrimary)),
                      ]),
                    ),
                ]),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Any other notification as a card: follow-up (lime with Book), clinic
/// cancel (red), missed turn (amber), queue alert (green step).
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.n, required this.unread});
  final AppNotification n;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    if (n.type == 'followUp') {
      final d = n.createdAt;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push(n.route),
            child: Ink(
              decoration: const BoxDecoration(gradient: AppColors.limeGradient),
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: AppColors.onLime, borderRadius: BorderRadius.circular(14)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(DateFormat('MMM').format(d).toUpperCase(),
                        style: AppText.labelSmall.copyWith(fontSize: 9, fontWeight: FontWeight.w700, color: const Color(0xFFC8DC8A))),
                    Text('${d.day}', style: AppText.labelLarge.copyWith(color: const Color(0xFFC8DC8A), fontWeight: FontWeight.w800)),
                  ]),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(n.title, style: AppText.labelLarge.copyWith(fontSize: 15, color: AppColors.onLime, fontWeight: FontWeight.w700)),
                    Text(n.body, style: AppText.labelSmall.copyWith(color: AppColors.onLimeMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                const SizedBox(width: Gap.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: AppColors.onLime, borderRadius: BorderRadius.circular(10)),
                  child: Text('Book', style: AppText.labelSmall.copyWith(color: AppColors.cream, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ),
        ),
      );
    }
    final step = n.type == 'queue' ? _step(n) : 0;
    final (IconData icon, Color bg, Color fg) = switch (n.type) {
      'cancel' => (Icons.block_rounded, AppColors.dangerContainer, AppColors.danger),
      'skip' => (Icons.directions_walk_rounded, AppColors.warningContainer, AppColors.warning),
      _ => step == 4
          ? (Icons.check_rounded, AppColors.infoContainer, AppColors.info)
          : (Icons.notifications_none_rounded, AppColors.primaryContainer, AppColors.primary),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: unread ? AppColors.surface : AppColors.surface.withValues(alpha: 0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(n.route),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                child: step >= 1 && step <= 3
                    ? Text('${4 - step}', style: AppText.labelLarge.copyWith(color: fg, fontWeight: FontWeight.w800))
                    : Icon(icon, size: 18, color: fg),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n.title,
                      style: AppText.labelMedium.copyWith(fontWeight: unread ? FontWeight.w800 : FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text('${n.body} · ${_ago(n.createdAt)}', style: AppText.labelSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (unread) ...[
                const SizedBox(width: Gap.sm),
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  static String _ago(DateTime d) {
    final now = pktNow();
    if (dayKey(d) == dayKey(now)) return _time(d);
    if (dayKey(d) == dayKey(now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return DateFormat('EEE d MMM').format(d);
  }
}

/// Empty list (board P7): a bell that rings now and then with the 4 alerts
/// floating round it, the promise, and what each token gets. Still with
/// reduce motion.
class _Empty extends ConsumerStatefulWidget {
  const _Empty();

  @override
  ConsumerState<_Empty> createState() => _EmptyState();
}

class _EmptyState extends ConsumerState<_Empty> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    Widget bubble(Widget child, Color bg, double phase, {bool border = false}) {
      final y = -6 * math.sin((_c.value + phase) * 2 * math.pi).abs();
      return Transform.translate(
        offset: Offset(0, y),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: border ? Border.all(color: AppColors.border) : null,
            boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.10), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: child,
        ),
      );
    }

    Widget row(String n, Color bg, Color fg, String title, String hint, {bool blue = false, bool last = false}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.cream))),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
              child: n == '✓'
                  ? Icon(Icons.check_rounded, size: 14, color: fg)
                  : Text(n, style: AppText.labelSmall.copyWith(color: fg, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(title,
                  style: AppText.labelMedium.copyWith(fontWeight: blue ? FontWeight.w700 : FontWeight.w600, color: blue ? AppColors.info : AppColors.textPrimary)),
            ),
            Text(hint, style: AppText.labelSmall.copyWith(fontSize: 11)),
          ]),
        );

    return ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 26), children: [
      Semantics(
        label: 'No notifications yet',
        child: ExcludeSemantics(
          child: SizedBox(
            height: 140,
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) {
                // A short ring around 70–90 % of each loop.
                final t = _c.value;
                final ring = t > 0.7 && t < 0.9 ? math.sin((t - 0.7) / 0.2 * 4 * math.pi) * 0.17 * (1 - (t - 0.7) / 0.2) : 0.0;
                return Stack(alignment: Alignment.center, children: [
                  Container(
                    width: 160,
                    height: 160,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [AppColors.primaryContainer, Color(0xFFEEF3EF), Color(0x00EEF3EF)], stops: [0, 0.6, 0.72]),
                    ),
                  ),
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.primarySoft, width: 1.5)),
                  ),
                  Transform.rotate(
                    angle: ring,
                    alignment: const Alignment(0, -0.6),
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.primaryMid, AppColors.navy]),
                        boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.3), blurRadius: 28, offset: const Offset(0, 14))],
                      ),
                      child: const Icon(Icons.notifications_none_rounded, size: 38, color: AppColors.onPrimary),
                    ),
                  ),
                  Positioned(left: 40, top: 10, child: bubble(Text('3', style: AppText.labelMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)), AppColors.surface, 0, border: true)),
                  Positioned(right: 44, top: 2, child: bubble(Text('2', style: AppText.labelMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)), AppColors.surface, 0.17, border: true)),
                  Positioned(left: 54, bottom: 12, child: bubble(Text('1', style: AppText.labelMedium.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w800)), AppColors.primary, 0.33)),
                  Positioned(right: 50, bottom: 18, child: bubble(const Icon(Icons.check_rounded, size: 15, color: AppColors.surface), AppColors.info, 0.5)),
                ]);
              },
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text('No notifications yet', textAlign: TextAlign.center, style: AppText.titleLarge.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text("Book a token and we'll keep you posted, so you can wait at home.",
          textAlign: TextAlign.center, style: AppText.bodyMedium.copyWith(height: 1.5)),
      const SizedBox(height: Gap.lg),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text("What you'll get for each token", style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          row('3', AppColors.primaryContainer, AppColors.primary, '3 patients ahead', 'Leave home'),
          row('2', AppColors.primaryContainer, AppColors.primary, '2 patients ahead', 'On the way'),
          row('1', AppColors.primary, AppColors.onPrimary, "You're next", 'At reception'),
          row('✓', AppColors.info, AppColors.surface, 'Your turn now', 'Go in', blue: true, last: true),
        ]),
      ),
      if (settings != null && !settings.notificationsAllowed) ...[
        const SizedBox(height: Gap.md),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
          decoration: BoxDecoration(color: AppColors.warningContainer, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Icon(Icons.notifications_off_outlined, size: 18, color: AppColors.warningText),
            const SizedBox(width: Gap.sm),
            Expanded(child: Text('Notifications are off on this phone.', style: AppText.labelSmall.copyWith(color: AppColors.warningText, fontSize: 13))),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.warningText),
              onPressed: () => context.push('/notifications'),
              child: const Text('Turn on'),
            ),
          ]),
        ),
      ],
    ]);
  }
}

/// Bell with the unread count, for the Home header.
class NotificationsBell extends ConsumerWidget {
  const NotificationsBell({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsProvider);
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => context.push('/inbox'),
      icon: Badge(
        isLabelVisible: unread > 0,
        backgroundColor: AppColors.cream,
        textColor: AppColors.primary,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: Icon(Icons.notifications_outlined, color: color),
      ),
    );
  }
}
