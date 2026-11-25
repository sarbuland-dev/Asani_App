/// Error with a stable code and a plain-words message (DESIGN.md §6–7).
class AppException implements Exception {
  const AppException(this.code, this.message);

  final String code;
  final String message;

  // bookToken error codes (DESIGN.md §7)
  static const clinicUnavailable = AppException('clinic-unavailable', "This clinic isn't taking online bookings right now.");
  static const doctorUnavailable =
      AppException('doctor-unavailable', "The doctor isn't available on this day. Please pick another date.");
  static const sessionEnded = AppException('session-ended', "Today's session has ended. Please pick another date.");
  static const tokensFull =
      AppException('tokens-full', 'All tokens for this day are booked. Please pick another date.');
  static const tooManyActive =
      AppException('too-many-active', 'You already have 5 active tokens. Cancel one to book another.');
  static const network = AppException('network', 'No internet connection. Your booking was not made.');
  static const bookingFailed = AppException('unknown', 'Booking failed. Please try again.');

  static AppException duplicateToken(String name, String label) =>
      AppException('duplicate-token', '$name already has token $label with this doctor on this day.');

  // Auth (PRD F-01, D-52: email code login, unverified phone)
  static const invalidEmail = AppException('invalid-email', 'Please enter a valid email address.');
  static const wrongCode = AppException('invalid-code', "That code isn't right. Please check and try again.");
  static const codeExpired = AppException('code-expired', 'This code has expired. Please request a new one.');
  static const tooManyAttempts =
      AppException('too-many-requests', 'Too many attempts. Please wait a few minutes and try again.');
  static const phoneTaken =
      AppException('phone-taken', 'This number is already used by another Asani account. Please use a different number.');
  static const invalidPhone = AppException('invalid-phone', 'Please enter a valid mobile number, e.g. 300 1234567.');
  static const noInternet = AppException('network', 'No internet connection. Please try again.');
  static const sessionExpired = AppException('session-expired', 'Session expired. Please log in again.');

  static const generic = AppException('unknown', 'Something went wrong. Please try again.');

  /// Plain message for any error, never raw exception text.
  static String messageOf(Object error) => error is AppException ? error.message : generic.message;

  @override
  String toString() => 'AppException($code)';
}
