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
import '../../core/widgets/dead_end.dart';

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

  /// True while [_date] was chosen by the app, not by the patient.
  bool _autoDate = false;

  /// D-50: which month of the booking window the calendar shows (‹ › arrows).
  int _monthIdx = 0;
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
    final doctorAsync = ref.watch(doctorProvider(widget.doctorId));
    final clinicAsync = ref.watch(clinicProvider(widget.clinicId));
    final doctor = doctorAsync.value;
    final clinic = clinicAsync.value;
    final patientsAsync = ref.watch(myPatientsProvider);
    final tokens = ref.watch(myTokensProvider).value ?? const <Token>[];

    if (doctor == null || clinic == null || !patientsAsync.hasValue) {
      final failed = [doctorAsync, clinicAsync, patientsAsync].where((a) => a.hasError && !a.hasValue).firstOrNull;
      if (failed != null) {
        return LoadErrorScreen(
          error: failed.error,
          onRetry: () {
            ref.invalidate(doctorProvider(widget.doctorId));
            ref.invalidate(clinicProvider(widget.clinicId));
            ref.invalidate(myPatientsProvider);
          },
        );
      }
      if ((doctorAsync.hasValue && doctor == null) || (clinicAsync.hasValue && clinic == null)) {
        return const NotFoundScreen(
          icon: Icons.medical_services_outlined,
          title: 'Doctor not found',
          message: 'This doctor is no longer listed at this clinic.',
        );
      }
      return const LoadingScreen();
    }
    final patients = patientsAsync.value!;
    _applyPrefill(doctor, patients);
    // "Book again" and alert links open on the date step: pick the first open day there too (B14).
    if (_step == 1 && _date == null) {
      _date = _firstBookableDate(doctor);
      _autoDate = _date != null;
    }

    final titles = ['Who is the patient?', 'Pick a date', 'Review and confirm'];
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

    final subtitles = [
      '${doctor.name} · ${clinic.name}',
      patient == null ? '' : 'For ${patient.name}${patient.isSelf ? ' (Self)' : ' (${patient.relation.label})'}',
      'Check the details before booking',
    ];

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: StatusBarScrim(
        child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Board P4: green header with back, the step's title and the 3 step bars.
            Container(
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.header)),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, Gap.sm, 20, 18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      HeaderBackButton(onPressed: _back),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(titles[_step],
                              style: AppText.labelLarge.copyWith(color: AppColors.onPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                          Text(subtitles[_step],
                              style: AppText.labelSmall.copyWith(color: AppColors.onPrimaryMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    Semantics(
                      label: 'Step ${_step + 1} of 3',
                      child: Row(children: [
                        for (var i = 0; i < 3; i++) ...[
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              height: 5,
                              decoration: BoxDecoration(
                                color: i <= _step ? AppColors.onPrimary : AppColors.primaryMid,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                          if (i < 2) const SizedBox(width: 6),
                        ],
                      ]),
                    ),
                  ]),
                ),
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
                  _bookingSlow ? 'Still working on it… Please keep the app open.' : 'Getting your token number…',
                  textAlign: TextAlign.center,
                  style: AppText.bodyMedium,
                ),
              ),
            Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, Gap.lg),
                  child: FilledButton(
                    onPressed: canContinue
                        ? () {
                            if (_step < 2) {
                              setState(() {
                                _step++;
                                _error = null;
                                if (_step == 1 && _date == null) {
                                  _date = _firstBookableDate(doctor);
                                  _autoDate = true;
                                }
                              });
                            } else {
                              _confirm(doctor);
                            }
                          }
                        : null,
                    child: _booking
                        ? const ButtonSpinner()
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(_step == 2 ? (online ? 'Confirm booking' : 'Needs internet') : 'Continue'),
                            const SizedBox(width: Gap.xs),
                            const Icon(Icons.chevron_right_rounded),
                          ]),
                  ),
                ),
              ),
            ),
          ],
        ),
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

  /// Board P4 S-08: one card per family member with a radio; the chosen one
  /// has a green edge. Someone who already has a token today is greyed with
  /// an amber note. "+ Add family member" in cream at the end.
  Widget _patientStep(List<Patient> patients, List<Token> tokens, Doctor doctor) {
    final today = dayKey(pktNow());
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      children: [
        for (final p in patients)
          Builder(builder: (context) {
            final existing = _existingToken(tokens, p.id, today);
            final selected = p.id == _patientId;
            final blocked = existing != null && _isOnlyToday(doctor);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Semantics(
                button: true,
                selected: selected,
                label: '${p.name}, ${patientSubtitle(p)}${existing == null ? '' : '. Already has token ${existing.label} today'}',
                excludeSemantics: true,
                child: Material(
                  color: selected || existing != null ? AppColors.background : AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: blocked ? null : () => setState(() => _patientId = p.id),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: existing != null
                                ? AppColors.cream
                                : (selected ? AppColors.primary : AppColors.primaryContainer),
                          ),
                          child: Text(Fmt.initials(p.name),
                              style: AppText.labelMedium.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: existing != null
                                      ? AppColors.textSecondary
                                      : (selected ? AppColors.onPrimary : AppColors.primary))),
                        ),
                        const SizedBox(width: Gap.md),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p.name,
                                style: AppText.labelLarge.copyWith(
                                    fontWeight: FontWeight.w700, color: existing != null ? AppColors.textSecondary : AppColors.textPrimary)),
                            Text(
                              existing == null ? patientSubtitle(p) : 'Already has token ${existing.label} today',
                              style: AppText.labelSmall.copyWith(
                                  color: existing == null ? AppColors.textSecondary : AppColors.warning,
                                  fontWeight: existing == null ? FontWeight.w500 : FontWeight.w600),
                            ),
                          ]),
                        ),
                        if (!blocked)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: selected ? AppColors.primary : AppColors.borderStrong, width: selected ? 7 : 2),
                            ),
                          ),
                      ]),
                    ),
                  ),
                ),
              ),
            );
          }),
        // Same action as the Family tab.
        Material(
          color: AppColors.cream,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () async {
              final p = await showAddFamilySheet(context);
              if (p != null && mounted) setState(() => _patientId = p.id);
            },
            child: SizedBox(
              height: 52,
              child: Center(
                child: Text('+ Add family member', style: AppText.labelLarge.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- step 2

  /// Board P4 S-09: a month-style calendar of the booking window (Mon first;
  /// past days and days with no clinic struck out, leave in red, full in
  /// amber, the chosen day green), a legend, then the session card.
  Widget _dateStep(Doctor doctor, Patient? patient, Token? blockedOnDate) {
    final now = pktNow();
    final dates = bookingDates(doctor, now);
    final inWindow = {for (final d in dates) dayKey(d)};
    final first = dateOnly(now).subtract(Duration(days: now.weekday - 1));
    final last = dates.isEmpty ? first : dates.last.add(Duration(days: 7 - dates.last.weekday));
    final allDays = [for (var d = first; !d.isAfter(last); d = d.add(const Duration(days: 1))) d];
    // D-50: one month at a time, with ‹ › when the window crosses into the next month.
    final months = <DateTime>{for (final d in dates.isEmpty ? [dateOnly(now)] : dates) DateTime(d.year, d.month)}.toList();
    final monthIdx = _monthIdx.clamp(0, months.length - 1);
    final month = months[monthIdx];
    bool inMonth(DateTime d) => d.year == month.year && d.month == month.month;
    // Whole weeks that touch this month; days of other months stay blank.
    final days = <DateTime?>[
      for (var w = 0; w < allDays.length; w += 7)
        if (allDays.skip(w).take(7).any(inMonth))
          for (final d in allDays.skip(w).take(7)) inMonth(d) ? d : null,
    ];

    final selectedDate = _date == null ? null : parseDayKey(_date!);
    final selectedDay = _date == null ? null : ref.watch(queueDayProvider((doctorId: doctor.id, date: _date!))).value;
    final schedule = selectedDate == null ? null : doctor.scheduleOn(selectedDate);
    final booked = selectedDay?.bookedCount ?? 0;

    // The app picked this day before its queue had loaded; if it is full, pick again.
    if (_autoDate && selectedDate != null && selectedDay != null &&
        !availabilityFor(doctor: doctor, date: selectedDate, day: selectedDay, now: now).canBook) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_autoDate) return;
        final next = _firstBookableDate(doctor);
        if (next != _date) setState(() => _date = next);
      });
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      children: [
        Container(
          padding: const EdgeInsets.all(Gap.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(DateFormat('MMMM').format(month), style: AppText.titleMedium.copyWith(fontWeight: FontWeight.w700))),
              IconButton(
                tooltip: 'Previous month',
                onPressed: monthIdx > 0 ? () => setState(() => _monthIdx = monthIdx - 1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: monthIdx < months.length - 1 ? () => setState(() => _monthIdx = monthIdx + 1) : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              for (final w in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
                Expanded(child: Text(w, textAlign: TextAlign.center, style: AppText.labelSmall.copyWith(fontSize: 11))),
            ]),
            const SizedBox(height: 4),
            GridView.count(
              // Without this the grid adds the status bar's height on top.
              padding: EdgeInsets.zero,
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 0.95,
              children: [
                for (final dd in days)
                  if (dd == null)
                    const SizedBox.shrink()
                  else
                  Builder(builder: (context) {
                    final d = dd;
                    final key = dayKey(d);
                    final open = inWindow.contains(key);
                    final day = open ? ref.watch(queueDayProvider((doctorId: doctor.id, date: key))).value : null;
                    final av = open ? availabilityFor(doctor: doctor, date: d, day: day, now: now) : null;
                    final selected = key == _date;
                    final canBook = av?.canBook ?? false;
                    final (Color bg, Color fg, bool strike) = selected
                        ? (AppColors.primary, AppColors.onPrimary, false)
                        : switch (av) {
                            null => (Colors.transparent, AppColors.borderStrong, false),
                            DoctorAvailability.onLeave => (AppColors.dangerContainer, AppColors.dangerText, false),
                            DoctorAvailability.full => (AppColors.warningContainer, AppColors.warningText, false),
                            DoctorAvailability.notScheduled ||
                            DoctorAvailability.ended =>
                              (Colors.transparent, AppColors.borderStrong, true),
                            _ => (AppColors.cream, AppColors.textPrimary, false),
                          };
                    return Semantics(
                      button: canBook,
                      enabled: canBook,
                      selected: selected,
                      label: '${DateFormat('EEEE d MMMM').format(d)}${av == null || canBook ? '' : ', ${av.shortReason}'}',
                      excludeSemantics: true,
                      child: Material(
                        color: bg,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: canBook
                              ? () => setState(() {
                                    _autoDate = false;
                                    _date = key;
                                  })
                              : null,
                          child: Center(
                            child: Text('${d.day}',
                                style: AppText.labelMedium.copyWith(
                                  color: fg,
                                  decoration: strike ? TextDecoration.lineThrough : null,
                                  decorationColor: fg,
                                )),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
            const SizedBox(height: Gap.md),
            Wrap(spacing: Gap.md, runSpacing: 4, children: [
              _legend(AppColors.dangerContainer, 'On leave'),
              _legend(AppColors.warningContainer, 'Full'),
              Text('Struck · no clinic', style: AppText.labelSmall.copyWith(fontSize: 11)),
            ]),
          ]),
        ),
        const SizedBox(height: Gap.md),
        if (_date == null)
          const EmptyState(
            icon: Icons.event_busy_outlined,
            title: 'No dates available',
            message: 'This doctor has no open dates in the booking window. Please try another doctor.',
          )
        else ...[
          Text('Session on ${Fmt.shortDay(_date!)}', style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: Gap.sm),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(schedule == null ? '—' : Fmt.timeRange(schedule), style: AppText.labelLarge.copyWith(fontWeight: FontWeight.w700))),
                if (selectedDay?.sessionStatus == SessionStatus.running)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.successContainer, borderRadius: BorderRadius.circular(Radii.pill)),
                    child: Text('● Running', style: AppText.labelSmall.copyWith(color: AppColors.successText, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
              ]),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: doctor.maxTokensPerDay == 0 ? 0 : (booked / doctor.maxTokensPerDay).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: AppColors.cream,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Text('$booked of ${doctor.maxTokensPerDay} booked', style: AppText.labelSmall.copyWith(fontSize: 13))),
                Text('${doctor.maxTokensPerDay - booked} left',
                    style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
        ],
        if (blockedOnDate != null && patient != null) ...[
          const SizedBox(height: Gap.md),
          _ErrorBox(text: '${patient.name} already has token ${blockedOnDate.label} with this doctor on this day.'),
        ],
      ],
    );
  }

  Widget _legend(Color c, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(text, style: AppText.labelSmall.copyWith(fontSize: 11)),
      ]);

  // ---------------------------------------------------------------- step 3

  /// Board P4 S-10: a dark ticket (doctor, clinic, notches, Date / Session /
  /// Token "A-??"), the patient strip with Change, today's queue, and the
  /// note that the number comes on confirm.
  Widget _confirmStep(Clinic clinic, Doctor doctor, Patient patient) {
    final schedule = doctor.scheduleOn(parseDayKey(_date!));
    final isToday = _date == dayKey(pktNow());
    final day = ref.watch(queueDayProvider((doctorId: doctor.id, date: _date!))).value;
    Widget cell(String label, String value, {bool faded = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppText.labelSmall.copyWith(fontSize: 11, color: AppColors.primarySoft)),
          Text(value,
              style: AppText.labelMedium.copyWith(
                  color: AppColors.onPrimary.withValues(alpha: faded ? 0.75 : 1), fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ]);
    Widget tile(String label, String value, {bool dark = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: dark ? AppColors.primary : AppColors.cream, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: AppText.labelSmall.copyWith(fontSize: 11, color: dark ? AppColors.onPrimaryMuted : AppColors.textSecondary)),
              Text(value,
                  style: AppText.titleMedium.copyWith(fontSize: 17, fontWeight: FontWeight.w700, color: dark ? AppColors.onPrimary : AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      children: [
        // The ticket.
        Container(
          decoration: BoxDecoration(
            gradient: AppColors.coverGradient,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.22), blurRadius: 24, offset: const Offset(0, 10))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppColors.cream, shape: BoxShape.circle),
                  child: Text(Fmt.initials(doctor.name),
                      style: AppText.labelLarge.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(doctor.name, style: AppText.labelLarge.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700)),
                    Text('${doctor.specialityEnum.label} · ${clinic.name}',
                        style: AppText.labelSmall.copyWith(color: AppColors.onPrimaryMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                Semantics(
                  button: true,
                  label: 'Change date',
                  excludeSemantics: true,
                  child: Material(
                    color: AppColors.cream.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _step = 1),
                      child: const SizedBox.square(dimension: 40, child: Icon(Icons.edit_outlined, size: 17, color: AppColors.onPrimary)),
                    ),
                  ),
                ),
              ]),
            ),
            // Tear line with two notches.
            SizedBox(
              height: 22,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned(left: -11, top: 0, child: _notch()),
                Positioned(right: -11, top: 0, child: _notch()),
                const Positioned(left: 16, right: 16, top: 10, child: DashedLine(color: Color(0x40F0EDE4))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Row(children: [
                Expanded(child: cell('Date', Fmt.shortDay(_date!))),
                Expanded(child: cell('Session', schedule == null ? '—' : Fmt.timeRangeShort(schedule))),
                Expanded(child: cell('Token', '${doctor.tokenPrefix}-??', faded: true)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: Gap.md),
        // Patient strip.
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: Text(Fmt.initials(patient.name),
                  style: AppText.labelMedium.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('PATIENT', style: AppText.labelSmall.copyWith(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primaryLight)),
                Text(patient.name, style: AppText.labelLarge.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
                Text(patientSubtitle(patient), style: AppText.labelSmall.copyWith(color: AppColors.primaryLight)),
              ]),
            ),
            TextButton(onPressed: () => setState(() => _step = 0), child: const Text('Change')),
          ]),
        ),
        if (isToday && day != null) ...[
          const SizedBox(height: Gap.md),
          Text('Queue today', style: AppText.labelMedium.copyWith(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: Gap.sm),
          Row(children: [
            tile('Booked', '${day.bookedCount}/${doctor.maxTokensPerDay}'),
            const SizedBox(width: Gap.sm),
            tile('Now serving', day.currentToken == 0 ? '—' : doctor.tokenLabel(day.currentToken), dark: true),
            const SizedBox(width: Gap.sm),
            tile('Est. wait', Fmt.wait(estimatedWaitMinutes(day.waitingCount, doctor.avgConsultMinutes))),
          ]),
        ],
        const SizedBox(height: Gap.md),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(color: AppColors.cream, shape: BoxShape.circle),
              child: const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('Your token number is given when you confirm.', style: AppText.labelSmall.copyWith(height: 1.5))),
          ]),
        ),
        if (_error != null) ...[
          const SizedBox(height: Gap.md),
          _ErrorBox(text: _error!),
        ],
      ],
    );
  }

  Widget _notch() => Container(width: 22, height: 22, decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle));
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
