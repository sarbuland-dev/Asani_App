import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_info.dart';
import '../../core/config/env.dart';
import '../../core/errors/app_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launch.dart';
import '../../core/widgets/common.dart';
import '../../data/providers.dart';
import '../../data/repositories/repositories.dart';
import '../shell/main_shell.dart';


/// S-16 Account (PRD F-10).
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final settings = ref.watch(settingsProvider).value;
    ref.watch(myTokensProvider); // refresh demo tools when tokens change
    final sim = ref.watch(queueSimulatorProvider);
    final simDoctors = sim.doctorsWithMyActiveTokens();
    if (user == null) return const Scaffold(body: SizedBox());

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: kNavBarClearance),
        children: [
          GradientHeader(
            child: Row(children: [
              InitialsAvatar(name: user.name, size: 64, bg: AppColors.surface, fg: AppColors.primary),
              const SizedBox(width: Gap.lg),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user.name, style: AppText.titleLarge.copyWith(color: AppColors.onPrimary, fontSize: 24)),
                  Text(Fmt.phone(user.phone), style: AppText.bodyLarge.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.9))),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(Gap.screen),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  _Tile(icon: Icons.edit_outlined, label: 'Edit name', onTap: () => _editName(context, ref, user.name)),
                  _Tile(
                    icon: Icons.notifications_none_rounded,
                    label: 'Notifications',
                    value: _alertsOn(user, settings) ? 'On' : 'Off',
                    valueColor: _alertsOn(user, settings) ? AppColors.success : AppColors.danger,
                    onTap: () => _toggleNotifications(context, ref, _alertsOn(user, settings)),
                  ),
                  _Tile(icon: Icons.shield_outlined, label: 'Privacy Policy', onTap: () => openUrl(context, AppLinks.privacy)),
                  _Tile(icon: Icons.description_outlined, label: 'Terms', onTap: () => openUrl(context, AppLinks.terms)),
                  _Tile(icon: Icons.help_outline_rounded, label: 'Contact support', onTap: () => openUrl(context, AppLinks.support)),
                  const _Tile(icon: Icons.info_outline_rounded, label: 'App version', value: appVersion, last: true),
                ]),
              ),
              const SizedBox(height: Gap.lg),
              AppCard(
                color: AppColors.warningContainer.withValues(alpha: 0.6),
                borderColor: AppColors.warningContainer,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const IconBox(icon: Icons.phone_android_rounded, bg: AppColors.warningContainer, fg: AppColors.warning),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Using a Xiaomi/Redmi phone?', style: AppText.labelLarge),
                      Text("Turn on Autostart so you don't miss alerts.", style: AppText.bodyMedium),
                      const SizedBox(height: Gap.sm),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.warning, side: const BorderSide(color: AppColors.warning)),
                        onPressed: () => _showMiuiGuide(context),
                        child: const Text('Show me how'),
                      ),
                    ]),
                  ),
                ]),
              ),
              // Demo mode only: in Firebase mode tools/queue-sim moves the real queue.
              if (Env.isDemo) ...[
              const SizedBox(height: Gap.lg),
              // Stand-in for the clinic desktop app until Phase 2 (tools/queue-sim).
              AppCard(
                color: AppColors.infoContainer.withValues(alpha: 0.5),
                borderColor: AppColors.infoContainer,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.science_outlined, color: AppColors.info),
                    const SizedBox(width: Gap.sm),
                    Text('Demo tools', style: AppText.labelLarge.copyWith(color: AppColors.infoDark)),
                  ]),
                  const SizedBox(height: Gap.xs),
                  Text('The clinic side is simulated. Queues move forward on their own every 15 seconds.',
                      style: AppText.bodyMedium),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Auto-move queues', style: AppText.labelMedium),
                    value: settings?.autoAdvanceQueue ?? true,
                    onChanged: (v) {
                      final repo = ref.read(settingsRepositoryProvider);
                      repo.update(repo.settings.copyWith(autoAdvanceQueue: v));
                    },
                  ),
                  for (final d in simDoctors)
                    Padding(
                      padding: const EdgeInsets.only(top: Gap.xs),
                      child: OutlinedButton.icon(
                        onPressed: () => sim.advanceQueue(d.id),
                        icon: const Icon(Icons.skip_next_rounded),
                        label: Text('Next patient · ${d.name}'),
                      ),
                    ),
                  if (simDoctors.isEmpty)
                    Text('Book a token for today to move its queue by hand.', style: AppText.labelSmall),
                ]),
              ),
              ],
              const SizedBox(height: Gap.xl),
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await confirmDialog(context,
                        title: 'Log out?', message: 'You can sign in again with your phone number.', confirmLabel: 'Log out');
                    if (ok) await ref.read(authRepositoryProvider).signOut();
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Log out'),
                ),
              ),
              const SizedBox(height: Gap.sm),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () => _deleteAccount(context, ref),
                child: const Text('Delete account'),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  /// On = the account wants alerts (synced, D-18) AND this phone allows them.
  static bool _alertsOn(AppUser user, AppSettings? settings) =>
      user.queueAlertsEnabled && settings?.notificationsAllowed == true;

  /// Off: only the account switch, so it is off on every phone.
  /// On: account switch on; if this phone hasn't allowed notifications yet,
  /// show the permission primer.
  Future<void> _toggleNotifications(BuildContext context, WidgetRef ref, bool on) async {
    final auth = ref.read(authRepositoryProvider);
    try {
      if (on) {
        await auth.setQueueAlerts(false);
        if (context.mounted) showSnack(context, 'Queue alerts turned off.');
        return;
      }
      await auth.setQueueAlerts(true);
      if (!context.mounted) return;
      if (ref.read(settingsRepositoryProvider).settings.notificationsAllowed) {
        showSnack(context, 'Queue alerts turned on.');
      } else {
        context.push('/notifications');
      }
    } catch (e) {
      if (context.mounted) showSnack(context, AppException.messageOf(e));
    }
  }

  Future<void> _editName(BuildContext context, WidgetRef ref, String current) async {
    final name = await showDialog<String>(context: context, builder: (_) => _EditNameDialog(initial: current));
    if (name == null || name.trim().length < 2) return;
    await ref.read(authRepositoryProvider).updateName(name);
    if (context.mounted) showSnack(context, 'Name updated.');
  }

  /// Double confirmation: dialog, then type DELETE (DESIGN S-16).
  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final first = await confirmDialog(
      context,
      title: 'Delete your account?',
      message: 'Your profile, family members and tokens will be removed. Clinics keep anonymous visit records. This cannot be undone.',
      confirmLabel: 'Continue',
      danger: true,
    );
    if (!first || !context.mounted) return;
    final confirmed = await showDialog<bool>(context: context, builder: (_) => const _TypeDeleteDialog());
    if (confirmed != true) return;
    try {
      await ref.read(authRepositoryProvider).deleteAccount();
    } catch (e) {
      if (context.mounted) showSnack(context, AppException.messageOf(e));
    }
  }

  void _showMiuiGuide(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true, // above the floating nav bar
      isScrollControlled: true, // may be taller than the default 9/16 of the screen
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xl),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Keep Asani alerts working', style: AppText.titleLarge),
            const SizedBox(height: Gap.md),
            for (final (i, s) in const [
              'Open Settings → Apps → Manage apps → Asani.',
              'Turn on Autostart.',
              'Battery saver → choose "No restrictions".',
              'Notifications → allow all Asani notifications.',
            ].indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.xs + 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: AppColors.primaryContainer,
                    child: Text('${i + 1}', style: AppText.labelSmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(child: Text(s, style: AppText.bodyLarge)),
                ]),
              ),
            const SizedBox(height: Gap.lg),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
          ]),
        ),
      ),
    );
  }
}

/// Owns its text controller, so it is disposed only after the dialog's
/// closing animation (disposing it right after showDialog returns crashes).
class _EditNameDialog extends StatefulWidget {
  const _EditNameDialog({required this.initial});
  final String initial;

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Edit name', style: AppText.titleLarge),
        content: TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Full name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Save')),
        ],
      );
}

/// Second step of account deletion: type DELETE (DESIGN S-16).
class _TypeDeleteDialog extends StatefulWidget {
  const _TypeDeleteDialog();

  @override
  State<_TypeDeleteDialog> createState() => _TypeDeleteDialogState();
}

class _TypeDeleteDialogState extends State<_TypeDeleteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Type DELETE to confirm', style: AppText.titleLarge),
        content: TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'DELETE'),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: _controller.text.trim() == 'DELETE' ? () => Navigator.pop(context, true) : null,
            child: const Text('Delete account'),
          ),
        ],
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, this.value, this.valueColor, this.onTap, this.last = false});
  final IconData icon;
  final String label;
  final String? value;
  final Color? valueColor;
  final VoidCallback? onTap;
  final bool last;

  @override
  Widget build(BuildContext context) => Column(children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
            child: Row(children: [
              IconBox(icon: icon, size: 38),
              const SizedBox(width: Gap.md),
              Expanded(child: Text(label, style: AppText.labelLarge)),
              if (value != null)
                Text(value!, style: AppText.labelMedium.copyWith(color: valueColor ?? AppColors.textSecondary)),
              if (onTap != null) const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ]),
          ),
        ),
        if (!last) const Divider(indent: Gap.lg, endIndent: Gap.lg),
      ]);
}

/// Kept for routes that want to jump to the account tab.
void goAccount(BuildContext context) => context.go('/account');
