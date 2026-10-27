/// All "what time is it" questions go through a Clock so tests (and the
/// diagnostics screen) can control time instead of depending on the phone.
abstract class Clock {
  DateTime nowUtc();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

extension ClockFormatting on Clock {
  /// Storage format for every timestamp: UTC, ISO-8601, always ends with 'Z'.
  String nowIso() => nowUtc().toIso8601String();

  /// Today's date on the phone's local calendar, as YYYY-MM-DD.
  /// Used for date-only fields such as a plan date.
  String todayLocal() => formatDate(nowUtc().toLocal());
}

String formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
