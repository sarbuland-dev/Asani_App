import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

/// Tabs: Home · Tokens · Family · Account (DESIGN.md §4), floating pill bar.
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
            height: 68,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(Radii.pill),
              boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 6))],
            ),
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
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

class _NavItem extends StatelessWidget {
  const _NavItem({required this.item, required this.selected, required this.onTap});
  final (IconData, IconData, String) item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, activeIcon, label) = item;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? AppColors.onPrimary.withValues(alpha: 0.18) : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.button),
              ),
              child: Icon(selected ? activeIcon : icon, color: AppColors.onPrimary, size: 22),
            ),
            const SizedBox(height: 2),
            ExcludeSemantics(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.labelSmall.copyWith(
                  color: AppColors.onPrimary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom padding so content scrolls clear of the floating bar.
const double kNavBarClearance = 110;
