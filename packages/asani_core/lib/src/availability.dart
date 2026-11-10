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

/// Bookable dates: today + the doctor's booking window (PRD F-04 step 2).
List<DateTime> bookingDates(Doctor doctor, DateTime now) {
  final today = dateOnly(now);
  return [for (var i = 0; i < doctor.bookingWindowDays; i++) today.add(Duration(days: i))];
}
