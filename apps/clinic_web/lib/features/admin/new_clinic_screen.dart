import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/clinic_kit.dart';
import '../../data/clinic_repository.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'admin_kit.dart';

/// A-13 / A-04: New clinic wizard (clinic → clinic login → plan → review),
/// with a live preview beside the form.
class NewClinicScreen extends ConsumerStatefulWidget {
  const NewClinicScreen({super.key});

  @override
  ConsumerState<NewClinicScreen> createState() => _NewClinicScreenState();
}

class _NewClinicScreenState extends ConsumerState<NewClinicScreen> {
  final _d = NewClinicDraft();
  final _forms = [GlobalKey<FormState>(), GlobalKey<FormState>(), GlobalKey<FormState>()];
  int _step = 0;
  bool _busy = false;
  late final _fee = TextEditingController(text: '${ref.read(adminSettingsProvider).prices[Plan.basic]}');
  late final _pilot = TextEditingController(text: '${ref.read(adminSettingsProvider).pilotDays}');

  @override
  void dispose() {
    _fee.dispose();
    _pilot.dispose();
    super.dispose();
  }

  /// A-04 (v0.4): doctors are not added here; the clinic adds them after its first login (D-19).
  static const _titles = ['Clinic', 'Clinic login', 'Plan', 'Review'];

  bool _validate() {
    switch (_step) {
      case 0:
        return _forms[0].currentState?.validate() ?? false;
      case 1:
        return _forms[1].currentState?.validate() ?? false;
      case 2:
        if (!(_forms[2].currentState?.validate() ?? false)) return false;
        _d.monthlyFee = int.parse(_fee.text);
        _d.pilotDays = int.parse(_pilot.text);
        return true;
    }
    return true;
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    ClinicAccount? created;
    final ok = await runAction(context, () async => created = await ref.read(repositoryProvider).createClinic(_d));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok && created != null) {
      showSnack(context, '${created!.clinic.name} created. Invite sent to ${created!.email}.');
      context.go('/admin/clinics/${created!.id}');
    }
  }

  String? _req(String? v) => (v ?? '').trim().isEmpty ? 'Required' : null;

  /// A field that also refreshes the preview card.
  Widget _field(String label, {required ValueChanged<String> set, required FormFieldValidator<String> validator, String? hint, String? prefix, String? help, String? initial, TextInputType? keyboard}) =>
      LabeledField(
        label,
        help: help,
        child: TextFormField(
          initialValue: initial,
          keyboardType: keyboard,
          decoration: InputDecoration(hintText: hint, prefixText: prefix),
          validator: validator,
          onChanged: (v) => setState(() => set(v)),
        ),
      );

  Widget _two(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 14), Expanded(child: b)]);

  @override
  Widget build(BuildContext context) {
    const hints = [
      "Details patients see in the app. The name can only be changed by the Super admin later.",
      "The clinic's email becomes the clinic's only login; the receptionist uses it too. The manager or senior doctor gets an email to set the password.",
      'The clinic starts free in the pilot, then moves to the plan below.',
      'Check everything before the clinic is created.',
    ];
    final last = _step == _titles.length - 1;

    return AdminPage(
      title: 'Clinics › New clinic',
      subtitle: 'Step ${_step + 1} of ${_titles.length} · ${_titles[_step]}',
      search: false,
      children: [
        _stepper(),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Panel(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(_titles[_step], style: AppText.titleMedium.copyWith(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(hints[_step], style: AppText.bodyMedium.copyWith(fontSize: 13)),
                const SizedBox(height: 20),
                // All steps stay built, so what was typed is kept.
                IndexedStack(index: _step, children: [_clinicStep(), _loginStep(), _planStep(), _review()]),
                const SizedBox(height: 20),
                const Divider(color: AppColors.cream),
                const SizedBox(height: 16),
                Row(children: [
                  OutlinedButton(
                    onPressed: _step == 0 ? () => context.go('/admin/clinics') : () => setState(() => _step--),
                    child: Text(_step == 0 ? 'Cancel' : 'Back'),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28)),
                    onPressed: last
                        ? (_busy ? null : _create)
                        : () {
                            if (_validate()) setState(() => _step++);
                          },
                    child: last
                        ? BusyLabel(busy: _busy, busyText: 'Creating…', color: AppColors.textSecondary, child: const Text('Create clinic'))
                        : Text('Next: ${_titles[_step + 1]} ›'),
                  ),
                ]),
              ]),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(width: 340, child: _preview()),
        ]),
      ],
    );
  }

  Widget _stepper() => Panel(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        child: Row(children: [
          for (var i = 0; i < _titles.length; i++)
            Expanded(
              flex: i == _titles.length - 1 ? 0 : 1,
              child: Row(mainAxisSize: i == _titles.length - 1 ? MainAxisSize.min : MainAxisSize.max, children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: i <= _step ? AppColors.primary : ClinicColors.creamDeep, shape: BoxShape.circle),
                  child: i < _step
                      ? const Icon(Icons.check_rounded, size: 18, color: AppColors.onPrimary)
                      : Text('${i + 1}', style: AppText.labelMedium.copyWith(fontSize: 13, color: i == _step ? AppColors.onPrimary : AppColors.textSecondary)),
                ),
                const SizedBox(width: 10),
                Text(_titles[i], style: AppText.labelMedium.copyWith(fontWeight: FontWeight.w700, color: i <= _step ? AppColors.textPrimary : AppColors.textSecondary)),
                if (i < _titles.length - 1)
                  const Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: SizedBox(height: 2, child: ColoredBox(color: AppColors.border)))),
              ]),
            ),
        ]),
      );

  Widget _preview() {
    String or(String v, String other) => v.trim().isEmpty ? other : v.trim();
    Text caps(String t) => Text(t, style: ClinicText.caps);
    return Panel(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HeroBlock(
          radius: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('NEW CLINIC', style: ClinicText.caps.copyWith(color: AppColors.primarySoft)),
            Text(or(_d.name, 'Clinic name'), style: AppText.titleMedium.copyWith(fontSize: 20, color: AppColors.onPrimary)),
            Text('${or(_d.area, 'Area')}, ${or(_d.city, 'city')}', style: AppText.bodyMedium.copyWith(fontSize: 13, color: AppColors.onPrimaryMuted)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            caps('CLINIC'),
            InfoLine('Address', or(_d.address, 'filling in…')),
            InfoLine('Location', _d.location == null ? 'required' : formatLatLng(_d.location!)),
            InfoLine('Phone', or(_d.phone, '—')),
            InfoLine('Print', _d.printFormat.label),
            const SizedBox(height: 8),
            caps('LOGIN'),
            InfoLine('Email', or(_d.email, 'next step')),
            InfoLine('Manager', or(_d.ownerName, '—')),
            const SizedBox(height: 8),
            caps('PLAN'),
            InfoLine('Plan', _step < 2 ? 'later step' : 'Pilot ${_pilot.text} days, then ${_d.planAfterPilot.label}'),
            if (_step >= 2) InfoLine('Monthly fee', 'Rs ${_fee.text}'),
          ]),
        ),
      ]),
    );
  }

  Widget _clinicStep() => Form(
        key: _forms[0],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _field('Clinic name', set: (v) => _d.name = v, validator: _req),
          const SizedBox(height: 14),
          _two(
            _field('City', initial: _d.city, set: (v) => _d.city = v, validator: _req),
            _field('Area', hint: 'Johar Town', set: (v) => _d.area = v, validator: _req),
          ),
          const SizedBox(height: 14),
          _two(
            _field('Address', set: (v) => _d.address = v, validator: _req),
            _field('Clinic phone', set: (v) => _d.phone = v, validator: (v) => (v ?? '').replaceAll(RegExp(r'[^0-9]'), '').length < 9 ? 'Enter a valid phone' : null),
          ),
          const SizedBox(height: 14),
          // D-31 / BW-12: required.
          _field(
            'Location (required)',
            hint: '31.4697, 74.2728',
            help: 'Paste a Google Maps link or type "lat, lng". Used for Directions and "nearest first".',
            set: (v) => _d.location = parseLatLng(v),
            validator: (v) {
              final p = parseLatLng(v ?? '');
              if (p == null) return 'Paste a Google Maps link or type "lat, lng"';
              if (!inPakistan(p)) return 'This location is not in Pakistan. Check the numbers.';
              return null;
            },
          ),
          const SizedBox(height: 14),
          LabeledField(
            'Print format',
            child: Align(
              alignment: Alignment.centerLeft,
              child: AdminTabs<PrintFormat>(
                values: PrintFormat.values,
                selected: _d.printFormat,
                label: (f) => f == PrintFormat.none ? 'None' : f.label,
                onChanged: (f) => setState(() => _d.printFormat = f),
              ),
            ),
          ),
        ]),
      );

  Widget _loginStep() => Form(
        key: _forms[1],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _field('Manager / senior doctor name', set: (v) => _d.ownerName = v, validator: _req),
          const SizedBox(height: 14),
          _field(
            'Manager mobile',
            prefix: '+92  ',
            hint: '300 1234567',
            keyboard: TextInputType.phone,
            set: (v) => _d.ownerPhone = PhoneUtils.isValidLocal(v) ? PhoneUtils.toE164(v) : v,
            validator: (v) => PhoneUtils.isValidLocal(v ?? '') ? null : 'Enter a valid mobile number',
          ),
          const SizedBox(height: 14),
          _field(
            'Clinic email',
            keyboard: TextInputType.emailAddress,
            set: (v) => _d.email = v,
            validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email',
          ),
        ]),
      );

  Widget _planStep() => Form(
        key: _forms[2],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _two(
            LabeledField(
              'Pilot length',
              child: TextFormField(
                controller: _pilot,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(suffixText: 'days'),
                validator: (v) => (int.tryParse(v ?? '') ?? -1) < 0 ? 'Enter days' : null,
                onChanged: (_) => setState(() {}),
              ),
            ),
            LabeledField(
              'Billing day',
              child: DropdownButtonFormField<int>(
                initialValue: _d.billingDay,
                items: [for (var i = 1; i <= 28; i++) DropdownMenuItem(value: i, child: Text('$i of each month'))],
                onChanged: (v) => _d.billingDay = v ?? 1,
              ),
            ),
          ),
          const SizedBox(height: 14),
          LabeledField(
            'Plan after pilot',
            child: Wrap(spacing: 8, children: [
              for (final p in const [Plan.basic, Plan.premium])
                FilterPill(
                  p.label,
                  selected: _d.planAfterPilot == p,
                  onTap: () => setState(() {
                    _d.planAfterPilot = p;
                    _fee.text = '${ref.read(adminSettingsProvider).prices[p]}';
                  }),
                ),
            ]),
          ),
          const SizedBox(height: 14),
          LabeledField(
            'Monthly fee',
            child: TextFormField(
              controller: _fee,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(prefixText: 'Rs  '),
              validator: (v) => int.tryParse(v ?? '') == null ? 'Enter an amount' : null,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
      );

  Widget _review() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InfoLine('Clinic', '${_d.name}, ${_d.area}, ${_d.city}'),
        InfoLine('Address', _d.address),
        InfoLine('Map location', _d.location == null ? '—' : formatLatLng(_d.location!)),
        InfoLine('Phone', _d.phone),
        InfoLine('Print format', _d.printFormat.label),
        InfoLine('Clinic login', '${_d.email} (manager: ${_d.ownerName})'),
        InfoLine('Manager mobile', Fmt.phone(_d.ownerPhone)),
        InfoLine('Plan', 'Pilot ${_d.pilotDays} days, then ${_d.planAfterPilot.label} at ${WebFmt.money(_d.monthlyFee)}/month (billing day ${_d.billingDay})'),
        const SizedBox(height: 14),
        const NoteBox.tint('On Create, the clinic starts in Pilot and the invite goes to the clinic email. After the first login, the clinic adds its own doctors.',
            icon: Icons.mail_outline_rounded),
      ]);
}
