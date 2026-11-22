import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:asani_ui/asani_ui.dart';

/// Tabs: Home · Tokens · Family · Account (DESIGN.md §4).
/// Floating dark green pill bar (board, D-43); the selected tab grows into a
/// green pill with its cream icon and label, the others show the icon only
/// and say their name on long-press.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.confirmation_number_outlined, Icons.confirmation_number_rounded, 'Tokens'),
    (Icons.group_outlined, Icons.group_rounded, 'Family'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Account'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.1,
        child: SafeArea(
          minimum: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
          child: Container(
            // Board (D-43): darkest green pill, soft shadow.
            height: 70,
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(Radii.pill),
              boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.28), blurRadius: 28, offset: const Offset(0, 12))],
            ),
            padding: const EdgeInsets.all(9),
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  // The selected tab takes more room so its label fits.
                  AnimatedFlex(
                    flex: shell.currentIndex == i ? 5 : 2,
                    child: _NavItem(item: _items[i], selected: shell.currentIndex == i, onTap: () => _go(i)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _go(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);
}

/// [Expanded] whose flex changes smoothly (flex itself cannot animate, so the
/// width is tweened through a [TweenAnimationBuilder]).
class AnimatedFlex extends StatelessWidget {
  const AnimatedFlex({super.key, required this.flex, required this.child});
  final int flex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: flex.toDouble()),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      builder: (_, value, child) => Expanded(flex: (value * 100).round(), child: child!),
      child: child,
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.item, required this.selected, required this.onTap});
  final (IconData, IconData, String) item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, activeIcon, label) = item;
    final tab = Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.pill),
          // The highlight hugs the icon + label; the whole slot stays tappable.
          // While the slot animates open it is briefly narrow: show the label
          // only once icon + gap + label padding fit (no overflow on 320 px phones).
          child: LayoutBuilder(builder: (context, box) {
            final showLabel = selected && box.maxWidth >= 72;
            return Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: selected ? AppColors.primaryMid : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              padding: EdgeInsets.fromLTRB(showLabel ? 16 : 4, 14, showLabel ? 22 : 4, 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(selected ? activeIcon : icon, color: selected ? AppColors.onPrimary : AppColors.primarySoft, size: 24),
                  if (showLabel) ...[
                    const SizedBox(width: Gap.sm),
                    Flexible(
                      child: ExcludeSemantics(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: AppText.labelLarge.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
          }),
        ),
      ),
    );
    // Icon-only tabs show their name on long-press (the label is hidden).
    return selected ? tab : Tooltip(message: label, excludeFromSemantics: true, child: tab);
  }
}

/// Bottom padding so content scrolls clear of the floating bar.
const double kNavBarClearance = 110;
