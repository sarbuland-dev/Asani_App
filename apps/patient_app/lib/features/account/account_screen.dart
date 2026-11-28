import 'package:asani_core/asani_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_info.dart';
import '../../core/config/env.dart';
import '../../core/errors/app_exception.dart';
import 'package:asani_ui/asani_ui.dart';
import '../../core/utils/device.dart';
import '../../core/utils/launch.dart';
import '../../data/providers.dart';
import '../auth/phone_field.dart';
import '../../data/repositories/repositories.dart';
import '../home/home_screen.dart' show showCityPicker;
import '../../core/widgets/bottom_clearance.dart';


/// S-16 Account (PRD F-10).
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final settings = ref.watch(settingsProvider).value;
    ref.watch(myTokensProvider); // refresh demo tools when tokens change
    final sim = ref.watch(queueSimulatorProvider);
    final isXiaomi = ref.watch(isXiaomiPhoneProvider).value ?? false;
    final simDoctors = sim.doctorsWithMyActiveTokens();
    if (user == null) return const Scaffold(body: SizedBox());

    final on = _alertsOn(user, settings);
    final city = ref.watch(selectedCityProvider);
    Widget card(List<Widget> children) => Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        );

    return StatusBarScrim(
      child: Scaffold(
      body: ListView(
        padding: EdgeInsets.only(bottom: bottomClearance(context)),
        children: [
          // Board P6 S-16: "Account" and a cream card with the user. The name is
          // changed from Family > the Self profile > Edit (that also updates the account).
          Container(
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, Gap.xl, 20, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Account', style: AppText.headline.copyWith(color: AppColors.onPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(18)),
                    child: Row(children: [
                      Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                        child: Text(Fmt.initials(user.name),
                            style: AppText.labelLarge.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(user.name, style: AppText.labelLarge.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (user.email.isNotEmpty)
                            Text(user.email, style: AppText.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(Fmt.phone(user.phone), style: AppText.labelSmall),
                        ]),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, Gap.md, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              card([
                _Tile(
                  icon: Icons.notifications_none_rounded,
                  label: 'Queue alerts',
                  // The web preview never receives pushes.
                  chip: kIsWeb ? 'Phone only' : (on ? 'On' : 'Off'),
                  chipOn: !kIsWeb && on,
                  onTap: () => kIsWeb
                      ? showSnack(context, 'Queue alerts come to the Asani app on a phone.')
                      : _toggleNotifications(context, ref, on),
                ),
                _Tile(icon: Icons.location_on_outlined, label: 'City', value: city, onTap: () => showCityPicker(context, ref)),
                // D-52: the login email can't be changed here.
                _Tile(icon: Icons.mail_outline_rounded, label: 'Email', value: user.email),
                // D-52 (S-4): the number is not verified; one number per Asani account.
                _Tile(
                  icon: Icons.phone_outlined,
                  label: 'Mobile number',
                  value: Fmt.phone(user.phone),
                  action: 'Edit',
                  onTap: () => _changePhone(context, ref, user.phone),
                  last: true,
                ),
              ]),
              // Autostart tip: only Xiaomi/Redmi/POCO phones need it.
              if (isXiaomi) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
                  decoration: BoxDecoration(color: AppColors.warningContainer, borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'Using a Xiaomi or Redmi phone? ', style: TextStyle(fontWeight: FontWeight.w700)),
                        const TextSpan(text: 'Turn on Autostart so alerts arrive on time.'),
                      ]),
                      style: AppText.labelSmall.copyWith(color: AppColors.warningText, fontSize: 13, height: 1.5),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        style: TextButton.styleFrom(foregroundColor: AppColors.warningText),
                        onPressed: () => _showMiuiGuide(context),
                        child: const Text('Show me how'),
                      ),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 10),
              card([
                _Tile(icon: Icons.shield_outlined, label: 'Privacy Policy', onTap: () => openUrl(context, AppLinks.privacy)),
                _Tile(icon: Icons.description_outlined, label: 'Terms', onTap: () => openUrl(context, AppLinks.terms)),
                _Tile(icon: Icons.help_outline_rounded, label: 'Contact support', onTap: () => openUrl(context, AppLinks.support), last: true),
              ]),
              // Demo mode only: in Firebase mode tools/queue-sim moves the real queue.
              if (Env.isDemo) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.science_outlined, color: AppColors.primary, size: 20),
                      const SizedBox(width: Gap.sm),
                      Text('Demo tools', style: AppText.labelLarge.copyWith(fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: Gap.xs),
                    Text('The clinic side is simulated. Queues move forward on their own every 15 seconds.', style: AppText.labelSmall),
                    // Own Material so the tile's ripple shows on the cream box.
                    Material(
                      type: MaterialType.transparency,
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Auto-move queues', style: AppText.labelMedium),
                        value: settings?.autoAdvanceQueue ?? true,
                        onChanged: (v) {
                          final repo = ref.read(settingsRepositoryProvider);
                          repo.update(repo.settings.copyWith(autoAdvanceQueue: v));
                        },
                      ),
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
                    if (simDoctors.isEmpty) Text('Book a token for today to move its queue by hand.', style: AppText.labelSmall),
                  ]),
                ),
              ],
              const SizedBox(height: Gap.lg),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    onPressed: () async {
                      final ok = await confirmDialog(context,
                          title: 'Log out?', message: 'You can sign in again with your email.', confirmLabel: 'Log out');
                      if (ok) await ref.read(authRepositoryProvider).signOut();
                    },
                    child: const Text('Log out'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size.fromHeight(46)),
                    onPressed: () => _deleteAccount(context, ref),
                    child: const Text('Delete account'),
                  ),
                ),
              ]),
              const SizedBox(height: Gap.sm),
              Text('Version $appVersion', textAlign: TextAlign.center, style: AppText.labelSmall),
            ]),
          ),
        ],
      ),
    ));
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
  const _Tile(
      {required this.icon, required this.label, this.value, this.chip, this.chipOn = false, this.action, this.onTap, this.last = false});
  final IconData icon;
  final String label;
  final String? value;

  /// Green text button at the end (e.g. "Edit") instead of the chevron.
  final String? action;
  final String? chip;
  final bool chipOn;
  final VoidCallback? onTap;
  final bool last;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.cream))),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: Gap.md),
            Expanded(child: Text(label, style: AppText.bodyLarge.copyWith(fontSize: 15))),
            if (chip != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: chipOn ? AppColors.successContainer : AppColors.dangerContainer,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(chip!,
                    style: AppText.labelSmall.copyWith(
                        fontSize: 11, fontWeight: FontWeight.w600, color: chipOn ? AppColors.successText : AppColors.dangerText)),
              ),
            if (value != null)
              Flexible(
                child: Text(value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700)),
              ),
            if (action != null) ...[
              const SizedBox(width: Gap.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(Radii.pill)),
                child: Text(action!, style: AppText.labelMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
            ] else if (onTap != null && chip == null)
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          ]),
        ),
      );
}

/// Kept for routes that want to jump to the account tab.
void goAccount(BuildContext context) => context.go('/account');

/// Account → Mobile number (D-52, S-4): change the contact number. Not verified; `phone-taken`
/// when another Asani account uses it. The account's family profiles get the new number.
Future<void> _changePhone(BuildContext context, WidgetRef ref, String current) async {
  final controller = TextEditingController(text: PhoneUtils.formatLocal(PhoneUtils.normalizeLocal(current)));
  String? error;
  var saving = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        Future<void> save() async {
          setState(() {
            saving = true;
            error = null;
          });
          try {
            await ref.read(authRepositoryProvider).updatePhone(controller.text);
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            if (context.mounted) showSnack(context, 'Mobile number updated.');
          } catch (e) {
            setState(() => error = AppException.messageOf(e));
          } finally {
            if (dialogContext.mounted) setState(() => saving = false);
          }
        }

        final valid = PhoneUtils.isValidLocal(controller.text);
        return AlertDialog(
          title: const Text('Mobile number'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PkPhoneField(
              controller: controller,
              enabled: !saving,
              autofocus: true,
              error: error != null,
              onChanged: () => setState(() => error = null),
              onSubmitted: valid && !saving ? save : null,
            ),
            if (error != null) ...[
              const SizedBox(height: Gap.sm),
              Text(error!, style: AppText.labelSmall.copyWith(color: AppColors.danger)),
            ],
            const SizedBox(height: Gap.md),
            const PhoneNote(),
          ]),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: valid && !saving ? save : null, child: saving ? const ButtonSpinner() : const Text('Save number')),
          ],
        );
      },
    ),
  );
  controller.dispose();
}
