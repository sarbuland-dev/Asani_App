import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/connectivity.dart';
import '../../core/theme/clinic_theme.dart';
import '../../core/widgets/desktop.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'clinic_frame.dart';

class _NavItem {
  const _NavItem(this.label, this.icon, this.path, {this.exact = false});
  final String label;
  final IconData icon;
  final String path;
  final bool exact;
}

List<_NavItem> _itemsFor(UserRole role) => switch (role) {
      UserRole.superAdmin => const [
          _NavItem('Dashboard', Icons.space_dashboard_outlined, '/admin', exact: true),
          _NavItem('Clinics', Icons.local_hospital_outlined, '/admin/clinics'),
          _NavItem('Same doctor', Icons.people_alt_outlined, '/admin/doctors'),
          _NavItem('Payments', Icons.receipt_long_outlined, '/admin/payments'),
          _NavItem('Defaulters', Icons.warning_amber_rounded, '/admin/defaulters'),
          _NavItem('Activity', Icons.history_rounded, '/admin/activity'),
          _NavItem('Settings', Icons.tune_rounded, '/admin/settings'),
        ],
      UserRole.clinic => const [], // the clinic has its own frame (ClinicFrame)
    };

/// Desktop frame: left sidebar, top bar (W-03), banners, page.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  /// PRD §9: minimum screen width 1280 px; below that the page scrolls sideways.
  static const minWidth = 1180.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    // The clinic screens follow the new board; the Super Admin keeps the old look.
    final isClinic = user.isClinic;
    final frame = isClinic
        ? ClinicFrame(user: user, location: location, child: child)
        : Row(children: [
            _Sidebar(user: user, location: location),
            Expanded(
              child: Column(children: [
                const _TopBar(),
                const OfflineBanner(),
                Expanded(child: child),
              ]),
            ),
          ]);

    final scaffold = Scaffold(
      body: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= minWidth) return frame;
        return SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: minWidth, height: c.maxHeight, child: frame));
      }),
    );
    return isClinic ? ClinicThemed(child: scaffold) : scaffold;
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.user, required this.location});
  final UserAccount user;
  final String location;

  bool _selected(_NavItem i) {
    if (i.exact) return location == i.path;
    return location == i.path || location.startsWith('${i.path}/');
  }

  @override
  Widget build(BuildContext context) {
    final items = _itemsFor(user.role);
    return Container(
      width: 248,
      decoration: const BoxDecoration(color: AppColors.surface, border: Border(right: BorderSide(color: AppColors.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.lg, Gap.xl),
          child: Row(children: [
            const AsaniMark(size: 36),
            const SizedBox(width: 4),
            Text('asani', style: AppText.titleLarge.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
            const SizedBox(width: Gap.sm),
            Pill(
              label: user.role == UserRole.superAdmin ? 'Admin' : 'Clinic',
              fg: user.role == UserRole.superAdmin ? AppColors.secondary : AppColors.primary,
              bg: user.role == UserRole.superAdmin ? AppColors.avatarCool : AppColors.primaryContainer,
            ),
          ]),
        ),
        for (final i in items) _NavTile(item: i, selected: _selected(i)),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Text('Asani Clinic Web · v0.1', style: AppText.labelSmall.copyWith(color: AppColors.textMuted)),
        ),
      ]),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.selected});
  final _NavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 2),
      child: Material(
        color: selected ? AppColors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.button),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: () => context.go(item.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.md),
            child: Row(children: [
              Icon(item.icon, size: 22, color: selected ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: Gap.md),
              Text(item.label,
                  style: AppText.labelLarge.copyWith(
                    fontSize: 15,
                    color: selected ? AppColors.primary : AppColors.textPrimary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  )),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Super Admin top bar: today, who is logged in, Log out.
class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final today = ref.watch(todayProvider).value ?? dayKey(pktNow());
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: Gap.xxl),
      decoration: const BoxDecoration(color: AppColors.surface, border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        Text('Super Admin', style: AppText.titleMedium),
        const SizedBox(width: Gap.lg),
        Pill(label: Fmt.longDay(today), fg: AppColors.textSecondary, bg: AppColors.muted, icon: Icons.calendar_today_rounded),
        const Spacer(),
        InitialsAvatar(name: user.name, size: 38),
        const SizedBox(width: Gap.md),
        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user.name, style: AppText.labelMedium),
          Text(user.role.label, style: AppText.labelSmall),
        ]),
        const SizedBox(width: Gap.lg),
        OutlinedButton.icon(
          onPressed: () async {
            final ok = await confirmDialog(context, title: 'Log out?', message: 'You will need your email and password to log in again.', confirmLabel: 'Log out');
            if (ok) await ref.read(repositoryProvider).signOut();
          },
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Log out'),
        ),
      ]),
    );
  }
}
