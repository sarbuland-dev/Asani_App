import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/links.dart';
import '../../core/theme/app_theme.dart';
import '../../core/web/print.dart';
import '../../core/widgets/desktop.dart';
import '../../core/widgets/qr_view.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// W-19 / C-13: clinic details, print format, QR standee.
class ClinicSettingsScreen extends ConsumerStatefulWidget {
  const ClinicSettingsScreen(this.clinicId, {super.key});
  final String clinicId;

  @override
  ConsumerState<ClinicSettingsScreen> createState() => _ClinicSettingsScreenState();
}

class _ClinicSettingsScreenState extends ConsumerState<ClinicSettingsScreen> {
  final _form = GlobalKey<FormState>();
  TextEditingController? _address, _area, _phone;
  PrintFormat? _format;

  @override
  void dispose() {
    _address?.dispose();
    _area?.dispose();
    _phone?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    await runAction(
      context,
      () => ref.read(repositoryProvider).updateClinicSettings(widget.clinicId, address: _address!.text.trim(), area: _area!.text.trim(), phone: _phone!.text.trim(), printFormat: _format),
      success: 'Settings saved.',
    );
  }

  void _printStandee(ClinicAccount c) {
    final qr = qrSvg(AppLinks.clinic(c.id), size: 340, color: '#0F766E');
    printHtml('''<!doctype html><html><head><meta charset="utf-8"><title>Asani QR</title><style>
@page { size: A4; margin: 0; }
body { margin: 0; font-family: Inter, Arial, sans-serif; color: #0F172A; }
.p { height: 297mm; display: flex; flex-direction: column; align-items: center; justify-content: center; text-align: center;
     background: linear-gradient(135deg, #0F766E, #14B8A6); -webkit-print-color-adjust: exact; print-color-adjust: exact; }
.card { background: #fff; border-radius: 32px; padding: 48px 56px; width: 150mm; }
h1 { font-size: 40px; margin: 0 0 8px; } h2 { font-size: 22px; margin: 0 0 28px; color: #475569; font-weight: 500; }
.brand { color: #0F766E; font-weight: 800; font-size: 34px; margin-top: 24px; } .s { color: #475569; font-size: 18px; }
</style></head><body><div class="p"><div class="card">
<h1>Scan to book your token</h1><h2>${esc(c.clinic.name)} · ${esc(c.clinic.area)}</h2>$qr
<div class="brand">asani</div><div class="s">No waiting in line. Watch the live queue on your phone.</div>
</div></div></body></html>''');
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(clinicProvider(widget.clinicId));
    if (c == null) return const SizedBox.shrink();
    _address ??= TextEditingController(text: c.clinic.address);
    _area ??= TextEditingController(text: c.clinic.area);
    _phone ??= TextEditingController(text: c.clinic.phone);
    _format ??= c.printFormat;

    return PageScaffold(
      title: 'Clinic settings',
      actions: [FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Save'))],
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 3,
          child: Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppCard(
                padding: const EdgeInsets.all(Gap.xl),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Clinic details', style: AppText.titleMedium),
                  const SizedBox(height: Gap.lg),
                  FieldLabel(
                    'Clinic name (changed by Asani)',
                    child: TextFormField(initialValue: c.clinic.name, enabled: false, decoration: const InputDecoration(suffixIcon: Icon(Icons.lock_outline_rounded))),
                  ),
                  FieldLabel('Address', child: TextFormField(controller: _address, validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null)),
                  Row(children: [
                    Expanded(child: FieldLabel('Area', child: TextFormField(controller: _area, validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null))),
                    const SizedBox(width: Gap.md),
                    Expanded(child: FieldLabel('City', child: TextFormField(initialValue: c.clinic.city, enabled: false))),
                  ]),
                  FieldLabel(
                    'Phone (shown to patients)',
                    child: TextFormField(controller: _phone, validator: (v) => (v ?? '').replaceAll(RegExp(r'[^0-9]'), '').length < 9 ? 'Enter a valid phone' : null),
                  ),
                ]),
              ),
              const SizedBox(height: Gap.lg),
              AppCard(
                padding: const EdgeInsets.all(Gap.xl),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Clinic form printing', style: AppText.titleMedium),
                  Text('Printed on Arrived & Print, walk-ins and Reprint.', style: AppText.bodyMedium),
                  const SizedBox(height: Gap.lg),
                  RadioGroup<PrintFormat>(
                    groupValue: _format,
                    onChanged: (v) => setState(() => _format = v),
                    child: Column(children: [
                      for (final f in PrintFormat.values)
                        RadioListTile<PrintFormat>(
                          value: f,
                          contentPadding: EdgeInsets.zero,
                          title: Text(f.label, style: AppText.labelLarge),
                          subtitle: Text(switch (f) {
                            PrintFormat.thermal80 => 'Small receipt printer, 80 mm paper roll.',
                            PrintFormat.a5 => 'Half of an A4 page, with a large Rx area.',
                            PrintFormat.none => 'Nothing is printed.',
                          }, style: AppText.labelSmall),
                        ),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(width: Gap.xl),
        Expanded(
          flex: 2,
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GradientHeader(
                radius: 0,
                padding: const EdgeInsets.all(Gap.xl),
                child: Column(children: [
                  Text('Scan to book your token', style: AppText.titleLarge.copyWith(color: AppColors.onPrimary)),
                  Text(c.clinic.name, style: AppText.bodyMedium.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.9))),
                  const SizedBox(height: Gap.lg),
                  Container(
                    padding: const EdgeInsets.all(Gap.lg),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.card)),
                    child: QrView(data: AppLinks.clinic(c.id), size: 180, color: AppColors.primary),
                  ),
                  const SizedBox(height: Gap.md),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const AsaniMark(size: 28, color: AppColors.onPrimary, plusColor: AppColors.primaryContainer),
                    Text('asani', style: AppText.titleLarge.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w800)),
                  ]),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(Gap.xl),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Clinic QR standee', style: AppText.titleMedium),
                  Text('Print it on A4 and keep it at reception, so patients book with the Asani app.', style: AppText.bodyMedium),
                  const SizedBox(height: Gap.lg),
                  FilledButton.icon(onPressed: () => _printStandee(c), icon: const Icon(Icons.print_rounded), label: const Text('Print poster (A4)')),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
