import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/connectivity.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

class _Item {
  const _Item(this.label, this.icon, this.path);
  final String label;
  final IconData icon;
  final String path;
}

const _today = [
  _Item('Queue board', Icons.confirmation_number_outlined, '/queue'),
  _Item('Upcoming bookings', Icons.calendar_today_outlined, '/upcoming'),
  _Item('Patients', Icons.search_rounded, '/patients'),
  _Item('Follow-ups', Icons.event_repeat_rounded, '/follow-ups'),
  _Item('Daily summary', Icons.bar_chart_rounded, '/summary'),
];

const _clinic = [
  _Item('Doctors', Icons.medical_services_outlined, '/doctors'),
  _Item('Settings', Icons.settings_outlined, '/settings'),
  _Item('Billing', Icons.credit_card_rounded, '/billing'),
  _Item('Help', Icons.help_outline_rounded, '/help'),
];

/// Clinic screens: dark sidebar, banners, page (board W-10 onwards).
class ClinicFrame extends ConsumerWidget {
  const ClinicFrame({super.key, required this.user, required this.location, required this.child});
  final UserAccount user;
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinic = user.clinicId == null ? null : ref.watch(clinicProvider(user.clinicId!));
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Sidebar(user: user, clinic: clinic, location: location),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const OfflineBanner(),
          if (clinic != null) _StatusBanner(clinic: clinic),
          Expanded(child: child),
        ]),
      ),
    ]);
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.user, required this.clinic, required this.location});
  final UserAccount user;
  final ClinicAccount? clinic;
  final String location;

  bool _selected(_Item i) => location == i.path || location.startsWith('${i.path}/');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider).value ?? dayKey(pktNow());
    final id = user.clinicId;
    final due = id == null ? 0 : ref.watch(followUpsProvider(id)).where((f) => f.dueDate == today && f.status == FollowUpStatus.pending).length;

    Widget tile(_Item i) => _NavTile(item: i, selected: _selected(i), badge: i.path == '/follow-ups' && due > 0 ? '$due' : null);

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
          // Scrolls on short screens; the login stays at the bottom.
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
              if (clinic != null) _clinicCard(clinic!),
              _section('TODAY'),
              for (final i in _today) tile(i),
              _section('CLINIC'),
              for (final i in _clinic) tile(i),
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 18), child: _LoginCard(user: user)),
        ]),
      ),
    );
  }

  Widget _clinicCard(ClinicAccount c) => Container(
        margin: const EdgeInsets.fromLTRB(4, 0, 4, 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.onPrimary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.onPrimary.withValues(alpha: 0.1)),
        ),
        child: Row(children: [
          const IconTile(Icons.add_rounded, size: 34, bg: AppColors.primaryMid, fg: AppColors.onPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.clinic.name,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.labelMedium.copyWith(color: AppColors.onPrimary, height: 1.25)),
              Text('${c.clinic.area}, ${c.clinic.city}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.labelSmall.copyWith(fontSize: 11, color: AppColors.primarySoft)),
            ]),
          ),
        ]),
      );

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
        child: Text(text, style: ClinicText.caps.copyWith(color: ClinicColors.sideSection)),
      );
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.selected, this.badge});
  final _Item item;
  final bool selected;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    // D-51: the follow-ups tab is lime when open.
    final followUps = item.path == '/follow-ups';
    final activeBg = followUps ? ClinicColors.lime : AppColors.cream;
    final fg = selected ? (followUps ? ClinicColors.limeInk : AppColors.primary) : AppColors.onPrimaryMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            hoverColor: AppColors.onPrimary.withValues(alpha: 0.07),
            onTap: () => context.go(item.path),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(children: [
                Icon(item.icon, size: 18, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.labelMedium.copyWith(color: fg, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                ),
                if (badge != null)
                  CChip(badge!, fontSize: 11, fg: selected ? ClinicColors.limeSoft : ClinicColors.limeInk, bg: selected ? ClinicColors.limeInk : ClinicColors.limeSoft)
                else if (selected && item.path == '/queue')
                  const LiveDot(),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The clinic has one shared login (D-18), so no person's name is shown.
class _LoginCard extends ConsumerWidget {
  const _LoginCard({required this.user});
  final UserAccount user;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: AppColors.onPrimary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.onPrimary.withValues(alpha: 0.1)),
        ),
        child: Row(children: [
          const Av('Reception', size: 34, bg: AppColors.cream),
          const SizedBox(width: 10),
          Expanded(
            child: Tooltip(
              message: user.email,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Reception', style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.onPrimary)),
                Text('Clinic login', style: AppText.labelSmall.copyWith(fontSize: 11, color: AppColors.primarySoft)),
              ]),
            ),
          ),
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout_rounded, size: 18, color: AppColors.primarySoft),
            onPressed: () async {
              final ok = await confirmDialog(context, title: 'Log out?', message: 'You will need your email and password to log in again.', confirmLabel: 'Log out');
              if (!ok || !context.mounted) return;
              // A queue banner names a patient: it must not follow to the login page.
              ScaffoldMessenger.of(context).clearSnackBars();
              await ref.read(repositoryProvider).signOut();
            },
          ),
        ]),
      );
}

/// Grace (amber) and suspended (red) banners (C-15, BW-8).
class _StatusBanner extends ConsumerWidget {
  const _StatusBanner({required this.clinic});
  final ClinicAccount clinic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = clinic.status;
    if (status != ClinicStatus.grace && status != ClinicStatus.suspended) return const SizedBox.shrink();
    final open = ref.watch(invoicesProvider(clinic.id)).where((i) => i.isOpen).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final suspendOn = open.isEmpty ? null : open.first.dueDate.add(Duration(days: ref.watch(adminSettingsProvider).suspendDays));
    final suspended = status == ClinicStatus.suspended;
    final fg = suspended ? AppColors.dangerText : AppColors.warningText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
      child: NoteBox(
        suspended
            ? 'This clinic is suspended. You can view, export and cancel tokens; other changes wait until the payment is recorded.'
            : 'Payment pending. Please pay${suspendOn == null ? '' : ' by ${WebFmt.date(suspendOn)}'} to avoid interruption.',
        fg: fg,
        bg: suspended ? AppColors.dangerContainer : AppColors.warningContainer,
        icon: suspended ? Icons.block_rounded : Icons.warning_amber_rounded,
        action: TextButton(
          style: TextButton.styleFrom(foregroundColor: fg),
          onPressed: () => context.go('/billing'),
          child: const Text('See how to pay'),
        ),
      ),
    );
  }
}
