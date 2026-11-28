import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/clinic_kit.dart';
import '../../core/widgets/pin_gate.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../account/change_password_screen.dart';
import 'export_card.dart';

/// W-18/19 / C-13: clinic details, print format, password, manager PIN and
/// export. No QR standee (D-51).
class ClinicSettingsScreen extends ConsumerStatefulWidget {
  const ClinicSettingsScreen(this.clinicId, {super.key});
  final String clinicId;

  @override
  ConsumerState<ClinicSettingsScreen> createState() => _ClinicSettingsScreenState();
}

class _ClinicSettingsScreenState extends ConsumerState<ClinicSettingsScreen> {
  final _form = GlobalKey<FormState>();
  TextEditingController? _address, _area, _phone, _location;
  PrintFormat? _format;

  @override
  void dispose() {
    _address?.dispose();
    _area?.dispose();
    _phone?.dispose();
    _location?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    await runAction(
      context,
      () => ref.read(repositoryProvider).updateClinicSettings(widget.clinicId,
          address: _address!.text.trim(), area: _area!.text.trim(), phone: _phone!.text.trim(), printFormat: _format, location: parseLatLng(_location!.text)),
      success: 'Settings saved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(clinicProvider(widget.clinicId));
    if (c == null) return const SizedBox.shrink();
    _address ??= TextEditingController(text: c.clinic.address);
    _area ??= TextEditingController(text: c.clinic.area);
    _phone ??= TextEditingController(text: c.clinic.phone);
    _location ??= TextEditingController(text: c.clinic.location == null ? '' : formatLatLng(c.clinic.location!));
    _format ??= c.printFormat;
    final canExport = ref.watch(currentUserProvider)?.role.canRunQueue ?? false;

    return ClinicPage(title: 'Settings', children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _details(c),
            const SizedBox(height: 18),
            const ChangePasswordCard(),
          ]),
        ),
        const SizedBox(width: 18),
        SizedBox(
          width: 320,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ManagerPinCard(clinicId: widget.clinicId), // D-41
            if (canExport) ...[const SizedBox(height: 18), ExportCard(clinicId: widget.clinicId)],
          ]),
        ),
      ]),
    ]);
  }

  Widget _details(ClinicAccount c) {
    Widget field(String label, TextEditingController controller, String? Function(String?) validator, {String? help}) => Expanded(
          child: LabeledField(label, help: help, child: TextFormField(controller: controller, validator: validator)),
        );
    String? required(String? v) => (v ?? '').trim().isEmpty ? 'Required' : null;

    return Panel(
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Clinic details', style: ClinicText.cardTitle),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: LabeledField(
                'Clinic name',
                help: 'Changed by Asani support',
                child: TextFormField(
                  initialValue: c.clinic.name,
                  enabled: false,
                  style: AppText.bodyLarge.copyWith(color: AppColors.textSecondary),
                  decoration: const InputDecoration(fillColor: ClinicColors.quiet),
                ),
              ),
            ),
            const SizedBox(width: 14),
            field('Phone (shown to patients)', _phone!, (v) => (v ?? '').replaceAll(RegExp(r'[^0-9]'), '').length < 9 ? 'Enter a valid phone' : null),
          ]),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            field('Address', _address!, required),
            const SizedBox(width: 14),
            field('Area', _area!, required, help: 'City: ${c.clinic.city} (changed by Asani support)'),
          ]),
          const SizedBox(height: 14),
          // D-31 / BW-12: required, for Directions and "nearest first" in the app.
          LabeledField(
            'Map location',
            required: true,
            help: 'Paste a Google Maps link or type "lat, lng". Used for Directions and "nearest first".',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const _DrawnMap(),
              const SizedBox(height: 10),
              TextFormField(
                controller: _location,
                decoration: const InputDecoration(hintText: '31.4697, 74.2728', prefixIcon: Icon(Icons.place_outlined, size: 20)),
                validator: (v) {
                  final p = parseLatLng(v ?? '');
                  if (p == null) return 'Paste a Google Maps link or type "lat, lng"';
                  if (!inPakistan(p)) return 'This location is not in Pakistan. Check the numbers.';
                  return null;
                },
              ),
            ]),
          ),
          const SizedBox(height: 14),
          LabeledField(
            'Print format',
            help: switch (_format!) {
              PrintFormat.thermal80 => 'Small receipt printer, 80 mm paper roll. Printed on Arrived & Print, walk-ins and Reprint.',
              PrintFormat.a5 => 'Half of an A4 page, with a large Rx area. Printed on Arrived & Print, walk-ins and Reprint.',
              PrintFormat.none => 'Nothing is printed.',
            },
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedPill<PrintFormat>(
                values: PrintFormat.values,
                selected: _format!,
                label: (f) => f == PrintFormat.none ? 'None' : f.label,
                onChanged: (f) => setState(() => _format = f),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            // D-68: no changes while suspended.
            child: FilledButton(onPressed: c.status.acceptsBookings ? _save : null, child: const Text('Save changes')),
          ),
        ]),
      ),
    );
  }
}

/// Decoration only: a drawn map tile with a pin (D-43: no map library).
class _DrawnMap extends StatelessWidget {
  const _DrawnMap();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          height: 110,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: ClinicColors.creamDeep, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
          child: Stack(alignment: Alignment.center, children: [
            const Positioned(left: 0, right: 0, top: 62, height: 12, child: ColoredBox(color: ClinicColors.page)),
            const Align(alignment: Alignment(-0.1, 0), child: SizedBox(width: 12, height: double.infinity, child: ColoredBox(color: ClinicColors.page))),
            Align(alignment: const Alignment(-0.1, -0.35), child: Icon(Icons.location_on_rounded, size: 40, color: AppColors.primary)),
          ]),
        ),
      );
}
