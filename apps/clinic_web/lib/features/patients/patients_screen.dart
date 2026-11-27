import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/clinic_kit.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'patient_profile_screen.dart';

/// W-14 / C-08: search this clinic's patients by phone or name. Profiles on
/// the left, the picked patient's history on the right.
class PatientsScreen extends ConsumerStatefulWidget {
  const PatientsScreen(this.clinicId, {super.key, this.initialPatientId});
  final String clinicId;

  /// Opened on one patient (/patients/:id).
  final String? initialPatientId;

  @override
  ConsumerState<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends ConsumerState<PatientsScreen> {
  final _q = TextEditingController();
  late String? _selectedId = widget.initialPatientId;

  /// The search box is filled with the opened patient's phone once, so the
  /// whole family shows.
  late bool _prefill = widget.initialPatientId != null;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(repoTickProvider);
    if (_prefill) {
      final phone = ref.watch(clinicPatientProvider((widget.clinicId, widget.initialPatientId!)))?.patient.phone;
      if (phone != null) {
        _prefill = false;
        if (_q.text.isEmpty) _q.text = '0${PhoneUtils.formatLocal(PhoneUtils.normalizeLocal(phone))}';
      }
    }
    final query = _q.text.trim();
    final results = query.length < 2 ? const <ClinicPatient>[] : ref.read(repositoryProvider).searchPatients(widget.clinicId, query);
    if (_selectedId == null && results.isNotEmpty) _selectedId = results.first.patient.id;
    final selected = _selectedId;

    return ClinicPage(
      title: 'Patients',
      subtitle: 'Only patients who visited or booked at this clinic are shown. Visits at other clinics are never shown.',
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: _searchBox()),
        ),
        const SizedBox(height: 18),
        if (selected == null && query.length < 2)
          const EmptyState(icon: Icons.person_search_rounded, title: 'Find a patient', message: 'Type at least 2 characters of a phone number or name.')
        else if (selected == null)
          const EmptyState(icon: Icons.search_off_rounded, title: 'No patients found', message: 'No one with this phone or name has visited this clinic.')
        else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (results.isNotEmpty) ...[
              SizedBox(width: MediaQuery.sizeOf(context).width >= 1360 ? 340 : 270, child: _list(query, results)),
              const SizedBox(width: 18),
            ],
            Expanded(child: PatientDetail(key: ValueKey(selected), clinicId: widget.clinicId, patientId: selected)),
          ]),
      ],
    );
  }

  Widget _searchBox() {
    OutlineInputBorder pill() =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.pill), borderSide: const BorderSide(color: AppColors.primary, width: 2));
    return TextField(
      controller: _q,
      autofocus: widget.initialPatientId == null,
      style: AppText.bodyLarge.copyWith(fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: 'Search by phone number (0300 1234567) or name',
        prefixIcon: const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.search_rounded, color: AppColors.primary)),
        suffixIcon: _q.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () => setState(() {
                  _q.clear();
                  _selectedId = null;
                }),
                icon: const Icon(Icons.close_rounded),
              ),
        enabledBorder: pill(),
        focusedBorder: pill(),
      ),
      onChanged: (_) => setState(() {
        _prefill = false;
        _selectedId = null;
      }),
    );
  }

  Widget _list(String query, List<ClinicPatient> results) {
    final byPhone = PhoneUtils.isValidLocal(query);
    final n = results.length;
    return Panel(
      radius: 16,
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Text(
            byPhone ? '$n profile${n == 1 ? '' : 's'} on this phone' : '$n patient${n == 1 ? '' : 's'} found',
            style: AppText.labelSmall.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        for (final p in results) _tile(p),
      ]),
    );
  }

  Widget _tile(ClinicPatient p) {
    final selected = p.patient.id == _selectedId;
    final visits = '${p.visitCount} visit${p.visitCount == 1 ? '' : 's'}';
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? ClinicColors.tint : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _selectedId = p.patient.id),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              selected ? Av.solid(p.patient.name) : Av(p.patient.name, bg: AppColors.onPrimaryMuted, fg: AppColors.navy),
              const SizedBox(width: 12),
              Expanded(
                child: TwoLine(p.patient.name, '${p.patient.relation.label} · ${p.patient.age(pktNow()) ?? '—'} ${p.patient.gender.short} · $visits'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
