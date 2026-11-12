import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/connectivity.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/desktop.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

class _NavItem {
  const _NavItem(this.label, this.icon, this.path, {this.exact = false});
  final String label;
  final IconData icon;
  final String path;
  final bool exact;
}

List<_NavItem> _itemsFor(StaffRole role) => switch (role) {
      StaffRole.superAdmin => const [
          _NavItem('Dashboard', Icons.space_dashboard_outlined, '/admin', exact: true),
          _NavItem('Clinics', Icons.local_hospital_outlined, '/admin/clinics'),
          _NavItem('Payments', Icons.receipt_long_outlined, '/admin/payments'),
          _NavItem('Defaulters', Icons.warning_amber_rounded, '/admin/defaulters'),
          _NavItem('Activity', Icons.history_rounded, '/admin/activity'),
          _NavItem('Settings', Icons.tune_rounded, '/admin/settings'),
        ],
      StaffRole.doctor => const [
          _NavItem('My Queue', Icons.format_list_numbered_rounded, '/queue'),
          _NavItem('Patients', Icons.people_alt_outlined, '/patients'),
          _NavItem('Follow-ups', Icons.event_repeat_rounded, '/follow-ups'),
          _NavItem('Daily summary', Icons.insights_rounded, '/summary'),
          _NavItem('Help', Icons.help_outline_rounded, '/help'),
        ],
      StaffRole.receptionist => const [
          _NavItem('Queue Board', Icons.format_list_numbered_rounded, '/queue'),
          _NavItem('Patients', Icons.people_alt_outlined, '/patients'),
          _NavItem('Follow-ups', Icons.event_repeat_rounded, '/follow-ups'),
          _NavItem('Daily summary', Icons.insights_rounded, '/summary'),
          _NavItem('Help', Icons.help_outline_rounded, '/help'),
        ],
      StaffRole.clinicAdmin => const [
          _NavItem('Queue Board', Icons.format_list_numbered_rounded, '/queue'),
          _NavItem('Patients', Icons.people_alt_outlined, '/patients'),
          _NavItem('Follow-ups', Icons.event_repeat_rounded, '/follow-ups'),
          _NavItem('Daily summary', Icons.insights_rounded, '/summary'),
          _NavItem('Doctors', Icons.medical_services_outlined, '/doctors'),
          _NavItem('Staff', Icons.badge_outlined, '/staff'),
          _NavItem('Clinic settings', Icons.settings_outlined, '/settings'),
          _NavItem('Billing', Icons.receipt_long_outlined, '/billing'),
          _NavItem('Help', Icons.help_outline_rounded, '/help'),
        ],
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
    final clinic = user.clinicId == null ? null : ref.watch(clinicProvider(user.clinicId!));

    final frame = Row(children: [
      _Sidebar(user: user, location: location),
      Expanded(
        child: Column(children: [
          _TopBar(user: user, clinic: clinic),
          const OfflineBanner(),
          if (clinic != null) _ClinicBanner(clinic: clinic, isAdmin: user.role == StaffRole.clinicAdmin),
          Expanded(child: child),
        ]),
      ),
    ]);

    return Scaffold(
      body: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= minWidth) return frame;
        return SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: minWidth, height: c.maxHeight, child: frame));
      }),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.user, required this.location});
  final StaffAccount user;
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
              label: user.role == StaffRole.superAdmin ? 'Admin' : 'Clinic',
              fg: user.role == StaffRole.superAdmin ? AppColors.secondary : AppColors.primary,
              bg: user.role == StaffRole.superAdmin ? AppColors.avatarCool : AppColors.primaryContainer,
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

/// W-03: clinic name, who is logged in, Log out (shared reception PCs).
class _TopBar extends ConsumerWidget {
  const _TopBar({required this.user, required this.clinic});
  final StaffAccount user;
  final ClinicAccount? clinic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider).value ?? dayKey(pktNow());
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: Gap.xxl),
      decoration: const BoxDecoration(color: AppColors.surface, border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        if (clinic != null) ...[
          const IconBox(icon: Icons.local_hospital_rounded, size: 38),
          const SizedBox(width: Gap.md),
          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(clinic!.clinic.name, style: AppText.titleMedium),
            Text('${clinic!.clinic.area}, ${clinic!.clinic.city}', style: AppText.labelSmall),
          ]),
        ] else
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

/// Grace (yellow) and suspended (red) banners (C-15, BW-8).
class _ClinicBanner extends ConsumerWidget {
  const _ClinicBanner({required this.clinic, required this.isAdmin});
  final ClinicAccount clinic;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = clinic.status;
    if (status != ClinicStatus.grace && status != ClinicStatus.suspended) return const SizedBox.shrink();
    final open = ref.watch(invoicesProvider(clinic.id)).where((i) => i.isOpen).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final suspendOn = open.isEmpty ? null : open.first.dueDate.add(Duration(days: ref.watch(adminSettingsProvider).suspendDays));
    final suspended = status == ClinicStatus.suspended;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xxl, Gap.md, Gap.xxl, 0),
      child: Banner2(
        icon: suspended ? Icons.block_rounded : Icons.warning_amber_rounded,
        fg: suspended ? AppColors.danger : AppColors.warning,
        bg: suspended ? AppColors.dangerContainer : AppColors.warningContainer,
        text: suspended
            ? 'This clinic is suspended. You can view and export, but no new tokens or Next until the payment is recorded.'
            : 'Payment pending, please pay${suspendOn == null ? '' : ' by ${WebFmt.date(suspendOn)}'} to avoid interruption.',
        action: isAdmin ? TextButton(onPressed: () => context.go('/billing'), child: const Text('View billing')) : null,
      ),
    );
  }
}
