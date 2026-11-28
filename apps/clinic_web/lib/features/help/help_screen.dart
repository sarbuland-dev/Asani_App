import 'package:flutter/material.dart';

import '../../core/widgets/clinic_kit.dart';

/// W-21 / C-16: short guides.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ClinicPage(
      title: 'Help',
      subtitle: 'Short guides for the reception PC.',
      children: [
        _row(
          _guide('Print without the dialog every time', const [
            'Set your thermal or A5 printer as the default printer in Windows.',
            'Right-click the Chrome shortcut on the desktop and open Properties.',
            'At the end of "Target", add a space and --kiosk-printing.',
            'Close all Chrome windows, then open Chrome from this shortcut and log in to Asani.',
            'Now "Arrived & Print" prints straight away. Test it with Reprint on any token.',
          ]),
          _shortcuts(),
        ),
        const SizedBox(height: 18),
        _row(
          _guide('Install as a desktop app', const [
            'Open Asani Clinic in Chrome.',
            'Click the install icon at the right end of the address bar (or ⋮ → Cast, save and share → Install page as app).',
            'Asani opens in its own window with its own icon on the desktop and taskbar.',
          ]),
          _support(),
        ),
      ],
    );
  }

  Widget _row(Widget a, Widget b) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: a), const SizedBox(width: 18), Expanded(child: b)]),
      );

  Widget _guide(String title, List<String> steps) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: ClinicText.cardTitle),
          const SizedBox(height: 14),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: ClinicColors.tint, borderRadius: BorderRadius.circular(8)),
                  child: Text('${i + 1}', style: ClinicText.small.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(steps[i], style: ClinicText.body)),
              ]),
            ),
        ]),
      );

  Widget _shortcuts() {
    const keys = [
      ('Enter token code', '/'),
      ('New walk-in', 'W'),
      ('Next patient for the selected doctor', 'N'),
      ('In check-in: Arrived & print', 'Enter'),
      ('Close a dialog', 'Esc'),
    ];
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Keyboard shortcuts (queue board)', style: ClinicText.cardTitle),
        const SizedBox(height: 8),
        for (final (i, (text, key)) in keys.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: i == keys.length - 1 ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.cream))),
            child: Row(children: [Expanded(child: Text(text, style: ClinicText.body)), Kbd(key)]),
          ),
      ]),
    );
  }

  Widget _support() => Panel(
        color: AppColors.primary,
        borderColor: AppColors.primary,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Need a hand?', style: ClinicText.cardTitle.copyWith(color: AppColors.onPrimary)),
          const SizedBox(height: 10),
          Text(
            'When you contact the Asani team, tell us your clinic name and what happened (a screenshot helps).',
            style: AppText.bodyMedium.copyWith(color: AppColors.onPrimaryMuted, height: 1.6),
          ),
        ]),
      );
}
