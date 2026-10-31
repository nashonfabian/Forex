import 'dart:math' as math;

enum NaiveTimestampZone { utc, local }

class HistoricalCandle {
  const HistoricalCandle({
    required this.timestampMs,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.tickVolume,
    this.realVolume,
    this.spread,
  });

  final int timestampMs;
  final double open;
  final double high;
  final double low;
  final double close;
  final double? tickVolume;
  final double? realVolume;
  final double? spread;
}

class CsvIssue {
  const CsvIssue(this.line, this.message);

  final int line;
  final String message;

  @override
  String toString() => 'Line $line: $message';
}

class HistoricalCsvResult {
  const HistoricalCsvResult({
    required this.candles,
    required this.errors,
    required this.gapCount,
  });

  final List<HistoricalCandle> candles;
  final List<CsvIssue> errors;
  final int gapCount;

  bool get isValid => errors.isEmpty && candles.isNotEmpty;
}

const historicalTimeframes = <String, int>{
  'M1': 60 * 1000,
  'M5': 5 * 60 * 1000,
  'M15': 15 * 60 * 1000,
  'M30': 30 * 60 * 1000,
  'H1': 60 * 60 * 1000,
  'H4': 4 * 60 * 60 * 1000,
  'D1': 24 * 60 * 60 * 1000,
};

class HistoricalCsvParser {
  const HistoricalCsvParser();

  HistoricalCsvResult parse(
    String csv, {
    required String timeframe,
    NaiveTimestampZone naiveTimestampZone = NaiveTimestampZone.utc,
  }) {
    final interval = historicalTimeframes[timeframe.toUpperCase()];
    if (interval == null) {
      return const HistoricalCsvResult(
        candles: [],
        errors: [CsvIssue(1, 'Unsupported timeframe.')],
        gapCount: 0,
      );
    }

    final rows = _parseRows(csv);
    if (rows.isEmpty) {
      return const HistoricalCsvResult(
        candles: [],
        errors: [CsvIssue(1, 'CSV file is empty.')],
        gapCount: 0,
      );
    }

    final headers = rows.first.fields.map(_normalizeHeader).toList();
    final timestampColumn = _findHeader(headers, const [
      'timestamp',
      'datetime',
      'date time',
      'time stamp',
    ]);
    final dateColumn = _findHeader(headers, const ['date']);
    final timeColumn = _findHeader(headers, const ['time']);
    final openColumn = _findHeader(headers, const ['open', 'o']);
    final highColumn = _findHeader(headers, const ['high', 'h']);
    final lowColumn = _findHeader(headers, const ['low', 'l']);
    final closeColumn = _findHeader(headers, const ['close', 'c', 'last']);
    final tickVolumeColumn = _findHeader(headers, const [
      'tick volume',
      'tickvol',
      'tick_volume',
      'volume ticks',
    ]);
    final realVolumeColumn = _findHeader(headers, const [
      'real volume',
      'real_volume',
      'volume',
    ]);
    final spreadColumn = _findHeader(headers, const ['spread']);

    final errors = <CsvIssue>[];
    if (timestampColumn == null && (dateColumn == null || timeColumn == null)) {
      errors.add(const CsvIssue(
        1,
        'CSV needs a timestamp/datetime column, or separate date and time columns.',
      ));
    }
    for (final entry in <String, int?>{
      'open': openColumn,
      'high': highColumn,
      'low': lowColumn,
      'close': closeColumn,
    }.entries) {
      if (entry.value == null) {
        errors.add(CsvIssue(1, 'Missing required "${entry.key}" column.'));
      }
    }
    if (errors.isNotEmpty) {
      return HistoricalCsvResult(candles: const [], errors: errors, gapCount: 0);
    }

    final candles = <HistoricalCandle>[];
    final seen = <int>{};
    var gapCount = 0;
    int? previousTimestamp;

    for (final row in rows.skip(1)) {
      if (row.fields.every((field) => field.trim().isEmpty)) continue;
      final timestampText = timestampColumn != null
          ? _field(row.fields, timestampColumn)
          : '${_field(row.fields, dateColumn!)} ${_field(row.fields, timeColumn!)}';
      final timestampMs = _parseTimestampMs(timestampText, naiveTimestampZone);
      if (timestampMs == null) {
        errors.add(CsvIssue(row.line, 'Invalid timestamp "$timestampText".'));
        continue;
      }

      final values = <String, double?>{
        'open': _number(_field(row.fields, openColumn!)),
        'high': _number(_field(row.fields, highColumn!)),
        'low': _number(_field(row.fields, lowColumn!)),
        'close': _number(_field(row.fields, closeColumn!)),
      };
      final invalidValue = values.entries.firstWhere(
        (entry) => entry.value == null || !entry.value!.isFinite,
        orElse: () => const MapEntry('', 0),
      );
      if (invalidValue.key.isNotEmpty) {
        errors.add(CsvIssue(row.line, 'Invalid ${invalidValue.key} price.'));
        continue;
      }

      final open = values['open']!;
      final high = values['high']!;
      final low = values['low']!;
      final close = values['close']!;
      if (open <= 0 ||
          high <= 0 ||
          low <= 0 ||
          close <= 0 ||
          high < math.max(open, math.max(close, low)) ||
          low > math.min(open, math.min(close, high))) {
        errors.add(CsvIssue(row.line, 'OHLC values are inconsistent or non-positive.'));
        continue;
      }

      final tickVolume = _optionalNumber(row, tickVolumeColumn, 'tick volume', errors);
      final realVolume = _optionalNumber(row, realVolumeColumn, 'real volume', errors);
      final spread = _optionalNumber(row, spreadColumn, 'spread', errors);
      if (errors.isNotEmpty && errors.last.line == row.line) continue;

      if (!seen.add(timestampMs)) {
        errors.add(CsvIssue(row.line, 'Duplicate candle timestamp.'));
        continue;
      }
      if (previousTimestamp != null) {
        if (timestampMs < previousTimestamp) {
          errors.add(CsvIssue(row.line, 'Rows are not in chronological order.'));
          continue;
        }
        if (timestampMs - previousTimestamp > interval * 3 ~/ 2) {
          gapCount++;
        }
      }

      candles.add(HistoricalCandle(
        timestampMs: timestampMs,
        open: open,
        high: high,
        low: low,
        close: close,
        tickVolume: tickVolume,
        realVolume: realVolume,
        spread: spread,
      ));
      previousTimestamp = timestampMs;
    }

    if (candles.isEmpty && errors.isEmpty) {
      errors.add(const CsvIssue(1, 'CSV contains no candle rows.'));
    }
    return HistoricalCsvResult(
      candles: List.unmodifiable(candles),
      errors: List.unmodifiable(errors),
      gapCount: gapCount,
    );
  }

  double? _optionalNumber(
    _CsvRow row,
    int? column,
    String label,
    List<CsvIssue> errors,
  ) {
    if (column == null) return null;
    final text = _field(row.fields, column);
    if (text.isEmpty) return null;
    final value = _number(text);
    if (value == null || !value.isFinite || value < 0) {
      errors.add(CsvIssue(row.line, 'Invalid $label value.'));
      return null;
    }
    return value;
  }

  int? _parseTimestampMs(String text, NaiveTimestampZone naiveZone) {
    final value = text.trim();
    if (value.isEmpty) return null;
    final hasOffset = RegExp(r'[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false)
        .hasMatch(value);
    final isoInput = value.replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse(isoInput);
    if (parsed != null) {
      final date = hasOffset ? parsed.toUtc() : (naiveZone == NaiveTimestampZone.utc
          ? DateTime.utc(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.minute, parsed.second, parsed.millisecond, parsed.microsecond)
          : parsed.toLocal());
      return date.millisecondsSinceEpoch;
    }

    final match = RegExp(
      r'^(\d{4})[./-](\d{1,2})[./-](\d{1,2})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?$',
    ).firstMatch(value);
    final dayFirst = match == null
        ? RegExp(
            r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?$',
          ).firstMatch(value)
        : null;
    final parts = match ?? dayFirst;
    if (parts == null) return null;
    final year = int.parse(dayFirst == null ? parts[1]! : parts[3]!);
    final month = int.parse(parts[dayFirst == null ? 2 : 2]!);
    final day = int.parse(dayFirst == null ? parts[3]! : parts[1]!);
    final hour = int.parse(parts[4]!);
    final minute = int.parse(parts[5]!);
    final second = int.tryParse(parts[6] ?? '') ?? 0;
    final date = naiveZone == NaiveTimestampZone.utc
        ? DateTime.utc(year, month, day, hour, minute, second)
        : DateTime(year, month, day, hour, minute, second);
    if (date.year != year || date.month != month || date.day != day) return null;
    return date.millisecondsSinceEpoch;
  }

  double? _number(String value) {
    final normalized = value.trim().replaceAll(',', '');
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  int? _findHeader(List<String> headers, List<String> aliases) {
    final wanted = aliases.map(_normalizeHeader).toSet();
    final index = headers.indexWhere(wanted.contains);
    return index < 0 ? null : index;
  }

  String _normalizeHeader(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[_-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ');

  String _field(List<String> fields, int index) => index < fields.length ? fields[index].trim() : '';

  List<_CsvRow> _parseRows(String input) {
    final rows = <_CsvRow>[];
    var delimiter = ',';
    final firstLine = input.split(RegExp(r'\r?\n')).first;
    final candidates = [',', ';', '\t'];
    delimiter = candidates.reduce((a, b) => _countOutsideQuotes(firstLine, b) > _countOutsideQuotes(firstLine, a) ? b : a);

    var fields = <String>[];
    final field = StringBuffer();
    var quoted = false;
    var line = 1;
    var rowLine = 1;
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (char == '"') {
        if (quoted && i + 1 < input.length && input[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == delimiter && !quoted) {
        fields.add(field.toString());
        field.clear();
      } else if ((char == '\n' || char == '\r') && !quoted) {
        if (char == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
        fields.add(field.toString());
        field.clear();
        rows.add(_CsvRow(rowLine, fields));
        fields = <String>[];
        line++;
        rowLine = line;
      } else {
        field.write(char);
        if (char == '\n') line++;
      }
    }
    if (quoted) return rows;
    if (fields.isNotEmpty || field.isNotEmpty) {
      fields.add(field.toString());
      rows.add(_CsvRow(rowLine, fields));
    }
    return rows;
  }

  int _countOutsideQuotes(String text, String delimiter) {
    var quoted = false;
    var count = 0;
    for (var i = 0; i < text.length; i++) {
      if (text[i] == '"') {
        quoted = !quoted;
      } else if (!quoted && text[i] == delimiter) {
        count++;
      }
    }
    return count;
  }
}

class _CsvRow {
  const _CsvRow(this.line, this.fields);

  final int line;
  final List<String> fields;
}
