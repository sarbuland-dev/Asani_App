import 'package:asani_core/asani_core.dart';

/// Postgres rows (snake_case, ISO timestamps; D-52) → the maps the shared `asani_core` models read
/// (camelCase, epoch milliseconds). One place, so every repository reads rows the same way.
abstract final class Rows {
  static final _snake = RegExp(r'_([a-z0-9])');

  static String camel(String key) => key.replaceAllMapped(_snake, (m) => m[1]!.toUpperCase());

  /// Keys to camelCase; `*_at` ISO strings to epoch ms.
  static Map<String, Object?> plain(Map<String, dynamic> row) {
    final m = <String, Object?>{};
    row.forEach((k, v) {
      m[camel(k)] = (k.endsWith('_at') && v is String) ? DateTime.tryParse(v)?.millisecondsSinceEpoch : v;
    });
    return m;
  }

  /// Parses a list, logging and skipping rows that do not fit the model instead of failing the screen.
  static List<T> parseAll<T>(Iterable<Map<String, dynamic>> rows, T Function(Map<String, dynamic>) parse, String what) {
    final out = <T>[];
    for (final r in rows) {
      try {
        out.add(parse(r));
      } catch (e) {
        AppLogger.warn('Skipping $what ${r['id'] ?? ''}: $e');
      }
    }
    return out;
  }

  static Clinic clinic(Map<String, dynamic> r) {
    final m = plain(r);
    final lat = r['lat'], lng = r['lng'];
    m['location'] = (lat is num && lng is num) ? {'lat': lat, 'lng': lng} : null;
    return Clinic.fromMap(m);
  }

  static Doctor doctor(Map<String, dynamic> r) => Doctor.fromMap(plain(r));

  static QueueDay queueDay(Map<String, dynamic> r) => QueueDay.fromMap(plain(r));

  /// Patient names are capitalised when read; the database keeps them as typed (D-59).
  static Map<String, Object?> _named(Map<Object?, Object?> m) => {
        ...m.cast<String, Object?>(),
        if (m['name'] is String) 'name': Fmt.personName(m['name']! as String),
      };

  static Patient patient(Map<String, dynamic> r) => Patient.fromMap(_named(plain(r)));

  static FollowUp followUp(Map<String, dynamic> r) => FollowUp.fromMap(plain(r));

  static AppNotification notification(Map<String, dynamic> r) => AppNotification.fromMap(r['id'] as String, plain(r));

  static const _steps = {
    'ahead3': QueueStep.threeAhead,
    'ahead2': QueueStep.twoAhead,
    'ahead1': QueueStep.oneAhead,
    'yourTurn': QueueStep.called,
  };

  /// `notified` jsonb ({ahead3: time, …}, DATABASE.md §7) → the steps sent and when (D-50).
  static Token token(Map<String, dynamic> r) {
    final m = plain(r);
    final notified = r['notified'];
    final snapshot = m['patientSnapshot'];
    if (snapshot is Map) m['patientSnapshot'] = _named(snapshot);
    m['notified'] = notified is Map ? [for (final k in notified.keys) _steps[k]?.name].whereType<String>().toList() : const <String>[];
    m['notifiedAt'] = notified is Map
        ? {
            for (final e in notified.entries)
              if (_steps[e.key] != null && e.value is String && DateTime.tryParse(e.value as String) != null)
                _steps[e.key]!.name: DateTime.parse(e.value as String).millisecondsSinceEpoch,
          }
        : const <String, int>{};
    return Token.fromMap(m);
  }
}
