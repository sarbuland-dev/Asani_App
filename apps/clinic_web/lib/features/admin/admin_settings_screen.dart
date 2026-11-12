import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/desktop.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// A-17 / A-08: plans, prices, billing and grace rules, payment instructions.
class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  ConsumerState<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends ConsumerState<AdminSettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final AdminSettings _s = ref.read(adminSettingsProvider);
  late final _prices = {for (final p in Plan.values) p: TextEditingController(text: '${_s.prices[p] ?? 0}')};
  late final _pilot = TextEditingController(text: '${_s.pilotDays}');
  late final _billing = TextEditingController(text: '${_s.billingDay}');
  late final _due = TextEditingController(text: '${_s.dueDays}');
  late final _grace = TextEditingController(text: '${_s.graceDays}');
  late final _suspend = TextEditingController(text: '${_s.suspendDays}');
  late final _instructions = TextEditingController(text: _s.paymentInstructions);

  @override
  void dispose() {
    for (final c in [..._prices.values, _pilot, _billing, _due, _grace, _suspend, _instructions]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _num(String label, TextEditingController c, {String? suffix, String? prefix, int max = 100000}) => Expanded(
        child: FieldLabel(
          label,
          child: TextFormField(
            controller: c,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(suffixText: suffix, prefixText: prefix),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              return n == null || n < 0 || n > max ? '0–$max' : null;
            },
          ),
        ),
      );

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    int n(TextEditingController c) => int.parse(c.text);
    if (n(_suspend) <= n(_grace)) {
      showSnack(context, 'Suspension must come after the reminder.');
      return;
    }
    await runAction(
      context,
      () => ref.read(repositoryProvider).saveSettings(_s.copyWith(
            prices: {for (final e in _prices.entries) e.key: n(e.value)},
            pilotDays: n(_pilot),
            billingDay: n(_billing).clamp(1, 28),
            dueDays: n(_due),
            graceDays: n(_grace),
            suspendDays: n(_suspend),
            paymentInstructions: _instructions.text.trim(),
          )),
      success: 'Settings saved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Admin settings',
      subtitle: 'Defaults for new clinics and the defaulter timeline.',
      actions: [FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Save'))],
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppCard(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Plans & default prices (per month)', style: AppText.titleMedium),
              const SizedBox(height: Gap.lg),
              Row(children: [
                for (final p in Plan.values) ...[_num(p.label, _prices[p]!, prefix: 'Rs  '), if (p != Plan.premium) const SizedBox(width: Gap.md)],
              ]),
              Text('Prices are still to be confirmed (Q-W06).', style: AppText.labelSmall),
            ]),
          ),
          const SizedBox(height: Gap.lg),
          AppCard(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Billing & defaulters', style: AppText.titleMedium),
              const SizedBox(height: Gap.lg),
              Row(children: [
                _num('Default pilot', _pilot, suffix: 'days', max: 365),
                const SizedBox(width: Gap.md),
                _num('Default billing day', _billing, suffix: 'of month', max: 28),
                const SizedBox(width: Gap.md),
                _num('Invoice due after', _due, suffix: 'days', max: 60),
              ]),
              Row(children: [
                _num('Reminder email after due', _grace, suffix: 'days', max: 60),
                const SizedBox(width: Gap.md),
                _num('Suspend after due', _suspend, suffix: 'days', max: 90),
                const Spacer(),
              ]),
              Text('7 and 15 days are the draft values (Q-W05).', style: AppText.labelSmall),
            ]),
          ),
          const SizedBox(height: Gap.lg),
          AppCard(
            padding: const EdgeInsets.all(Gap.xl),
            child: FieldLabel(
              'Payment instructions shown to clinics (Billing page)',
              child: TextFormField(controller: _instructions, maxLines: 5, validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
            ),
          ),
        ]),
      ),
    );
  }
}
