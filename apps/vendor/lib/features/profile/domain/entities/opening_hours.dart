import 'package:flutter/foundation.dart';

/// One day the kitchen is open, and when.
///
/// A day the restaurant is closed is simply the absence of an [OpeningHours] for
/// that weekday — the same way the database stores it (migration 0018). Times are
/// held as minutes since midnight, not a Flutter `TimeOfDay`, so the domain stays
/// free of the toolkit; the editor converts at the edge.
@immutable
class OpeningHours {
  const OpeningHours({
    required this.weekday,
    required this.opensMinutes,
    required this.closesMinutes,
  });

  /// ISO weekday: 1 = Monday … 7 = Sunday. Matches `DateTime.weekday` and the
  /// `day_of_week` column, so neither side does modular arithmetic.
  final int weekday;

  /// Minutes since midnight. `closesMinutes` is always greater than
  /// `opensMinutes` — the database's `closes > opens` check is the backstop.
  final int opensMinutes;
  final int closesMinutes;

  /// From a `restaurant_hours` row: `opens`/`closes` arrive as `HH:MM:SS`.
  factory OpeningHours.fromRow(Map<String, dynamic> row) => OpeningHours(
    weekday: (row['day_of_week'] as num).toInt(),
    opensMinutes: _minutesFromTime(row['opens'] as String),
    closesMinutes: _minutesFromTime(row['closes'] as String),
  );

  /// For `set_restaurant_hours`: `HH:MM` is enough, Postgres casts it to `time`.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'day': weekday,
    'opens': _timeFromMinutes(opensMinutes),
    'closes': _timeFromMinutes(closesMinutes),
  };

  static int _minutesFromTime(String hms) {
    final List<String> parts = hms.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  static String _timeFromMinutes(int minutes) {
    final String h = (minutes ~/ 60).toString().padLeft(2, '0');
    final String m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}
