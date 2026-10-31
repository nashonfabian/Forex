import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';
import '../../core/ids.dart';
import '../../core/rows.dart';
import 'base_repository.dart';
import 'historical_csv.dart';

class DatasetImportResult {
  const DatasetImportResult({
    required this.validation,
    this.datasetId,
  });

  final HistoricalCsvResult validation;
  final String? datasetId;

  bool get imported => datasetId != null;
}

class HistoricalDataRepository extends BaseRepository {
  HistoricalDataRepository(super.app, super.changes, super.clock);

  final HistoricalCsvParser _parser = const HistoricalCsvParser();

  Future<DatasetImportResult> importCsv({
    required String csv,
    required String instrument,
    required String timeframe,
    required String sourceName,
    NaiveTimestampZone naiveTimestampZone = NaiveTimestampZone.utc,
  }) async {
    final normalizedInstrument = instrument.trim().toUpperCase();
    if (normalizedInstrument.isEmpty) {
      return const DatasetImportResult(
        validation: HistoricalCsvResult(
          candles: [],
          errors: [CsvIssue(1, 'Instrument is required.')],
          gapCount: 0,
        ),
      );
    }

    final validation = _parser.parse(
      csv,
      timeframe: timeframe,
      naiveTimestampZone: naiveTimestampZone,
    );
    if (!validation.isValid) return DatasetImportResult(validation: validation);

    final datasetId = newId();
    final now = clock.nowIso();
    final timezoneMode = switch (naiveTimestampZone) {
      NaiveTimestampZone.utc => 'utc',
      NaiveTimestampZone.local => 'local',
    };
    final digest = sha256.convert(utf8.encode(csv)).toString();
    await write(
      const ['historical_datasets', 'historical_candles'],
      (txn, _) async {
        await txn.insert('historical_datasets', {
          'id': datasetId,
          'instrument': normalizedInstrument,
          'timeframe': timeframe.toUpperCase(),
          'source_name': sourceName,
          'timezone_mode': timezoneMode,
          'first_timestamp_ms': validation.candles.first.timestampMs,
          'last_timestamp_ms': validation.candles.last.timestampMs,
          'candle_count': validation.candles.length,
          'gap_count': validation.gapCount,
          'sha256': digest,
          'created_at': now,
        });
        final batch = txn.batch();
        for (final candle in validation.candles) {
          batch.insert('historical_candles', {
            'dataset_id': datasetId,
            'timestamp_ms': candle.timestampMs,
            'open': candle.open,
            'high': candle.high,
            'low': candle.low,
            'close': candle.close,
            'tick_volume': candle.tickVolume,
            'real_volume': candle.realVolume,
            'spread': candle.spread,
          });
        }
        await batch.commit(noResult: true);
        return datasetId;
      },
    );
    return DatasetImportResult(validation: validation, datasetId: datasetId);
  }

  Future<List<Rec>> datasets() async => (await db).query(
        'historical_datasets',
        orderBy: 'created_at DESC, id',
      );

  /// Returns only candles at or before [throughTimestampMs], newest bars first
  /// internally and in chronological order for chart rendering.
  Future<List<Rec>> candlesUpTo({
    required String datasetId,
    required int throughTimestampMs,
    int limit = 500,
  }) async {
    if (limit < 1 || limit > 5000) {
      throw RangeError.range(limit, 1, 5000, 'limit');
    }
    return (await db).rawQuery(
      '''
      SELECT * FROM (
        SELECT timestamp_ms, open, high, low, close,
               tick_volume, real_volume, spread
        FROM historical_candles
        WHERE dataset_id = ? AND timestamp_ms <= ?
        ORDER BY timestamp_ms DESC
        LIMIT ?
      )
      ORDER BY timestamp_ms ASC
      ''',
      [datasetId, throughTimestampMs, limit],
    );
  }

  Future<Rec?> nextCandle(String datasetId, int afterTimestampMs) async =>
      _firstCandle(
        'dataset_id = ? AND timestamp_ms > ?',
        [datasetId, afterTimestampMs],
        'timestamp_ms ASC',
      );

  Future<Rec?> previousCandle(String datasetId, int beforeTimestampMs) async =>
      _firstCandle(
        'dataset_id = ? AND timestamp_ms < ?',
        [datasetId, beforeTimestampMs],
        'timestamp_ms DESC',
      );

  Future<Rec?> _firstCandle(String where, List<Object?> args, String orderBy) async {
    final rows = await (await db).query(
      'historical_candles',
      columns: const [
        'timestamp_ms',
        'open',
        'high',
        'low',
        'close',
        'tick_volume',
        'real_volume',
        'spread',
      ],
      where: where,
      whereArgs: args,
      orderBy: orderBy,
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<String> createReplaySession({
    required String datasetId,
    required int requestedStartTimestampMs,
    double speedCandlesPerSecond = 1,
  }) async {
    if (!speedCandlesPerSecond.isFinite || speedCandlesPerSecond <= 0) {
      throw ArgumentError.value(speedCandlesPerSecond, 'speedCandlesPerSecond');
    }
    final database = await db;
    final starts = await database.query(
      'historical_candles',
      columns: const ['timestamp_ms'],
      where: 'dataset_id = ? AND timestamp_ms >= ?',
      whereArgs: [datasetId, requestedStartTimestampMs],
      orderBy: 'timestamp_ms ASC',
      limit: 1,
    );
    if (starts.isEmpty) {
      throw StateError('No candle exists at or after the selected replay start.');
    }
    final id = newId();
    final now = clock.nowIso();
    await write(
      const ['replay_sessions'],
      (txn, _) async {
        await txn.insert('replay_sessions', {
          'id': id,
          'dataset_id': datasetId,
          'start_timestamp_ms': starts.first['timestamp_ms'],
          'cursor_timestamp_ms': starts.first['timestamp_ms'],
          'speed_candles_per_second': speedCandlesPerSecond,
          'created_at': now,
          'updated_at': now,
        });
        return id;
      },
    );
    return id;
  }

  Future<Rec?> replaySession(String sessionId) async {
    final rows = await (await db).query(
      'replay_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Rec>> visibleCandles(
    String sessionId, {
    int limit = 500,
  }) async {
    if (limit < 1 || limit > 5000) {
      throw RangeError.range(limit, 1, 5000, 'limit');
    }
    return (await db).rawQuery(
      '''
      SELECT * FROM (
        SELECT c.timestamp_ms, c.open, c.high, c.low, c.close,
               c.tick_volume, c.real_volume, c.spread
        FROM historical_candles AS c
        JOIN replay_sessions AS r ON r.dataset_id = c.dataset_id
        WHERE r.id = ? AND c.timestamp_ms <= r.cursor_timestamp_ms
        ORDER BY c.timestamp_ms DESC
        LIMIT ?
      )
      ORDER BY timestamp_ms ASC
      ''',
      [sessionId, limit],
    );
  }

  Future<Rec?> stepReplay(String sessionId, {required bool forward}) async {
    final session = await replaySession(sessionId);
    if (session == null) return null;
    final datasetId = session['dataset_id']! as String;
    final cursor = session['cursor_timestamp_ms']! as int;
    final candle = forward
        ? await nextCandle(datasetId, cursor)
        : await previousCandle(datasetId, cursor);
    if (candle == null) return null;
    final candleTimestamp = candle['timestamp_ms']! as int;
    final startTimestamp = session['start_timestamp_ms']! as int;
    if (!forward && candleTimestamp < startTimestamp) return null;
    await saveReplayCursor(sessionId, candleTimestamp);
    return candle;
  }

  Future<void> saveReplayCursor(String sessionId, int timestampMs) async {
    final session = await replaySession(sessionId);
    if (session == null) throw StateError('Replay session not found.');
    final datasetId = session['dataset_id']! as String;
    final startTimestamp = session['start_timestamp_ms']! as int;
    if (timestampMs < startTimestamp) {
      throw RangeError('Replay cursor cannot move before the session start.');
    }
    final matches = await (await db).query(
      'historical_candles',
      columns: const ['timestamp_ms'],
      where: 'dataset_id = ? AND timestamp_ms = ?',
      whereArgs: [datasetId, timestampMs],
      limit: 1,
    );
    if (matches.isEmpty) throw ArgumentError.value(timestampMs, 'timestampMs');
    await write(
      const ['replay_sessions'],
      (txn, now) async {
        await txn.update(
          'replay_sessions',
          {'cursor_timestamp_ms': timestampMs, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [sessionId],
        );
      },
    );
  }

  Future<void> saveReplaySpeed(String sessionId, double speed) async {
    if (!speed.isFinite || speed <= 0) throw ArgumentError.value(speed, 'speed');
    await write(
      const ['replay_sessions'],
      (txn, now) async {
        final changed = await txn.update(
          'replay_sessions',
          {'speed_candles_per_second': speed, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [sessionId],
        );
        if (changed == 0) throw StateError('Replay session not found.');
      },
    );
  }

  Future<Database> get database => db;
}
