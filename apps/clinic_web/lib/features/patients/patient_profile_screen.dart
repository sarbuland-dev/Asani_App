import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../core/web/download.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../queue/walk_in_dialog.dart';
import 'link_account_dialog.dart';

/// W-14 / C-08: one patient's history at this clinic only (the right side of
/// the Patients page).
class PatientDetail extends ConsumerWidget {
  const PatientDetail({super.key, required this.clinicId, required this.patientId});
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

    final age = p.age(pktNow());
    final visit = cp.lastVisit == null
        ? 'No completed visits yet'
        : 'Last visit ${Fmt.shortDay(cp.lastVisit!.token.date)} · ${WebFmt.ordinal(cp.visitCount)} visit';
    // The board's buttons here are fully round.
    final outlined = OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary, shape: const StadiumBorder(), side: const BorderSide(color: AppColors.border));
    final filled = FilledButton.styleFrom(shape: const StadiumBorder());

    final identity = Row(children: [
      Av.solid(p.name, size: 60),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.name, style: AppText.titleMedium.copyWith(fontSize: 20, fontWeight: FontWeight.w700)),
          Tooltip(
            message: 'Click to copy the phone number',
            child: InkWell(
              onTap: () async {
                await copyText(p.phone);
                if (context.mounted) showSnack(context, 'Phone number copied.');
              },
              child: Text('${p.relation.label} · ${age ?? '—'} · ${p.gender.label} · ${Fmt.phone(p.phone)}', style: AppText.bodyMedium),
            ),
          ),
          Text(visit, style: AppText.bodyMedium),
          // D-40: why there is no Edit button.
          if (p.ownerUid != null) Text('Details are managed by the patient in the Asani app', style: ClinicText.small),
        ]),
      ),
    ]);

    final buttons = Wrap(spacing: 10, runSpacing: 10, children: [
      // D-40: only walk-ins (no app account) are edited by the clinic.
      if (user.role.canRunQueue && p.ownerUid == null)
        OutlinedButton(style: outlined, onPressed: () => _edit(context, ref, p), child: const Text('Edit details')),
      // D-52 (S-2): reception links a walk-in to the patient's app account, in person.
      if (user.role.canRunQueue && p.ownerUid == null && p.status == PatientStatus.active)
        OutlinedButton(
          style: outlined,
          onPressed: () => showLinkAccountDialog(context, clinicId: clinicId, walkIn: p),
          child: const Text('Link to app account'),
        ),
      if (user.role.canRunQueue)
        FilledButton(
          style: filled,
          onPressed: writable
              ? () async {
                  final t = await showWalkInDialog(context, clinicId, phone: p.phone, patientId: p.id);
                  if (t != null && context.mounted) context.go('/queue');
                }
              : null,
          child: const Text('Book token'),
        ),
    ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        radius: 16,
        child: LayoutBuilder(
          // One line like the board; the buttons drop below when space is short.
          builder: (context, box) => box.maxWidth >= 680
              ? Row(children: [Expanded(child: identity), const SizedBox(width: 16), buttons])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [identity, const SizedBox(height: 14), buttons]),
        ),
      ),
      // D-51: lime is the colour of follow-ups.
      for (final f in cp.followUps) ...[
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: const BoxDecoration(color: ClinicColors.lime),
            padding: const EdgeInsets.only(left: 4),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 18, 14),
              color: ClinicColors.limeTint,
              child: Row(children: [
                Text('Follow-up', style: AppText.labelMedium.copyWith(color: ClinicColors.limeText, fontWeight: FontWeight.w800)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${doctorName(f.doctorId)} · due ${Fmt.relativeDay(f.dueDate)}${f.note == null ? '' : ' · "${f.note}"'}',
                    style: AppText.bodyMedium.copyWith(color: ClinicColors.limeText),
                  ),
                ),
                const SizedBox(width: 12),
                CChip(effectiveFollowUpStatus(f, today).label, bg: AppColors.surface, fg: ClinicColors.limeText),
              ]),
            ),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Panel(
        radius: 16,
        padding: EdgeInsets.zero,
        child: SimpleTable(
          capsHeaders: false,
          columns: const [
            TableColumn('Date', flex: 4),
            TableColumn('Doctor', flex: 5),
            TableColumn('Token', flex: 2),
            TableColumn('Wait', flex: 2),
            TableColumn('Status', flex: 3),
          ],
          empty: Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('No visits yet.', style: AppText.bodyMedium))),
          rows: [
            for (final v in visits)
              [
                // How the token was made (app or walk-in) shows on hover.
                Tooltip(message: v.source == TokenSource.app ? 'Booked in the app' : 'Walk-in', child: Text(Fmt.longDay(v.token.date), style: ClinicText.body)),
                Text(doctorName(v.token.doctorId), style: ClinicText.body),
                Text(v.label, style: AppText.labelMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                Text(WebFmt.minutes(v.waitMinutes), style: ClinicText.body),
                TokenStatusChip(v.status),
              ],
          ],
        ),
      ),
    ]);
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
