import 'package:flutter/material.dart';
import 'package:asani_core/asani_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import 'package:asani_ui/asani_ui.dart';
import '../../data/providers.dart';
import 'token_widgets.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/bottom_clearance.dart';

/// S-12 Tokens tab: Active | Past (PRD F-08).
class TokensScreen extends ConsumerStatefulWidget {
  const TokensScreen({super.key});

  @override
  ConsumerState<TokensScreen> createState() => _TokensScreenState();
}

class _TokensScreenState extends ConsumerState<TokensScreen> {
  bool _past = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(_past ? myPastTokensProvider : myActiveTokensProvider);
    final activeCount = ref.watch(myActiveTokensProvider).value?.length;
    return StatusBarScrim(
      child: Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Board P6 S-12: green header, "My tokens", Active · n | Past.
          Container(
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, Gap.xl, 20, 18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('My tokens',
                      style: AppText.headline.copyWith(color: AppColors.onPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 14),
                  _Segmented(past: _past, activeCount: activeCount, onChanged: (v) => setState(() => _past = v)),
                ]),
              ),
            ),
          ),
          Expanded(
            child: tokens.when(
              loading: () => const Padding(padding: EdgeInsets.all(Gap.screen), child: SkeletonList()),
              error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(myTokensProvider)),
              data: (list) => list.isEmpty
                  ? SingleChildScrollView(
                      padding: EdgeInsets.only(bottom: bottomClearance(context)),
                      child: _past
                          ? const EmptyState(
                              icon: Icons.history_rounded,
                              title: 'No past tokens',
                              message: 'Completed and cancelled tokens will show here.',
                            )
                          : EmptyState(
                              icon: Icons.confirmation_number_outlined,
                              title: 'No active tokens',
                              message: 'Book a token at a clinic near you and watch the queue live.',
                              actionLabel: 'Find a clinic',
                              onAction: () => context.go('/home'),
                            ),
                    )
                  : ListView(
                      padding: EdgeInsets.fromLTRB(Gap.screen, Gap.lg, Gap.screen, bottomClearance(context)),
                      children: [
                        // Past: grouped by month (board), newest first.
                        for (var i = 0; i < list.length; i++) ...[
                          if (_past && (i == 0 || _month(list[i].date) != _month(list[i - 1].date)))
                            Padding(
                              padding: EdgeInsets.only(top: i == 0 ? 0 : Gap.sm, bottom: Gap.sm),
                              child: Text(_month(list[i].date),
                                  style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.textSecondary)),
                            ),
                          TokenListCard(token: list[i]),
                        ],
                        // Past list: the live query holds the latest 100; older ones on demand.
                        if (_past) const _LoadOlder(),
                      ],
                    ),
            ),
          ),
        ],
      ),
    ));
  }
}

String _month(String dayKey) => DateFormat('MMMM y').format(parseDayKey(dayKey));

class _LoadOlder extends ConsumerWidget {
  const _LoadOlder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(olderTokensProvider);
    if (s.done) return const Center(child: Text('No older tokens.'));
    return Center(
      child: TextButton(
        onPressed: s.loading ? null : () => ref.read(olderTokensProvider.notifier).loadMore(),
        child: Text(s.loading ? 'Loading…' : 'Load older tokens'),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.past, required this.activeCount, required this.onChanged});
  final bool past;
  final int? activeCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool value) {
      final selected = past == value;
      return Expanded(
        child: Semantics(
          selected: selected,
          button: true,
          child: GestureDetector(
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.cream : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(label,
                  style: AppText.labelMedium.copyWith(
                      color: selected ? AppColors.primary : AppColors.onPrimaryMuted,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600)),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.primaryMid, borderRadius: BorderRadius.circular(Radii.pill)),
      child: Row(children: [seg(activeCount == null || activeCount == 0 ? 'Active' : 'Active · $activeCount', false), seg('Past', true)]),
    );
  }
}
