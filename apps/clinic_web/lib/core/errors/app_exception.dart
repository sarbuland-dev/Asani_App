/// Error with a stable code and a plain-words message (DESIGN.md §6–7).
class AppException implements Exception {
  const AppException(this.code, this.message);

  final String code;
  final String message;

  static const wrongLogin = AppException('wrong-login', 'Email or password is incorrect.');
  static const tooManyAttempts =
      AppException('too-many-attempts', 'Too many attempts. Try again later or reset your password.');
  static const disabled = AppException('disabled', 'This account has been disabled. Please contact your clinic admin.');
  static const offline = AppException('offline', 'You are offline. Actions are disabled until the internet is back.');
  static const suspended =
      AppException('suspended', 'This clinic is suspended. The queue is read-only until the payment is recorded.');
  static const notAllowed = AppException('not-allowed', "You don't have permission to do this.");
  static const generic = AppException('unknown', 'Something went wrong. Please try again.');

  /// Plain message for any error, never raw exception text.
  static String messageOf(Object error) => error is AppException ? error.message : generic.message;

  @override
  String toString() => 'AppException($code)';
}
