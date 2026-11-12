/// Public links printed on slips and posters. The real domain is still open
/// (PRD-CLINIC-WEB Q-W09); change it here only.
abstract final class AppLinks {
  static const base = 'https://asani.app';
  static String clinic(String clinicId) => '$base/c/$clinicId';
  static String token(String tokenId) => '$base/t/$tokenId';
}
