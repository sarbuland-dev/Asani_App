import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/providers.dart';
import '../shell/main_shell.dart';
import 'token_widgets.dart';

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
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GradientHeader(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: Gap.sm),
              Text('My tokens', style: AppText.displaySmall.copyWith(color: AppColors.onPrimary, fontSize: 28)),
              const SizedBox(height: Gap.lg),
              _Segmented(past: _past, onChanged: (v) => setState(() => _past = v)),
            ]),
          ),
          Expanded(
            child: tokens.when(
              loading: () => const Padding(padding: EdgeInsets.all(Gap.screen), child: SkeletonList()),
              error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(myTokensProvider)),
              data: (list) => list.isEmpty
                  ? SingleChildScrollView(
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
                      padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.lg, Gap.screen, kNavBarClearance),
                      children: [for (final t in list) TokenListCard(token: t)],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.past, required this.onChanged});
  final bool past;
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
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(label,
                  style: AppText.labelMedium.copyWith(color: selected ? AppColors.primary : AppColors.onPrimary)),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.onPrimary.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(Radii.pill)),
      child: Row(children: [seg('Active', false), seg('Past', true)]),
    );
  }
}
