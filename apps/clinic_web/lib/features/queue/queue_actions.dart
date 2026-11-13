import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/connectivity.dart';
import '../../core/widgets/desktop.dart';
import '../../data/clinic_repository.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../print/clinic_form.dart';

/// Token actions shared by the Queue Board, token panel, check-in and
/// patient pages (C-04). The backend validates everything again (BW-1).
abstract final class QueueActions {
  /// Actions a role may take on a token in its current status.
  static List<TokenAction> available(QueueToken t, UserRole role) {
    if (!role.canRunQueue) return const [];
    return switch (t.status) {
      TokenStatus.booked => const [TokenAction.arrive, TokenAction.callNow, TokenAction.hold, TokenAction.cancel, TokenAction.noShow],
      TokenStatus.arrived => const [TokenAction.callNow, TokenAction.hold, TokenAction.reprint, TokenAction.cancel, TokenAction.noShow],
      TokenStatus.called => const [TokenAction.skip, TokenAction.hold, TokenAction.reprint],
      TokenStatus.onHold => const [TokenAction.callNow, TokenAction.backToQueue, TokenAction.cancel, TokenAction.noShow],
      TokenStatus.skipped => const [TokenAction.callNow, TokenAction.backToQueue, TokenAction.noShow],
      TokenStatus.completed => const [TokenAction.reprint],
      TokenStatus.cancelled || TokenStatus.noShow => const [],
    };
  }

  static String label(TokenAction a, QueueToken t) => switch (a) {
        TokenAction.arrive => 'Arrived & Print',
        TokenAction.callNow => t.status == TokenStatus.skipped ? 'Recall' : 'Call now',
        TokenAction.skip => 'Skip',
        TokenAction.hold => 'Hold',
        // D-24: from Skipped this means "came back": called right after the current patient.
        TokenAction.backToQueue => t.status == TokenStatus.skipped ? 'Arrived · call next' : 'Back to queue',
        TokenAction.cancel => 'Cancel token',
        TokenAction.noShow => 'Mark No-show',
        TokenAction.reprint => 'Reprint',
      };

  static IconData icon(TokenAction a) => switch (a) {
        TokenAction.arrive => Icons.how_to_reg_rounded,
        TokenAction.callNow => Icons.campaign_outlined,
        TokenAction.skip => Icons.skip_next_rounded,
        TokenAction.hold => Icons.pause_circle_outline_rounded,
        TokenAction.backToQueue => Icons.undo_rounded,
        TokenAction.cancel => Icons.cancel_outlined,
        TokenAction.noShow => Icons.person_off_outlined,
        TokenAction.reprint => Icons.print_outlined,
      };

  static bool isDanger(TokenAction a) => a == TokenAction.cancel || a == TokenAction.noShow;

  /// Runs an action with its confirmation step. Returns true when done.
  static Future<bool> perform(BuildContext context, WidgetRef ref, QueueToken t, TokenAction a) async {
    if (!ref.read(isOnlineProvider)) {
      showSnack(context, 'You are offline. Actions are disabled.');
      return false;
    }
    final repo = ref.read(repositoryProvider);
    String? reason;
    switch (a) {
      case TokenAction.cancel:
        reason = await askReason(
          context,
          title: 'Cancel token ${t.label}?',
          options: const ['Patient request', 'Duplicate', 'Other'],
          confirmLabel: 'Cancel token',
          note: 'If the patient uses the Asani app, they get a notification with this reason.', // D-23
        );
        if (reason == null) return false;
      case TokenAction.noShow:
        if (!context.mounted) return false;
        final ok = await confirmDialog(context, title: 'Mark ${t.label} as No-show?', message: '${t.token.patientSnapshot.name} will be removed from the queue.', confirmLabel: 'Mark No-show', danger: true);
        if (!ok) return false;
      case TokenAction.callNow:
        final current = repo.tokens(t.token.clinicId, t.token.date).where((x) => x.token.doctorId == t.token.doctorId && x.status == TokenStatus.called && x.id != t.id).firstOrNull;
        if (current != null && context.mounted) {
          final ok = await confirmDialog(context, title: 'Call ${t.label} now?', message: '${current.label} (now serving) will be marked Completed.', confirmLabel: 'Call now');
          if (!ok) return false;
        }
      case TokenAction.hold:
      case TokenAction.arrive:
      case TokenAction.skip:
      case TokenAction.backToQueue:
      case TokenAction.reprint:
        break;
    }
    if (!context.mounted) return false;
    final done = await runAction(context, () => repo.tokenAction(t.id, a, reason: reason));
    if (!done) return false;
    if (a == TokenAction.arrive || a == TokenAction.reprint) printForm(ref, repo.tokenById(t.id) ?? t);
    if (context.mounted) {
      showSnack(context, switch (a) {
        TokenAction.arrive => '${t.label} arrived. Printing the clinic form…',
        TokenAction.reprint => 'Printing ${t.label} again…',
        TokenAction.callNow => '${t.label} called. The patient has been notified.',
        TokenAction.cancel => '${t.label} cancelled.',
        _ => '${t.label}: ${a.logLabel}.',
      });
    }
    return true;
  }

  /// Prints the clinic form in the clinic's chosen format (C-07).
  static Future<void> printForm(WidgetRef ref, QueueToken t) async {
    final repo = ref.read(repositoryProvider);
    // The visit number needs this patient's history at the clinic.
    final history = await repo.loadClinicPatient(t.token.clinicId, t.token.patientId);
    final clinic = repo.clinic(t.token.clinicId);
    if (clinic == null || clinic.printFormat == PrintFormat.none) return;
    final doctor = repo.doctors(t.token.clinicId, includeInactive: true).where((d) => d.id == t.token.doctorId).firstOrNull;
    if (doctor == null) return;
    final earlier = (history?.visits ?? const <QueueToken>[])
        .where((v) => v.status == TokenStatus.completed && v.token.date.compareTo(t.token.date) < 0)
        .toList();
    ClinicFormTemplate.print(
      ClinicFormData(
        clinic: clinic.clinic,
        doctor: doctor,
        token: t,
        visitNumber: earlier.length + 1,
        lastVisit: earlier.isEmpty ? null : earlier.first.token.date,
      ),
      clinic.printFormat,
    );
  }

  /// "Copy patient details" for clinics with their own software (C-14).
  static String patientDetails(QueueToken t, Doctor? d) {
    final s = t.token.patientSnapshot;
    final age = s.age();
    return [
      'Token: ${t.label} (${Fmt.longDay(t.token.date)})',
      'Patient: ${s.name}',
      'Age/Sex: ${age ?? '-'} / ${s.gender.short}',
      'Phone: ${Fmt.phone(s.phone)}',
      if (d != null) 'Doctor: ${d.name}',
    ].join('\n');
  }
}

/// C-09: Set follow-up (3 days / 1 week / 2 weeks / 1 month / pick date).
Future<void> showFollowUpDialog(BuildContext context, WidgetRef ref, QueueToken t) async {
  final today = parseDayKey(dayKey(pktNow()));
  final presets = <String, int>{'3 days': 3, '1 week': 7, '2 weeks': 14, '1 month': 30};
  var due = today.add(const Duration(days: 7));
  final note = TextEditingController();
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AppDialog(
        title: 'Set follow-up',
        subtitle: '${t.token.patientSnapshot.name} · ${t.label}',
        width: 480,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final ok = await runAction(ctx, () => ref.read(repositoryProvider).setFollowUp(t.id, dayKey(due), note: note.text));
              if (ok && ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Save follow-up'),
          ),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
            for (final e in presets.entries)
              ChoiceChip(
                label: Text(e.key),
                selected: dayKey(due) == dayKey(today.add(Duration(days: e.value))),
                onSelected: (_) => setState(() => due = today.add(Duration(days: e.value))),
              ),
            ActionChip(
              avatar: const Icon(Icons.calendar_month_rounded, size: 18),
              label: const Text('Pick date'),
              onPressed: () async {
                final d = await showDatePicker(context: ctx, firstDate: today.add(const Duration(days: 1)), lastDate: today.add(const Duration(days: 365)), initialDate: due);
                if (d != null) setState(() => due = d);
              },
            ),
          ]),
          const SizedBox(height: Gap.lg),
          Banner2(text: 'Due on ${Fmt.longDay(dayKey(due))}', icon: Icons.event_rounded, fg: AppColors.primary, bg: AppColors.primaryContainer),
          const SizedBox(height: Gap.lg),
          FieldLabel(
            'Note (optional, non-medical)',
            child: TextField(controller: note, maxLength: 40, decoration: const InputDecoration(hintText: 'e.g. Review, Bring reports')),
          ),
          Text('The patient gets an app reminder automatically.', style: AppText.labelSmall),
        ]),
      ),
    ),
  );
  note.dispose();
  if (saved == true && context.mounted) showSnack(context, 'Follow-up set.');
}
