import 'clock.dart';

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _two(int n) => n.toString().padLeft(2, '0');

int currencyFractionDigits(String? currencyCode) {
  switch (currencyCode) {
    case 'BIF':
    case 'CLP':
    case 'DJF':
    case 'GNF':
    case 'ISK':
    case 'JPY':
    case 'KMF':
    case 'KRW':
    case 'PYG':
    case 'RWF':
    case 'UGX':
    case 'UYI':
    case 'VND':
    case 'VUV':
    case 'XAF':
    case 'XOF':
    case 'XPF':
      return 0;
    case 'BHD':
    case 'IQD':
    case 'JOD':
    case 'KWD':
    case 'LYD':
    case 'OMR':
    case 'TND':
      return 3;
    case 'CLF':
    case 'UYW':
      return 4;
    default:
      return 2;
  }
}

int _minorScale(int fractionDigits) {
  var scale = 1;
  for (var i = 0; i < fractionDigits; i++) {
    scale *= 10;
  }
  return scale;
}

/// "Friday 16 October 2026"
String formatLongDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} ${d.year}';

/// Stored UTC ISO string -> "16/10/2026 11:42" in the phone's local time.
String formatLocalDateTime(String? isoUtc) {
  if (isoUtc == null || isoUtc.isEmpty) return '-';
  final parsed = DateTime.tryParse(isoUtc);
  if (parsed == null) return isoUtc;
  final d = parsed.toLocal();
  return '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';
}

/// Stored UTC ISO string -> "16/10/2026" (local date).
String formatLocalDate(String? isoUtc) {
  if (isoUtc == null || isoUtc.isEmpty) return '-';
  final parsed = DateTime.tryParse(isoUtc);
  if (parsed == null) return isoUtc;
  final d = parsed.toLocal();
  return '${_two(d.day)}/${_two(d.month)}/${d.year}';
}

/// "2026-10-16" -> "16/10/2026"
String formatYmd(String? ymd) {
  if (ymd == null || ymd.length < 10) return '-';
  final p = ymd.substring(0, 10).split('-');
  if (p.length != 3) return ymd;
  return '${p[2]}/${p[1]}/${p[0]}';
}

/// "2026-10-16" -> local midnight, or null.
DateTime? parseYmd(String? ymd) => (ymd == null || ymd.length < 10)
    ? null
    : DateTime.tryParse('${ymd.substring(0, 10)}T00:00:00');

/// Monday of the week containing [d], as YYYY-MM-DD.
String weekStartYmd(DateTime d) =>
    formatDate(DateTime(d.year, d.month, d.day - (d.weekday - 1)));

String addDaysYmd(String ymd, int days) {
  final d = parseYmd(ymd) ?? DateTime.now();
  return formatDate(DateTime(d.year, d.month, d.day + days));
}

/// UTC bounds [start, end) covering the local dates startYmd..endYmd inclusive.
/// Used to compare against stored UTC timestamps.
List<String> utcBounds(String startYmd, String endYmd) {
  final s = parseYmd(startYmd) ?? DateTime.now();
  final e = parseYmd(endYmd) ?? s;
  final next = DateTime(e.year, e.month, e.day + 1);
  return [s.toUtc().toIso8601String(), next.toUtc().toIso8601String()];
}

/// "+03:00"
String formatOffset(Duration offset) {
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  return '$sign${_two(abs.inHours)}:${_two(abs.inMinutes.remainder(60))}';
}

/// Money is stored as integer minor units. 123456 -> "1,234.56".
String formatMinor(int? minor, {int fractionDigits = 2}) {
  if (minor == null) return '-';
  final negative = minor < 0;
  final abs = minor.abs();
  final scale = _minorScale(fractionDigits);
  final whole = (abs ~/ scale).toString();
  final fraction = fractionDigits == 0
      ? ''
      : '.${(abs % scale).toString().padLeft(fractionDigits, '0')}';
  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
    buf.write(whole[i]);
  }
  return '${negative ? '-' : ''}$buf$fraction';
}

/// "1,234.56" -> 123456. Empty or invalid -> null.
int? parseMinor(String text, {int fractionDigits = 2}) {
  final t = text.trim().replaceAll(',', '');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || !v.isFinite) return null;
  final minor = v * _minorScale(fractionDigits);
  if (!minor.isFinite) return null;
  final rounded = minor.round();
  return (minor - rounded).abs() < 0.000001 ? rounded : null;
}

double? parseDouble(String text) {
  final t = text.trim().replaceAll(',', '');
  if (t.isEmpty) return null;
  final value = double.tryParse(t);
  return value == null || !value.isFinite ? null : value;
}

/// "not_started" -> "Not started"
String pretty(String? key) {
  if (key == null || key.isEmpty) return '';
  final s = key.replaceAll('_', ' ');
  return s[0].toUpperCase() + s.substring(1);
}

/// 12345 -> "123.45" (for filling a text field).
String minorToText(int? minor, {int fractionDigits = 2}) => minor == null
    ? ''
    : (minor / _minorScale(fractionDigits)).toStringAsFixed(fractionDigits);

/// A number for a text field without trailing ".0".
String numToText(double? v) {
  if (v == null) return '';
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}
