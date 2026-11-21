import 'dates.dart';
import 'models.dart';

/// Doctor availability for a date (PRD F-03, F-04 date step).
enum DoctorAvailability {
  available,
  notStarted,
  onLeave,
  notScheduled,
  full,
  ended;

  /// BR-2..BR-4: booking allowed for this date.
  bool get canBook => this == available || this == notStarted;

  /// Short reason shown under a disabled date chip.
  String get shortReason => switch (this) {
        available || notStarted => '',
        onLeave => 'On leave',
        notScheduled => 'No clinic',
        full => 'Full',
        ended => 'Ended',
      };
}

DoctorAvailability availabilityFor({
  required Doctor doctor,
  required DateTime date,
  QueueDay? day,
  required DateTime now,
}) {
  if (!doctor.active) return DoctorAvailability.notScheduled;
  if (doctor.onLeave(date)) return DoctorAvailability.onLeave;
  final schedule = doctor.scheduleOn(date);
  if (schedule == null) return DoctorAvailability.notScheduled;
  if ((day?.bookedCount ?? 0) >= doctor.maxTokensPerDay) return DoctorAvailability.full;

  final isToday = dayKey(date) == dayKey(now);
  if (isToday) {
    final nowMin = now.hour * 60 + now.minute;
    if (day?.sessionStatus.name == 'ended' || nowMin >= schedule.endMinutes) {
      return DoctorAvailability.ended;
    }
    final running = day?.sessionStatus.name == 'running' || day?.sessionStatus.name == 'paused';
    if (!running && nowMin < schedule.startMinutes) return DoctorAvailability.notStarted;
  }
  return DoctorAvailability.available;
}

/// A clinic is "Open today" when at least one doctor works today.
bool clinicOpenOn(Iterable<Doctor> doctors, DateTime date) =>
    doctors.any((d) => d.active && !d.onLeave(date) && d.scheduleOn(date) != null);

/// Open right now: some doctor working today whose session hasn't ended yet
/// (before its end time). When every doctor's session is over, the clinic
/// shows "Closed now" (PRD D-27).
bool clinicOpenNow(Iterable<Doctor> doctors, DateTime now) {
  final nowMin = now.hour * 60 + now.minute;
  return doctors.any((d) {
    if (!d.active || d.onLeave(now)) return false;
    final s = d.scheduleOn(now);
    return s != null && nowMin < s.endMinutes;
  });
}

/// How long after a doctor's session end time a today token still counts as
/// "Active" on Home / My Tokens (PRD D-27).
const tokenGraceAfterSession = Duration(hours: 1);

/// D-27: whether a token is still live for the patient. Closed statuses and
/// past days are never live; future days always are. Today's token stops
/// being live when the clinic ended the session, or one hour after the
/// doctor's session end time (the 3 AM job closes it properly later).
bool tokenIsLive(Token t, {Doctor? doctor, QueueDay? day, required DateTime now}) {
  // D-35: a Skipped token stays live (paused) until the session is over.
  if (!t.status.isOpenForPatient) return false;
  final today = dayKey(now);
  if (t.date.compareTo(today) < 0) return false;
  if (t.date.compareTo(today) > 0) return true;
  if (day?.sessionStatus.name == 'ended' && t.status.name != 'arrived') return false;
  final s = doctor?.scheduleOn(now);
  if (s == null) return true; // unknown schedule: keep showing it
  final nowMin = now.hour * 60 + now.minute;
  return nowMin < s.endMinutes + tokenGraceAfterSession.inMinutes;
}

/// Bookable dates: today + the doctor's booking window (PRD F-04 step 2).
List<DateTime> bookingDates(Doctor doctor, DateTime now) {
  final today = dateOnly(now);
  return [for (var i = 0; i < doctor.bookingWindowDays; i++) today.add(Duration(days: i))];
}
