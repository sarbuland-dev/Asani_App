import 'enums.dart';

/// Patients ahead (ARCHITECTURE.md §4): active numbers lower than mine.
int patientsAhead(List<int> activeNumbers, int myNumber) =>
    activeNumbers.where((n) => n < myNumber).length;

int estimatedWaitMinutes(int ahead, int avgConsultMinutes) => ahead * avgConsultMinutes;

/// Decides which queue notification to send now (PRD F-06, N-2..N-4).
///
/// Returns the step to send (or null) and the full set of steps that must be
/// marked as done, so skipped steps are never sent later.
({QueueStep? send, Set<QueueStep> notified}) nextQueueNotification({
  required TokenStatus status,
  required int ahead,
  required Set<QueueStep> alreadyNotified,
}) {
  QueueStep? current;
  if (status == TokenStatus.called) {
    current = QueueStep.called;
  } else if (status == TokenStatus.booked || status == TokenStatus.arrived) {
    if (ahead >= 1 && ahead <= 3) {
      current = QueueStep.values.firstWhere((s) => s.ahead == ahead);
    }
  }
  if (current == null || alreadyNotified.contains(current)) {
    return (send: null, notified: alreadyNotified);
  }
  // Mark this step and every earlier (higher "ahead") step as done.
  final updated = {
    ...alreadyNotified,
    ...QueueStep.values.where((s) => s.index <= current!.index),
  };
  return (send: current, notified: updated);
}
