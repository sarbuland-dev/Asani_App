import 'package:flutter/material.dart';

import '../../core/widgets/clinic_kit.dart';
import '../../data/clinic_repository.dart';

/// D-57: amber notice after Next skipped patients who had not arrived. There
/// is nothing to choose, only OK.
Future<void> showNotArrivedNotice(BuildContext context, List<NotArrived> skipped) =>
    showDialog<void>(context: context, builder: (_) => _NotArrivedNotice(skipped));

class _NotArrivedNotice extends StatelessWidget {
  const _NotArrivedNotice(this.skipped);
  final List<NotArrived> skipped;

  @override
  Widget build(BuildContext context) {
    final one = skipped.length == 1;
    final title = one ? '${skipped.first.label} has not arrived yet' : '${skipped.length} patients have not arrived yet';
    final who = one
        ? '${skipped.first.name.isEmpty ? 'This patient' : skipped.first.name} was skipped.'
        : 'These patients were skipped:';
    final body = AppText.bodyMedium.copyWith(color: AppColors.warningText, height: 1.5);

    return Dialog(
      backgroundColor: AppColors.warningContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ClinicRadii.hero),
        side: const BorderSide(color: ClinicColors.amberBorder, width: 1.5),
      ),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 380, maxHeight: MediaQuery.sizeOf(context).height - 48),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Center(child: IconTile(Icons.person_off_outlined, size: 52, bg: AppColors.warning, fg: AppColors.surface)),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: AppText.titleMedium.copyWith(fontSize: 20, fontWeight: FontWeight.w800, color: ClinicColors.amberDeep)),
            const SizedBox(height: 8),
            Text(who, textAlign: TextAlign.center, style: body),
            if (!one) ...[
              const SizedBox(height: 4),
              for (final t in skipped)
                Text('${t.label} · ${t.name}', textAlign: TextAlign.center, style: body.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
            ],
            Text('When they check in with the token code, they are called right after the current patient.', textAlign: TextAlign.center, style: body),
            const SizedBox(height: 18),
            SizedBox(
              height: 48,
              child: FilledButton(
                autofocus: true, // Enter closes it
                style: FilledButton.styleFrom(backgroundColor: AppColors.warning, foregroundColor: AppColors.surface),
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
