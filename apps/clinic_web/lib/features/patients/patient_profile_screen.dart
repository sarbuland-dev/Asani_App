import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../core/web/download.dart';
import '../../core/widgets/desktop.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../queue/walk_in_dialog.dart';
import 'link_account_dialog.dart';

/// W-14 / C-08: one patient's history at this clinic only.
class PatientProfileScreen extends ConsumerWidget {
  const PatientProfileScreen({super.key, required this.clinicId, required this.patientId});
  final String clinicId;
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cp = ref.watch(clinicPatientProvider((clinicId, patientId)));
    final user = ref.watch(currentUserProvider)!;
    final doctors = ref.watch(allDoctorsProvider(clinicId));
    final clinic = ref.watch(clinicProvider(clinicId));
    final today = ref.watch(todayProvider).value ?? dayKey(pktNow());
    String doctorName(String id) => doctors.where((d) => d.id == id).firstOrNull?.name ?? '—';
    if (cp == null) {
      if (ref.watch(repositoryProvider).isLoadingPatient(patientId)) {
        return const Padding(padding: EdgeInsets.all(Gap.xxl), child: SkeletonList(count: 4));
      }
      return const Center(child: EmptyState(icon: Icons.person_off_outlined, title: 'Patient not found', message: 'This patient has no visits at this clinic.'));
    }
    final p = cp.patient;
    final visits = cp.visits;
    final writable = clinic?.status.acceptsBookings ?? false;

    return PageScaffold(
      title: p.name,
      subtitle: '${p.relation.label} · ${p.age(pktNow()) ?? '—'} / ${p.gender.label} · ${Fmt.phone(p.phone)}',
      leading: HeaderBackButton(dark: true, onPressed: () => context.go('/patients')),
      actions: [
        // D-40: only walk-ins (no app account) are edited by the clinic.
        if (user.role.canRunQueue && p.ownerUid == null)
          OutlinedButton.icon(
            onPressed: () => _edit(context, ref, p),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit details'),
          ),
        if (p.ownerUid != null) const Center(child: Text('Managed by the patient in the Asani app')),
        // D-52 (S-2): reception links a walk-in to the patient's app account, in person.
        if (user.role.canRunQueue && p.ownerUid == null && p.status == PatientStatus.active)
          OutlinedButton.icon(
            onPressed: () => showLinkAccountDialog(context, clinicId: clinicId, walkIn: p),
            icon: const Icon(Icons.link_rounded, size: 18),
            label: const Text('Link to app account'),
          ),
        if (user.role.canRunQueue)
          FilledButton.icon(
            onPressed: writable
                ? () async {
                    final t = await showWalkInDialog(context, clinicId, phone: p.phone, patientId: p.id);
                    if (t != null && context.mounted) context.go('/queue');
                  }
                : null,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Book token'),
          ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardGrid(minWidth: 220, children: [
          KpiCard(label: 'Visits here', value: '${cp.visitCount}', icon: Icons.event_available_rounded),
          KpiCard(label: 'Last visit', value: cp.lastVisit == null ? '—' : Fmt.shortDay(cp.lastVisit!.token.date), icon: Icons.history_rounded),
          KpiCard(
            label: 'Phone',
            value: Fmt.phone(p.phone),
            icon: Icons.call_outlined,
            hint: 'Click to copy',
            onTap: () async {
              await copyText(p.phone);
              if (context.mounted) showSnack(context, 'Phone number copied.');
            },
          ),
          KpiCard(label: 'App account', value: p.ownerUid == null ? 'No' : 'Yes', icon: Icons.phone_iphone_rounded),
        ]),
        if (cp.followUps.isNotEmpty) ...[
          const SectionTitle('Follow-ups'),
          AppTable(
            columns: const [TableColumn('Due', flex: 2), TableColumn('Doctor', flex: 3), TableColumn('Note', flex: 3), TableColumn('Status', flex: 2)],
            rows: [
              for (final f in cp.followUps)
                [
                  Text(Fmt.relativeDay(f.dueDate), style: AppText.labelMedium),
                  Text(doctorName(f.doctorId), style: AppText.bodyMedium),
                  Text(f.note ?? '—', style: AppText.bodyMedium),
                  FollowUpPill(effectiveFollowUpStatus(f, today)),
                ],
            ],
          ),
        ],
        const SectionTitle('Visit history at this clinic'),
        AppTable(
          columns: const [
            TableColumn('Date', flex: 3),
            TableColumn('Token', flex: 2),
            TableColumn('Doctor', flex: 3),
            TableColumn('Source', flex: 2),
            TableColumn('Wait', flex: 2),
            TableColumn('Status', flex: 2),
          ],
          empty: const Padding(padding: EdgeInsets.all(Gap.xl), child: Center(child: Text('No visits yet.'))),
          rows: [
            for (final v in visits)
              [
                Text(Fmt.longDay(v.token.date), style: AppText.labelMedium),
                Text(v.label, style: AppText.labelLarge.copyWith(color: AppColors.primary)),
                Text(doctorName(v.token.doctorId), style: AppText.bodyMedium),
                SourcePill(v.source),
                Text(WebFmt.minutes(v.waitMinutes), style: AppText.bodyMedium),
                StatusChip(v.status),
              ],
          ],
        ),
      ]),
    );
  }

  /// Typo fixes only (name/age/gender), logged (C-08, Q-W07 open).
  Future<void> _edit(BuildContext context, WidgetRef ref, Patient p) async {
    final name = TextEditingController(text: p.name);
    final age = TextEditingController(text: p.age(pktNow())?.toString() ?? '');
    var gender = p.gender;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AppDialog(
          title: 'Edit patient details',
          subtitle: 'For typo fixes. The change is logged.',
          width: 460,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final a = int.tryParse(age.text);
                if (name.text.trim().length < 2) return;
                final ok = await runAction(
                  ctx,
                  () => ref.read(repositoryProvider).updatePatient(clinicId, p.id, name: name.text, birthYear: a == null ? null : pktNow().year - a, gender: gender),
                  success: 'Patient details updated.',
                );
                if (ok && ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
          child: Column(children: [
            FieldLabel('Full name', child: TextField(controller: name, textCapitalization: TextCapitalization.words)),
            FieldLabel(
              'Age',
              child: TextField(controller: age, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)]),
            ),
            FieldLabel(
              'Gender',
              child: Wrap(spacing: Gap.sm, children: [
                for (final g in Gender.values) ChoiceChip(label: Text(g.label), selected: gender == g, onSelected: (_) => setState(() => gender = g)),
              ]),
            ),
          ]),
        ),
      ),
    );
    name.dispose();
    age.dispose();
  }
}
