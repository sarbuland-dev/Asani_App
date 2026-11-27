import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/connectivity.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../admin/dashboard_screen.dart';

class _Item {
  const _Item(this.label, this.icon, this.path, {this.exact = false, this.sub = false});
  final String label;
  final IconData icon;
  final String path;
  final bool exact;
  final bool sub;
}

const _items = [
  _Item('Dashboard', Icons.space_dashboard_outlined, '/admin', exact: true),
  _Item('Clinics', Icons.local_hospital_outlined, '/admin/clinics'),
  _Item('Doctors', Icons.medical_services_outlined, '/admin/doctors'),
  _Item('Payments', Icons.credit_card_rounded, '/admin/payments'),
  _Item('Defaulters', Icons.warning_amber_rounded, '/admin/defaulters', sub: true),
  _Item('Activity', Icons.timeline_rounded, '/admin/activity'),
  _Item('Settings', Icons.settings_outlined, '/admin/settings'),
];

/// Super Admin screens: dark sidebar and page (board A-10 onwards).
class AdminFrame extends StatelessWidget {
  const AdminFrame({super.key, required this.user, required this.location, required this.child});
  final UserAccount user;
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _AdminSidebar(user: user, location: location),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const OfflineBanner(), Expanded(child: child)])),
      ]);
}

class _AdminSidebar extends ConsumerWidget {
  const _AdminSidebar({required this.user, required this.location});
  final UserAccount user;
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(linkSuggestionsProvider).where((s) => s.status == LinkStatus.open).length;
    final defaulters = ref.watch(defaultersProvider).length;

    return Container(
      width: 236,
      decoration: const BoxDecoration(color: AppColors.navy),
      foregroundDecoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topLeft,
          radius: 1.2,
          colors: [ClinicColors.sage.withValues(alpha: 0.18), ClinicColors.sage.withValues(alpha: 0)],
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(14, 22, 14, 8), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 18),
                child: Row(children: [
                  const AsaniLogoTile(size: 38),
                  const SizedBox(width: 10),
                  Text('asani', style: AppText.titleLarge.copyWith(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.onPrimary)),
                ]),
              ),
              _roleCard(),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
                child: Text('MANAGE', style: ClinicText.caps.copyWith(color: ClinicColors.sideSection)),
              ),
              for (final i in _items)
                _tile(
                  context,
                  i,
                  badge: switch (i.path) {
                    '/admin/doctors' when suggestions > 0 => CChip('$suggestions', fontSize: 11, bg: ClinicColors.chartAmber, fg: AppColors.textPrimary),
                    '/admin/defaulters' when defaulters > 0 => CChip('$defaulters', fontSize: 11, bg: ClinicColors.chartRed, fg: AppColors.textPrimary),
                    _ => null,
                  },
                ),
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 18), child: _me(context, ref)),
        ]),
      ),
    );
  }

  BoxDecoration get _glass => BoxDecoration(
        color: AppColors.onPrimary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.onPrimary.withValues(alpha: 0.1)),
      );

  Widget _roleCard() => Container(
        margin: const EdgeInsets.fromLTRB(4, 0, 4, 4),
        padding: const EdgeInsets.all(12),
        decoration: _glass,
        child: Row(children: [
          const IconTile(Icons.lock_outline_rounded, size: 34, bg: AppColors.cream),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Super admin', style: AppText.labelMedium.copyWith(color: AppColors.onPrimary)),
              Text('All clinics · Asani team', style: AppText.labelSmall.copyWith(fontSize: 11, color: AppColors.primarySoft)),
            ]),
          ),
        ]),
      );

  Widget _tile(BuildContext context, _Item item, {Widget? badge}) {
    final selected = item.exact ? location == item.path : location == item.path || location.startsWith('${item.path}/');
    final fg = selected ? AppColors.primary : AppColors.onPrimaryMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? AppColors.cream : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            hoverColor: AppColors.onPrimary.withValues(alpha: 0.07),
            onTap: () => context.go(item.path),
            child: Padding(
              padding: EdgeInsets.fromLTRB(item.sub ? 42 : 12, 11, 12, 11),
              child: Row(children: [
                if (!item.sub) ...[Icon(item.icon, size: 18, color: fg), const SizedBox(width: 12)],
                Expanded(
                  child: Text(item.label,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.labelMedium.copyWith(fontSize: item.sub ? 13 : 14, color: fg, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                ),
                ?badge,
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _me(BuildContext context, WidgetRef ref) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: _glass,
        child: Row(children: [
          Av(user.name, size: 34, bg: AppColors.cream),
          const SizedBox(width: 10),
          Expanded(
            child: Tooltip(
              message: user.email,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user.name, overflow: TextOverflow.ellipsis, style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.onPrimary)),
                Text('Super admin', style: AppText.labelSmall.copyWith(fontSize: 11, color: AppColors.primarySoft)),
              ]),
            ),
          ),
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout_rounded, size: 18, color: AppColors.primarySoft),
            onPressed: () async {
              final ok = await confirmDialog(context, title: 'Log out?', message: 'You will need your email and password to log in again.', confirmLabel: 'Log out');
              if (ok) await ref.read(repositoryProvider).signOut();
            },
          ),
        ]),
      );
}
