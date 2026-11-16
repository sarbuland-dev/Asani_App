import 'dart:async';

import 'package:asani_core/asani_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/config/env.dart';
import '../../core/errors/app_exception.dart';
import '../../core/net/connectivity.dart';
import 'package:asani_ui/asani_ui.dart';
import '../../data/providers.dart';
import '../family/profile_form.dart';

/// S-08 → S-09 → S-10: patient → date → confirm (PRD F-04).
class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key, required this.clinicId, required this.doctorId, this.initialPatientId, this.initialDate});
  final String clinicId;
  final String doctorId;
  final String? initialPatientId;
  final String? initialDate;

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  int _step = 0;
  String? _patientId;
  String? _date;
  bool _booking = false;
  bool _bookingSlow = false; // > 6 s: say we're still working
  Timer? _slowTimer;
  String? _error;
  bool _prefilled = false;

  /// Active token of [patientId] with this doctor on [date], if any (BR-5).
  Token? _existingToken(List<Token> tokens, String patientId, String date) => tokens
      .where((t) => t.patientId == patientId && t.doctorId == widget.doctorId && t.date == date && t.status.isActive)
      .firstOrNull;

  void _applyPrefill(Doctor doctor, List<Patient> patients) {
    if (_prefilled) return;
    _prefilled = true;
    if (widget.initialPatientId != null && patients.any((p) => p.id == widget.initialPatientId)) {
      _patientId = widget.initialPatientId;
      _step = 1;
      final d = widget.initialDate;
      if (d != null) {
        final now = pktNow();
        final ok = availabilityFor(doctor: doctor, date: parseDayKey(d), now: now).canBook && d.compareTo(dayKey(now)) >= 0;
        if (ok) {
          _date = d;
          _step = 2; // follow-up: user only confirms (PRD F-09)
        }
      }
    } else if (patients.isNotEmpty) {
      _patientId = patients.first.id;
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() {
        _step--;
        _error = null;
      });
    } else {
      context.pop();
    }
  }

  Future<void> _confirm(Doctor doctor) async {
    if (_booking || _patientId == null || _date == null) return;
    // S-17 primer, once, before the first booking.
    final settings = ref.read(settingsRepositoryProvider).settings;
    if (!settings.primerShown) {
      await context.push('/notifications');
      if (!mounted) return;
    }
    setState(() {
      _booking = true;
      _bookingSlow = false;
      _error = null;
    });
    _slowTimer?.cancel();
    _slowTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _bookingSlow = true);
    });
    try {
      final token = await ref.read(tokenRepositoryProvider).bookToken(
            clinicId: widget.clinicId,
            doctorId: widget.doctorId,
            patientId: _patientId!,
            date: _date!,
          );
      if (mounted) context.pushReplacement('/booked/${token.id}');
    } catch (e) {
      if (mounted) setState(() => _error = AppException.messageOf(e));
    } finally {
      _slowTimer?.cancel();
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doctor = ref.watch(doctorProvider(widget.doctorId)).value;
    final clinic = ref.watch(clinicProvider(widget.clinicId)).value;
    final patientsAsync = ref.watch(myPatientsProvider);
    final tokens = ref.watch(myTokensProvider).value ?? const <Token>[];

    if (doctor == null || clinic == null || !patientsAsync.hasValue) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final patients = patientsAsync.value!;
    _applyPrefill(doctor, patients);

    final titles = ['Who is the patient?', 'Pick a date', 'Confirm booking'];
    final patient = patients.where((p) => p.id == _patientId).firstOrNull;
    final today = dayKey(pktNow());
    final blockedToday = patient == null ? null : _existingToken(tokens, patient.id, today);
    final blockedOnDate = (patient == null || _date == null) ? null : _existingToken(tokens, patient.id, _date!);

    // Booking needs internet (ARCHITECTURE.md §8); the demo works without it.
    final online = Env.isDemo || ref.watch(isOnlineProvider);
    final canContinue = switch (_step) {
      0 => patient != null && !(blockedToday != null && _isOnlyToday(doctor)),
      1 => _date != null && blockedOnDate == null,
      _ => !_booking && blockedOnDate == null && online,
    };

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GradientHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    HeaderBackButton(onPressed: _back),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(doctor.name, style: AppText.labelLarge.copyWith(color: AppColors.onPrimary)),
                        Text(clinic.name, style: AppText.bodyMedium.copyWith(color: AppColors.onPrimary.withValues(alpha: 0.85))),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: Gap.lg),
                  Text('Step ${_step + 1} of 3', style: AppText.labelMedium.copyWith(color: AppColors.onPrimary)),
                  const SizedBox(height: Gap.sm),
                  Row(children: [
                    for (var i = 0; i < 3; i++) ...[
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          height: 5,
                          decoration: BoxDecoration(
                            color: i <= _step ? AppColors.onPrimary : AppColors.onPrimary.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                        ),
                      ),
                      if (i < 2) const SizedBox(width: 6),
                    ],
                  ]),
                  const SizedBox(height: Gap.lg),
                  Text(titles[_step], style: AppText.headline.copyWith(color: AppColors.onPrimary)),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: switch (_step) {
                    0 => _patientStep(patients, tokens, doctor),
                    1 => _dateStep(doctor, patient, blockedOnDate),
                    _ => _confirmStep(clinic, doctor, patient!),
                  },
                ),
              ),
            ),
            if (_booking)
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.sm, Gap.screen, 0),
                child: Text(
                  _bookingSlow
                      ? 'Still working on it… Please keep the app open.'
                      : 'Getting your token number…',
                  textAlign: TextAlign.center,
                  style: AppText.bodyMedium,
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Gap.screen, Gap.sm, Gap.screen, Gap.md),
                child: FilledButton(
                  onPressed: canContinue
                      ? () {
                          if (_step < 2) {
                            setState(() {
                              _step++;
                              _error = null;
                              if (_step == 1 && _date == null) _date = _firstBookableDate(doctor);
                            });
                          } else {
                            _confirm(doctor);
                          }
                        }
                      : null,
                  child: _booking
                      ? const ButtonSpinner()
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          if (_step == 2) ...[const Icon(Icons.check_rounded), const SizedBox(width: Gap.sm)],
                          Text(_step == 2 ? (online ? 'Confirm booking' : 'Needs internet') : 'Next'),
                        ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// When today is the only bookable day, a patient with a token today can't continue.
  bool _isOnlyToday(Doctor doctor) => doctor.bookingWindowDays <= 1;

  String? _firstBookableDate(Doctor doctor) {
    final now = pktNow();
    for (final d in bookingDates(doctor, now)) {
      final key = dayKey(d);
      final day = ref.read(queueDayProvider((doctorId: doctor.id, date: key))).value;
      if (availabilityFor(doctor: doctor, date: d, day: day, now: now).canBook) return key;
    }
    return null;
  }

  // ---------------------------------------------------------------- step 1

  Widget _patientStep(List<Patient> patients, List<Token> tokens, Doctor doctor) {
    final today = dayKey(pktNow());
    return ListView(
      padding: const EdgeInsets.all(Gap.screen),
      children: [
        Text('Patient', style: AppText.labelMedium),
        const SizedBox(height: Gap.sm),
        for (final p in patients)
          Builder(builder: (context) {
            final existing = _existingToken(tokens, p.id, today);
            final selected = p.id == _patientId;
            final (bg, fg) = InitialsAvatar.colorsFor(p.relation);
            return Padding(
              padding: const EdgeInsets.only(bottom: Gap.md),
              child: AppCard(
                onTap: () => setState(() => _patientId = p.id),
                color: selected ? AppColors.primaryContainer.withValues(alpha: 0.45) : AppColors.surface,
                borderColor: selected ? AppColors.primary : AppColors.border,
                padding: const EdgeInsets.all(Gap.md),
                child: Row(children: [
                  InitialsAvatar(name: p.name, size: 46, bg: bg, fg: fg),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.name, style: AppText.titleSmall),
                      Text(patientSubtitle(p), style: AppText.bodyMedium),
                      if (existing != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(children: [
                            const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.warning),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text('Already has token ${existing.label} today',
                                  style: AppText.labelSmall.copyWith(color: AppColors.warning, fontWeight: FontWeight.w600)),
                            ),
                          ]),
                        ),
                    ]),
                  ),
                  Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                      color: selected ? AppColors.primary : AppColors.textMuted),
                ]),
              ),
            );
          }),
        const SizedBox(height: Gap.xs),
        // Same button as the Family tab.
        SizedBox(
          height: 56,
          child: OutlinedButton.icon(
            onPressed: () async {
              final p = await showAddFamilySheet(context);
              if (p != null && mounted) setState(() => _patientId = p.id);
            },
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Add family member'),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- step 2

  Widget _dateStep(Doctor doctor, Patient? patient, Token? blockedOnDate) {
    final now = pktNow();
    final dates = bookingDates(doctor, now);
    final selectedDate = _date == null ? null : parseDayKey(_date!);
    final selectedDay = _date == null ? null : ref.watch(queueDayProvider((doctorId: doctor.id, date: _date!))).value;
    final schedule = selectedDate == null ? null : doctor.scheduleOn(selectedDate);

    return ListView(
      padding: const EdgeInsets.all(Gap.screen),
      children: [
        Row(children: [
          Expanded(child: Text(DateFormat('MMMM y').format(now), style: AppText.titleMedium)),
          Text('Next ${dates.length} days', style: AppText.labelSmall),
        ]),
        const SizedBox(height: Gap.md),
        SizedBox(
          // Grows with the user's text size (up to 1.3×); body-text factor
          // because Android 14+ scales big sizes less (non-linear).
          height: 40 + 64 * (MediaQuery.textScalerOf(context).scale(14) / 14),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: dates.length,
            separatorBuilder: (_, _) => const SizedBox(width: Gap.sm),
            itemBuilder: (_, i) {
              final d = dates[i];
              final key = dayKey(d);
              final day = ref.watch(queueDayProvider((doctorId: doctor.id, date: key))).value;
              final av = availabilityFor(doctor: doctor, date: d, day: day, now: now);
              final selected = key == _date;
              final label = i == 0 ? 'Today' : (i == 1 ? 'Tomorrow' : DateFormat('EEE').format(d));
              return Semantics(
                button: true,
                enabled: av.canBook,
                selected: selected,
                label: '$label ${d.day}${av.canBook ? '' : ', ${av.shortReason}'}',
                child: GestureDetector(
                  onTap: av.canBook ? () => setState(() => _date = key) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 66,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : (av.canBook ? AppColors.surface : AppColors.muted),
                      borderRadius: BorderRadius.circular(Radii.pill),
                      border: Border.all(color: selected ? AppColors.primary : AppColors.border),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ExcludeSemantics(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        // "Tomorrow" shrinks to fit instead of breaking at large text sizes.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(label,
                              maxLines: 1,
                              style: AppText.labelSmall.copyWith(color: selected ? AppColors.onPrimary : AppColors.textSecondary)),
                        ),
                        const SizedBox(height: 2),
                        Text('${d.day}',
                            style: AppText.titleLarge.copyWith(
                              color: selected ? AppColors.onPrimary : (av.canBook ? AppColors.textPrimary : AppColors.textMuted),
                              decoration: av == DoctorAvailability.full ? TextDecoration.lineThrough : null,
                            )),
                        if (!av.canBook)
                          Text(av.shortReason, style: AppText.labelSmall),
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: Gap.lg),
        if (_date == null)
          const EmptyState(
            icon: Icons.event_busy_outlined,
            title: 'No dates available',
            message: 'This doctor has no open dates in the booking window. Please try another doctor.',
          )
        else
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                InitialsAvatar(name: doctor.name, size: 44, bg: AppColors.primaryContainer, fg: AppColors.primary),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(doctor.name, style: AppText.titleSmall),
                    if (schedule != null)
                      Row(children: [
                        const Icon(Icons.schedule_rounded, size: 15, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(Fmt.timeRange(schedule), style: AppText.bodyMedium),
                      ]),
                  ]),
                ),
              ]),
              const SizedBox(height: Gap.md),
              Row(children: [
                Expanded(
                  child: Text('${selectedDay?.bookedCount ?? 0} of ${doctor.maxTokensPerDay} tokens booked',
                      style: AppText.labelMedium),
                ),
                Text('${doctor.maxTokensPerDay - (selectedDay?.bookedCount ?? 0)} left',
                    style: AppText.labelMedium.copyWith(color: AppColors.success)),
              ]),
              const SizedBox(height: Gap.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.pill),
                child: LinearProgressIndicator(
                  value: (selectedDay?.bookedCount ?? 0) / doctor.maxTokensPerDay,
                  minHeight: 8,
                  backgroundColor: AppColors.muted,
                  color: AppColors.primary,
                ),
              ),
            ]),
          ),
        if (blockedOnDate != null && patient != null) ...[
          const SizedBox(height: Gap.md),
          _ErrorBox(text: '${patient.name} already has token ${blockedOnDate.label} with this doctor on this day.'),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------- step 3

  Widget _confirmStep(Clinic clinic, Doctor doctor, Patient patient) {
    final schedule = doctor.scheduleOn(parseDayKey(_date!));
    final age = patient.age();
    return ListView(
      padding: const EdgeInsets.all(Gap.screen),
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.xs),
          child: Column(children: [
            _SummaryRow(icon: Icons.local_hospital_outlined, label: 'Clinic', value: '${clinic.name}, ${clinic.area}'),
            const Divider(),
            _SummaryRow(icon: Icons.medical_services_outlined, label: 'Doctor', value: doctor.name),
            const Divider(),
            _SummaryRow(
              icon: Icons.person_outline_rounded,
              label: 'Patient',
              value: '${patient.name} (${[if (!patient.isSelf) patient.relation.label, if (age != null) '$age'].join(', ')})'
                  .replaceAll(' ()', ''),
            ),
            const Divider(),
            _SummaryRow(
              icon: Icons.calendar_today_outlined,
              label: 'Date',
              value: '${Fmt.relativeDay(_date!)}${schedule == null ? '' : ' · ${Fmt.timeRangeShort(schedule)}'}',
            ),
          ]),
        ),
        const SizedBox(height: Gap.md),
        Container(
          padding: const EdgeInsets.all(Gap.md),
          decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(Radii.button)),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 20),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text('Your token number is given when you confirm.',
                  style: AppText.bodyMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.w500)),
            ),
          ]),
        ),
        if (_error != null) ...[
          const SizedBox(height: Gap.md),
          _ErrorBox(text: _error!),
        ],
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.md),
        child: Row(children: [
          IconBox(icon: icon, size: 40),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: AppText.labelSmall),
              Text(value, style: AppText.labelLarge),
            ]),
          ),
        ]),
      );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(color: AppColors.dangerContainer, borderRadius: BorderRadius.circular(Radii.button)),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
          const SizedBox(width: Gap.sm),
          Expanded(child: Text(text, style: AppText.bodyMedium.copyWith(color: AppColors.danger))),
        ]),
      );
}
