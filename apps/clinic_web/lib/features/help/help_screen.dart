import 'package:flutter/material.dart';

import '../../core/widgets/desktop.dart';

/// W-21 / C-16: short guides.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Help',
      subtitle: 'Quick guides for the reception PC.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _guide(Icons.print_rounded, 'Print without the dialog (kiosk printing)', const [
          'Set your thermal or A5 printer as the default printer in Windows.',
          'Right-click the Chrome shortcut on the desktop → Properties.',
          'At the end of "Target", add a space and: --kiosk-printing',
          'Close all Chrome windows, then open Chrome from this shortcut.',
          'Now "Arrived & Print" prints straight away, without the print dialog.',
        ]),
        _guide(Icons.install_desktop_rounded, 'Install Asani as a desktop app', const [
          'Open Asani Clinic in Chrome.',
          'Click the install icon at the right end of the address bar (or ⋮ → Cast, save and share → Install).',
          'Asani opens in its own window with its own icon on the desktop and taskbar.',
        ]),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const IconBox(icon: Icons.keyboard_rounded),
              const SizedBox(width: Gap.md),
              Text('Keyboard shortcuts (Queue Board)', style: AppText.titleMedium),
            ]),
            const SizedBox(height: Gap.lg),
            for (final (k, d) in const [('/', 'Check in by token code'), ('W', 'New walk-in token'), ('N', 'Next patient for the selected doctor'), ('Esc', 'Close a dialog'), ('Enter', 'In check-in: Slip matches · Arrived & Print')])
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: Row(children: [
                  Container(
                    width: 64,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.muted, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
                    child: Text(k, style: AppText.labelMedium),
                  ),
                  const SizedBox(width: Gap.lg),
                  Text(d, style: AppText.bodyLarge),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: Gap.lg),
        _guide(Icons.support_agent_rounded, 'Contact Asani support', const [
          'Call or WhatsApp the Asani team from 10 AM to 8 PM, Monday to Saturday.',
          'Tell us your clinic name and what happened (a screenshot helps).',
        ]),
      ]),
    );
  }

  Widget _guide(IconData icon, String title, List<String> steps) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.lg),
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [IconBox(icon: icon), const SizedBox(width: Gap.md), Text(title, style: AppText.titleMedium)]),
            const SizedBox(height: Gap.lg),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppColors.primaryContainer, shape: BoxShape.circle),
                    child: Text('${i + 1}', style: AppText.labelSmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(child: Text(steps[i], style: AppText.bodyLarge)),
                ]),
              ),
          ]),
        ),
      );
}
