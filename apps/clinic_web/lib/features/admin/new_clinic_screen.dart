import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/desktop.dart';
import '../../data/clinic_repository.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../doctors/doctor_form_dialog.dart';

/// A-13 / A-04: New clinic wizard (clinic → doctors → admin → plan → review).
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

  static const _titles = ['Clinic', 'Doctors', 'Clinic admin', 'Plan', 'Review'];

  bool _validate() {
    switch (_step) {
      case 0:
        return _forms[0].currentState?.validate() ?? false;
      case 1:
        if (_d.doctors.isEmpty) {
          showSnack(context, 'Add at least one doctor.');
          return false;
        }
        return true;
      case 2:
        return _forms[1].currentState?.validate() ?? false;
      case 3:
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

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'New clinic',
      subtitle: 'Step ${_step + 1} of 5 · ${_titles[_step]}',
      leading: HeaderBackButton(dark: true, onPressed: () => context.go('/admin/clinics')),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 220,
          child: Column(children: [
            for (var i = 0; i < _titles.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: Row(children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i < _step ? AppColors.primary : (i == _step ? AppColors.primaryContainer : AppColors.muted),
                      shape: BoxShape.circle,
                    ),
                    child: i < _step
                        ? const Icon(Icons.check_rounded, size: 18, color: AppColors.onPrimary)
                        : Text('${i + 1}', style: AppText.labelMedium.copyWith(color: i == _step ? AppColors.primary : AppColors.textSecondary)),
                  ),
                  const SizedBox(width: Gap.md),
                  Text(_titles[i], style: AppText.labelLarge.copyWith(color: i == _step ? AppColors.primary : AppColors.textSecondary)),
                ]),
              ),
          ]),
        ),
        const SizedBox(width: Gap.xl),
        Expanded(
          child: AppCard(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              IndexedStack(index: _step, children: [_clinicStep(), _doctorsStep(), _adminStep(), _planStep(), _review()]),
              const SizedBox(height: Gap.xl),
              Row(children: [
                if (_step > 0) TextButton.icon(onPressed: () => setState(() => _step--), icon: const Icon(Icons.arrow_back_rounded), label: const Text('Back')),
                const Spacer(),
                if (_step < 4)
                  FilledButton.icon(
                    onPressed: () {
                      if (_validate()) setState(() => _step++);
                    },
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Continue'),
                  )
                else
                  FilledButton.icon(onPressed: _busy ? null : _create, icon: const Icon(Icons.check_rounded), label: const Text('Create clinic')),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _clinicStep() => Form(
        key: _forms[0],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FieldLabel('Clinic name', child: TextFormField(onChanged: (v) => _d.name = v, validator: _req, textCapitalization: TextCapitalization.words)),
          Row(children: [
            Expanded(child: FieldLabel('Area', child: TextFormField(onChanged: (v) => _d.area = v, validator: _req, decoration: const InputDecoration(hintText: 'Johar Town')))),
            const SizedBox(width: Gap.md),
            Expanded(child: FieldLabel('City', child: TextFormField(initialValue: _d.city, onChanged: (v) => _d.city = v, validator: _req))),
          ]),
          FieldLabel('Address', child: TextFormField(onChanged: (v) => _d.address = v, validator: _req)),
          FieldLabel(
            'Clinic phone',
            child: TextFormField(onChanged: (v) => _d.phone = v, validator: (v) => (v ?? '').replaceAll(RegExp(r'[^0-9]'), '').length < 9 ? 'Enter a valid phone' : null),
          ),
          FieldLabel(
            'Print format',
            child: StatefulBuilder(
              builder: (context, setState) => Wrap(spacing: Gap.sm, children: [
                for (final f in PrintFormat.values) ChoiceChip(label: Text(f.label), selected: _d.printFormat == f, onSelected: (_) => setState(() => _d.printFormat = f)),
              ]),
            ),
          ),
          Text('Map location can be added later from the clinic settings.', style: AppText.labelSmall),
        ]),
      );

  Widget _doctorsStep() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Letters A, B, C… are assigned in this order when the clinic is created.', style: AppText.bodyMedium),
        const SizedBox(height: Gap.lg),
        for (var i = 0; i < _d.doctors.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
              child: Row(children: [
                LetterBadge(String.fromCharCode(65 + i)),
                const SizedBox(width: Gap.md),
                Expanded(child: TwoLine(_d.doctors[i].name, '${_d.doctors[i].speciality} · ${_d.doctors[i].avgConsultMinutes} min · max ${_d.doctors[i].maxTokensPerDay}')),
                IconButton(
                  tooltip: 'Edit',
                  onPressed: () async {
                    final d = await showDoctorForm(context, initial: _d.doctors[i], clinicId: 'new');
                    if (d != null) setState(() => _d.doctors[i] = d);
                  },
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(tooltip: 'Remove', onPressed: () => setState(() => _d.doctors.removeAt(i)), icon: const Icon(Icons.delete_outline_rounded)),
              ]),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () async {
              final d = await showDoctorForm(context, clinicId: 'new');
              if (d != null) setState(() => _d.doctors.add(d));
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add doctor'),
          ),
        ),
      ]);

  Widget _adminStep() => Form(
        key: _forms[1],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text("The clinic's email becomes the Clinic Admin login. They get an email to set their own password.", style: AppText.bodyMedium),
          const SizedBox(height: Gap.lg),
          FieldLabel('Owner name', child: TextFormField(onChanged: (v) => _d.ownerName = v, validator: _req, textCapitalization: TextCapitalization.words)),
          FieldLabel(
            'Owner mobile',
            child: TextFormField(
              onChanged: (v) => _d.ownerPhone = PhoneUtils.isValidLocal(v) ? PhoneUtils.toE164(v) : v,
              decoration: const InputDecoration(prefixText: '+92  ', hintText: '300 1234567'),
              validator: (v) => PhoneUtils.isValidLocal(v ?? '') ? null : 'Enter a valid mobile number',
            ),
          ),
          FieldLabel(
            'Clinic email',
            child: TextFormField(
              onChanged: (v) => _d.email = v,
              keyboardType: TextInputType.emailAddress,
              validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email',
            ),
          ),
        ]),
      );

  Widget _planStep() => Form(
        key: _forms[2],
        child: StatefulBuilder(
          builder: (context, setState) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: FieldLabel(
                  'Pilot length',
                  child: TextFormField(
                    controller: _pilot,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(suffixText: 'days'),
                    validator: (v) => (int.tryParse(v ?? '') ?? -1) < 0 ? 'Enter days' : null,
                  ),
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: FieldLabel(
                  'Billing day',
                  child: DropdownButtonFormField<int>(
                    initialValue: _d.billingDay,
                    items: [for (var i = 1; i <= 28; i++) DropdownMenuItem(value: i, child: Text('$i of each month'))],
                    onChanged: (v) => _d.billingDay = v ?? 1,
                  ),
                ),
              ),
            ]),
            FieldLabel(
              'Plan after pilot',
              child: Wrap(spacing: Gap.sm, children: [
                for (final p in const [Plan.basic, Plan.premium])
                  ChoiceChip(
                    label: Text(p.label),
                    selected: _d.planAfterPilot == p,
                    onSelected: (_) => setState(() {
                      _d.planAfterPilot = p;
                      _fee.text = '${ref.read(adminSettingsProvider).prices[p]}';
                    }),
                  ),
              ]),
            ),
            FieldLabel(
              'Monthly fee',
              child: TextFormField(
                controller: _fee,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(prefixText: 'Rs  '),
                validator: (v) => int.tryParse(v ?? '') == null ? 'Enter an amount' : null,
              ),
            ),
          ]),
        ),
      );

  Widget _review() {
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 160, child: Text(k, style: AppText.bodyMedium)), Expanded(child: Text(v, style: AppText.labelMedium))]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row('Clinic', '${_d.name}, ${_d.area}, ${_d.city}'),
      row('Address', _d.address),
      row('Phone', _d.phone),
      row('Print format', _d.printFormat.label),
      row('Doctors', [for (var i = 0; i < _d.doctors.length; i++) '${String.fromCharCode(65 + i)}: ${_d.doctors[i].name}'].join('\n')),
      row('Clinic admin', '${_d.ownerName} · ${_d.email}'),
      row('Owner mobile', Fmt.phone(_d.ownerPhone)),
      row('Plan', 'Pilot ${_d.pilotDays} days, then ${_d.planAfterPilot.label} at ${WebFmt.money(_d.monthlyFee)}/month (billing day ${_d.billingDay})'),
      const SizedBox(height: Gap.md),
      const Banner2(text: 'On Create, the clinic starts in Pilot and the invite email goes to the clinic email.', icon: Icons.mail_outline_rounded, fg: AppColors.info, bg: AppColors.infoContainer),
    ]);
  }
}
