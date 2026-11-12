import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/desktop.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// W-18 / C-12: staff accounts of the clinic.
class StaffScreen extends ConsumerWidget {
  const StaffScreen(this.clinicId, {super.key});
  final String clinicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PageScaffold(
        title: 'Staff',
        subtitle: 'Each person sets their own password from the invite email.',
        actions: [
          FilledButton.icon(
            onPressed: () => showAddStaffDialog(context, ref, clinicId),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Add staff'),
          ),
        ],
        child: StaffTable(clinicId: clinicId),
      );
}

/// Staff list with actions. Also used in the super admin clinic detail.
class StaffTable extends ConsumerWidget {
  const StaffTable({super.key, required this.clinicId, this.showInvitedBy = false});
  final String clinicId;
  final bool showInvitedBy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(staffProvider(clinicId));
    final me = ref.watch(currentUserProvider)!;
    final doctors = ref.watch(allDoctorsProvider(clinicId));
    final repo = ref.watch(repositoryProvider);
    String roleText(StaffAccount s) {
      if (s.role != StaffRole.doctor) return s.role.label;
      final d = doctors.where((d) => d.id == s.doctorId).firstOrNull;
      return d == null ? 'Doctor' : 'Doctor · ${d.tokenPrefix}';
    }

    return AppTable(
      columns: [
        const TableColumn('Name', flex: 4),
        const TableColumn('Role', flex: 2),
        const TableColumn('Status', flex: 2),
        TableColumn(showInvitedBy ? 'Added by' : 'Last login', flex: 3),
        const TableColumn('', flex: 3, align: TextAlign.right),
      ],
      rows: [
        for (final s in staff)
          [
            Row(children: [
              InitialsAvatar(name: s.name, size: 34, bg: s.status == StaffStatus.disabled ? AppColors.border : AppColors.primary),
              const SizedBox(width: Gap.md),
              Expanded(child: TwoLine(s.isMainAccount ? '${s.name} · main account' : s.name, s.email)),
            ]),
            Text(roleText(s), style: AppText.bodyMedium),
            StaffStatusPill(s.status),
            Text(
              showInvitedBy
                  ? '${s.invitedBy ?? '—'} · ${WebFmt.date(s.createdAt)}'
                  : (s.lastLoginAt == null ? 'Never' : WebFmt.ago(s.lastLoginAt!, now: pktNow())),
              style: AppText.bodyMedium,
            ),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (s.status == StaffStatus.invited)
                TextButton(onPressed: () => runAction(context, () => repo.resendInvite(s.uid), success: 'Invite sent again to ${s.email}.'), child: const Text('Resend invite')),
              // C-12: an admin cannot change themselves or the clinic's main account.
              if (s.uid != me.uid && (!s.isMainAccount || me.role == StaffRole.superAdmin))
                PopupMenuButton<String>(
                  tooltip: 'Actions',
                  onSelected: (v) async {
                    switch (v) {
                      case 'role':
                        await _changeRole(context, ref, s);
                      case 'disable':
                        final ok = await confirmDialog(context,
                            title: 'Disable ${s.name}?', message: 'They are signed out everywhere within minutes and cannot log in.', confirmLabel: 'Disable', danger: true);
                        if (ok && context.mounted) await runAction(context, () => repo.updateStaff(s.uid, status: StaffStatus.disabled), success: '${s.name} disabled.');
                      case 'enable':
                        await runAction(context, () => repo.updateStaff(s.uid, status: StaffStatus.active), success: '${s.name} enabled.');
                    }
                  },
                  itemBuilder: (_) => [
                    if (!s.isMainAccount) const PopupMenuItem(value: 'role', child: Text('Change role')),
                    if (s.status != StaffStatus.disabled) const PopupMenuItem(value: 'disable', child: Text('Disable')),
                    if (s.status == StaffStatus.disabled) const PopupMenuItem(value: 'enable', child: Text('Enable')),
                  ],
                ),
            ]),
          ],
      ],
    );
  }

  Future<void> _changeRole(BuildContext context, WidgetRef ref, StaffAccount s) async {
    final result = await showDialog<(StaffRole, String?)>(
      context: context,
      builder: (_) => _RoleDialog(clinicId: clinicId, title: 'Change role: ${s.name}', initialRole: s.role, initialDoctor: s.doctorId),
    );
    if (result == null || !context.mounted) return;
    await runAction(context, () => ref.read(repositoryProvider).updateStaff(s.uid, role: result.$1, doctorId: result.$2), success: 'Role changed.');
  }
}

/// Add staff: name, email, role (+ doctor) → invite email (§5.2).
Future<void> showAddStaffDialog(BuildContext context, WidgetRef ref, String clinicId) =>
    showDialog<void>(context: context, builder: (_) => _AddStaffDialog(clinicId: clinicId));

class _AddStaffDialog extends ConsumerStatefulWidget {
  const _AddStaffDialog({required this.clinicId});
  final String clinicId;

  @override
  ConsumerState<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends ConsumerState<_AddStaffDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  StaffRole _role = StaffRole.receptionist;
  String? _doctorId;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_role == StaffRole.doctor && _doctorId == null) {
      showSnack(context, 'Pick which doctor this login is for.');
      return;
    }
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref.read(repositoryProvider).inviteStaff(widget.clinicId, name: _name.text, email: _email.text, role: _role, doctorId: _doctorId),
      success: 'Invite sent to ${_email.text.trim()}.',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final doctors = ref.watch(doctorsProvider(widget.clinicId));
    return AppDialog(
      title: 'Add staff',
      subtitle: 'They get a "Set your Asani password" email.',
      width: 520,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(onPressed: _busy ? null : _invite, icon: const Icon(Icons.send_rounded, size: 18), label: const Text('Send invite')),
      ],
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FieldLabel('Full name', child: TextFormField(controller: _name, autofocus: true, textCapitalization: TextCapitalization.words, validator: (v) => (v ?? '').trim().length < 2 ? 'Enter a name' : null)),
          FieldLabel(
            'Email',
            child: TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(hintText: 'name@clinic.com'),
              validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email',
            ),
          ),
          _RolePicker(role: _role, doctorId: _doctorId, doctors: doctors, onChanged: (r, d) => setState(() {
                _role = r;
                _doctorId = d;
              })),
        ]),
      ),
    );
  }
}

class _RoleDialog extends ConsumerStatefulWidget {
  const _RoleDialog({required this.clinicId, required this.title, required this.initialRole, this.initialDoctor});
  final String clinicId;
  final String title;
  final StaffRole initialRole;
  final String? initialDoctor;

  @override
  ConsumerState<_RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends ConsumerState<_RoleDialog> {
  late StaffRole _role = widget.initialRole;
  late String? _doctorId = widget.initialDoctor;

  @override
  Widget build(BuildContext context) => AppDialog(
        title: widget.title,
        width: 480,
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: _role == StaffRole.doctor && _doctorId == null ? null : () => Navigator.pop(context, (_role, _doctorId)),
            child: const Text('Save'),
          ),
        ],
        child: _RolePicker(
          role: _role,
          doctorId: _doctorId,
          doctors: ref.watch(doctorsProvider(widget.clinicId)),
          onChanged: (r, d) => setState(() {
            _role = r;
            _doctorId = d;
          }),
        ),
      );
}

class _RolePicker extends StatelessWidget {
  const _RolePicker({required this.role, required this.doctorId, required this.doctors, required this.onChanged});
  final StaffRole role;
  final String? doctorId;
  final List<Doctor> doctors;
  final void Function(StaffRole, String?) onChanged;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FieldLabel(
          'Role',
          child: Wrap(spacing: Gap.sm, children: [
            for (final r in const [StaffRole.receptionist, StaffRole.doctor, StaffRole.clinicAdmin])
              ChoiceChip(label: Text(r.label), selected: role == r, onSelected: (_) => onChanged(r, r == StaffRole.doctor ? doctorId : null)),
          ]),
        ),
        if (role == StaffRole.doctor)
          FieldLabel(
            'Which doctor?',
            child: Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
              for (final d in doctors)
                ChoiceChip(avatar: LetterBadge(d.tokenPrefix, size: 22), label: Text(d.name), selected: doctorId == d.id, onSelected: (_) => onChanged(role, d.id)),
            ]),
          ),
        Text(switch (role) {
          StaffRole.receptionist => 'Runs the queue: check-in, walk-ins, printing, follow-ups.',
          StaffRole.doctor => 'Sees own queue, calls Next, sets follow-ups.',
          StaffRole.clinicAdmin => 'Everything, plus doctors, staff, settings and billing.',
          StaffRole.superAdmin => '',
        }, style: AppText.labelSmall),
      ]);
}
