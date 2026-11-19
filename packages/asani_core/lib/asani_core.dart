/// Shared Asani models, enums and business rules (pure Dart, no Flutter):
/// used by the patient app and the clinic web.
library;

export 'src/enums.dart';
export 'src/models.dart';
export 'src/availability.dart';
export 'src/queue_math.dart';
export 'src/dates.dart';
export 'src/formatters.dart'; // Fmt (dates, times, phone display), PhoneUtils
export 'src/logger.dart'; // AppLogger (AGENTS.md §6: no print)
export 'src/token_code.dart';
export 'src/speciality.dart'; // fixed list, D-31
export 'src/doctor_search.dart'; // distance, PMDC, Doctors tab cards (D-31..D-33)
