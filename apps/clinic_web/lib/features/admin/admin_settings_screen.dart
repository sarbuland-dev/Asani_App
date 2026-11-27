import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'admin_kit.dart';

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

  String? _range(String? v, int max) {
    final n = int.tryParse(v ?? '');
    return n == null || n < 0 || n > max ? '0–$max' : null;
  }

  Widget _num(String label, TextEditingController c, {String? suffix, required int max}) => Expanded(
        child: LabeledField(
          label,
          child: TextFormField(
            controller: c,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(suffixText: suffix),
            validator: (v) => _range(v, max),
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

  /// One plan with its editable default price; Basic is the dark card.
  Widget _planCard(Plan p) {
    final dark = p == Plan.basic;
    final fg = dark ? AppColors.onPrimary : AppColors.textPrimary;
    final soft = dark ? AppColors.onPrimaryMuted : AppColors.textSecondary;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: dark ? null : AppColors.surface,
          gradient: dark ? ClinicColors.heroGradient : null,
          borderRadius: BorderRadius.circular(ClinicRadii.card),
          border: Border.all(color: dark ? AppColors.primary : AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(p.label, style: AppText.titleSmall.copyWith(color: fg))),
            if (dark) const CChip.tint('Most clinics'),
          ]),
          const SizedBox(height: 6),
          Text(p == Plan.pilot ? 'during the pilot, per month' : 'per month', style: ClinicText.small.copyWith(color: soft)),
          const SizedBox(height: 10),
          TextFormField(
            controller: _prices[p],
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: ClinicText.big(24),
            decoration: const InputDecoration(prefixText: 'Rs  '),
            validator: (v) => _range(v, 100000),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    return Form(
      key: _form,
      child: AdminPage(
        title: 'Settings',
        subtitle: 'Plans, prices and billing rules',
        search: false,
        actions: [FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check_rounded, size: 18), label: const Text('Save settings'))],
        children: [
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Plans and default prices', style: ClinicText.cardTitle),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final (i, p) in Plan.values.indexed) ...[if (i > 0) const SizedBox(width: 14), _planCard(p)],
              ]),
              const SizedBox(height: 10),
              Text('Prices are still to be confirmed (Q-W06).', style: ClinicText.small),
            ]),
          ),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Defaults for new clinics', style: ClinicText.cardTitle),
                  const SizedBox(height: 14),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _num('Pilot length', _pilot, suffix: 'days', max: 365),
                    const SizedBox(width: 14),
                    _num('Billing day', _billing, suffix: 'of month', max: 28),
                  ]),
                  const SizedBox(height: 14),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _num('Invoice due after', _due, suffix: 'days', max: 60),
                    const SizedBox(width: 14),
                    _num('Grace before reminder', _grace, suffix: 'days', max: 60),
                  ]),
                  const SizedBox(height: 14),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _num('Suspend after', _suspend, suffix: 'days', max: 90),
                    const SizedBox(width: 14),
                    const Spacer(),
                  ]),
                  const SizedBox(height: 14),
                  const NoteBox('7 and 15 days are still draft values (Q-W05).', icon: Icons.warning_amber_rounded),
                ]),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Panel(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('Payment instructions shown to clinics', style: ClinicText.cardTitle),
                    const SizedBox(height: 4),
                    Text("Shown on each clinic's Billing page.", style: ClinicText.small),
                    const SizedBox(height: 12),
                    TextFormField(controller: _instructions, minLines: 5, maxLines: 8, validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
                  ]),
                ),
                const SizedBox(height: 16),
                Panel(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('Your admin login', style: ClinicText.cardTitle),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(color: ClinicColors.quiet, borderRadius: BorderRadius.circular(ClinicRadii.control), border: Border.all(color: AppColors.border)),
                      child: Row(children: [
                        const Icon(Icons.mail_outline_rounded, size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text(user?.email ?? '', overflow: TextOverflow.ellipsis, style: ClinicText.body)),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    Text('Only Asani team accounts have the Super admin role.', style: ClinicText.small),
                  ]),
                ),
              ]),
            ),
          ]),
        ],
      ),
    );
  }
}
