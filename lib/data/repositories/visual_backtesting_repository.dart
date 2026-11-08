import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';
import '../../core/db/app_database.dart';
import '../../core/db/table_changes.dart';
import '../../core/ids.dart';
import '../../core/rows.dart';

const visualTradingSessions = [
  'Sydney',
  'Tokyo',
  'London',
  'New York',
  'Other'
];
const visualOutcomes = ['pending', 'win', 'loss', 'breakeven', 'inconclusive'];
const visualAnnotationKinds = [
  'entry',
  'stop_loss',
  'take_profit',
  'exit',
  'observation',
];
const visualBacktestingTables = [
  'visual_strategies',
  'visual_tests',
  'visual_test_images',
  'visual_annotations',
];

String? validateVisualStrategy({
  required String name,
  required String entryConditions,
  required String exitConditions,
  required String stopLossRules,
  required String takeProfitRules,
  required String stayOutConditions,
  required List<String> sessions,
  required List<String> timeframes,
}) {
  if (name.trim().isEmpty) {
    return 'Enter a strategy name.';
  }
  if (entryConditions.trim().isEmpty) {
    return 'Enter the strategy entry conditions.';
  }
  if (exitConditions.trim().isEmpty) {
    return 'Enter the strategy exit conditions.';
  }
  if (stopLossRules.trim().isEmpty) {
    return 'Enter the strategy stop-loss rules.';
  }
  if (takeProfitRules.trim().isEmpty) {
    return 'Enter the strategy take-profit rules.';
  }
  if (stayOutConditions.trim().isEmpty) {
    return 'Enter conditions for staying out of the market.';
  }
  if (sessions.isEmpty) return 'Choose at least one trading session.';
  if (sessions.any((value) => !visualTradingSessions.contains(value))) {
    return 'Choose valid trading sessions.';
  }
  if (timeframes.isEmpty) return 'Choose at least one timeframe.';
  if (timeframes.any((value) => !visualTimeframes.contains(value))) {
    return 'Choose valid timeframes.';
  }
  return null;
}

const visualTimeframes = ['1M', '5M', '15M', '30M', '1H', '4H', '1D'];

String? validateVisualOutcome(String outcome, double? resultR) {
  if (!visualOutcomes.contains(outcome)) return 'Choose a valid setup outcome.';
  if (resultR != null && !resultR.isFinite) {
    return 'R-multiple must be a finite number.';
  }
  if (outcome == 'win' && resultR != null && resultR <= 0) {
    return 'A win must have a positive R-multiple.';
  }
  if (outcome == 'loss' && resultR != null && resultR >= 0) {
    return 'A loss must have a negative R-multiple.';
  }
  if (outcome == 'breakeven' && resultR != null && resultR != 0) {
    return 'A breakeven result must have an R-multiple of zero.';
  }
  if ((outcome == 'pending' || outcome == 'inconclusive') && resultR != null) {
    return 'Pending or inconclusive tests cannot have a result R-multiple.';
  }
  return null;
}

class VisualBacktestStats {
  const VisualBacktestStats({
    required this.testCount,
    required this.wins,
    required this.losses,
    required this.breakeven,
    required this.winRate,
    required this.meanR,
    required this.rSampleCount,
    required this.maxDrawdownR,
  });

  final int testCount;
  final int wins;
  final int losses;
  final int breakeven;
  final double? winRate;
  final double? meanR;
  final int rSampleCount;
  final double? maxDrawdownR;

  factory VisualBacktestStats.fromTests(Iterable<Rec> tests) {
    final completed = tests
        .where((test) =>
            test.s('outcome') == 'win' ||
            test.s('outcome') == 'loss' ||
            test.s('outcome') == 'breakeven')
        .toList()
      ..sort((a, b) {
        final byTestedAt = a.s('tested_at').compareTo(b.s('tested_at'));
        if (byTestedAt != 0) return byTestedAt;
        return a.s('created_at').compareTo(b.s('created_at'));
      });
    final wins = completed.where((test) => test.s('outcome') == 'win').length;
    final losses =
        completed.where((test) => test.s('outcome') == 'loss').length;
    final breakeven =
        completed.where((test) => test.s('outcome') == 'breakeven').length;
    final rValues = completed
        .map((test) => test['result_r'])
        .whereType<num>()
        .map((value) => value.toDouble())
        .where((value) => value.isFinite)
        .toList();

    double? maxDrawdown;
    if (completed.isNotEmpty &&
        rValues.length == completed.length &&
        rValues.isNotEmpty) {
      var equity = 0.0;
      var peak = 0.0;
      var maximum = 0.0;
      for (final value in rValues) {
        equity += value;
        if (equity > peak) peak = equity;
        final drawdown = peak - equity;
        if (drawdown > maximum) maximum = drawdown;
      }
      maxDrawdown = maximum;
    }

    return VisualBacktestStats(
      testCount: completed.length,
      wins: wins,
      losses: losses,
      breakeven: breakeven,
      winRate: wins + losses == 0 ? null : wins / (wins + losses),
      meanR: rValues.isEmpty
          ? null
          : rValues.reduce((a, b) => a + b) / rValues.length,
      rSampleCount: rValues.length,
      maxDrawdownR: maxDrawdown,
    );
  }
}

class VisualBacktestingRepository {
  VisualBacktestingRepository(this._app, this._changes, this._clock);

  final AppDatabase _app;
  final TableChanges _changes;
  final Clock _clock;

  Future<Database> get _db => _app.db;

  Future<void> _write(
    Future<void> Function(Transaction txn, String now) action,
  ) async {
    final now = _clock.nowIso();
    await (await _db).transaction((txn) => action(txn, now));
    _changes.notify(visualBacktestingTables);
  }

  Future<List<Rec>> strategies() async => (await _db).query(
        'visual_strategies',
        where: 'deleted_at IS NULL',
        orderBy: 'updated_at DESC, name COLLATE NOCASE',
      );

  Stream<List<Rec>> watchStrategies() => watchQuery(
        _changes,
        {'visual_strategies'},
        strategies,
      );

  Future<Rec?> strategyById(String id) async {
    final rows = await (await _db).query(
      'visual_strategies',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<String> saveStrategy({
    String? id,
    required String name,
    required String entryConditions,
    required String exitConditions,
    required String stopLossRules,
    required String takeProfitRules,
    required String stayOutConditions,
    required List<String> sessions,
    required List<String> timeframes,
  }) async {
    final error = validateVisualStrategy(
      name: name,
      entryConditions: entryConditions,
      exitConditions: exitConditions,
      stopLossRules: stopLossRules,
      takeProfitRules: takeProfitRules,
      stayOutConditions: stayOutConditions,
      sessions: sessions,
      timeframes: timeframes,
    );
    if (error != null) throw StateError(error);

    final strategyId = id ?? newId();
    final values = <String, Object?>{
      'name': name.trim(),
      'entry_conditions': entryConditions.trim(),
      'exit_conditions': exitConditions.trim(),
      'stop_loss_rules': stopLossRules.trim(),
      'take_profit_rules': takeProfitRules.trim(),
      'stay_out_conditions': stayOutConditions.trim(),
      'sessions_json': jsonEncode(sessions.toSet().toList()),
      'timeframes_json': jsonEncode(timeframes.toSet().toList()),
    };
    await _write((txn, now) async {
      final existing = id == null
          ? const <Rec>[]
          : await txn.query(
              'visual_strategies',
              columns: const ['id'],
              where: 'id = ? AND deleted_at IS NULL',
              whereArgs: [id],
              limit: 1,
            );
      if (id != null && existing.isEmpty) {
        throw StateError('Strategy not found.');
      }
      if (id == null) {
        await txn.insert('visual_strategies', {
          ...values,
          'id': strategyId,
          'created_at': now,
          'updated_at': now,
        });
      } else {
        await txn.update(
          'visual_strategies',
          {...values, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [strategyId],
        );
      }
    });
    return strategyId;
  }

  Future<void> archiveStrategy(String id) => _write((txn, now) async {
        final changed = await txn.update(
          'visual_strategies',
          {'deleted_at': now, 'updated_at': now},
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [id],
        );
        if (changed == 0) throw StateError('Strategy not found.');
      });

  Future<List<Rec>> tests({String? strategyId, int limit = 500}) async {
    final where = <String>['t.deleted_at IS NULL'];
    final args = <Object?>[];
    if (strategyId != null) {
      where.add('t.strategy_id = ?');
      args.add(strategyId);
    }
    args.add(limit);
    return (await _db).rawQuery(
      '''
      SELECT t.*, t.strategy_name_snapshot AS strategy_name,
             (SELECT COUNT(*) FROM visual_test_images ti WHERE ti.test_id = t.id) AS image_count
      FROM visual_tests t
      JOIN visual_strategies s ON s.id = t.strategy_id
      WHERE ${where.join(' AND ')}
      ORDER BY t.tested_at DESC, t.created_at DESC
      LIMIT ?
      ''',
      args,
    );
  }

  Stream<List<Rec>> watchTests({String? strategyId}) => watchQuery(
        _changes,
        {'visual_tests', 'visual_test_images', 'visual_strategies'},
        () => tests(strategyId: strategyId),
      );

  Future<List<Rec>> testResults() async => (await _db).query(
        'visual_tests',
        columns: const [
          'strategy_id',
          'tested_at',
          'outcome',
          'result_r',
          'created_at',
        ],
        where: 'deleted_at IS NULL',
        orderBy: 'tested_at, created_at',
      );

  Stream<List<Rec>> watchTestResults() => watchQuery(
        _changes,
        {'visual_tests'},
        testResults,
      );

  Future<Rec?> testById(String id) async {
    final rows = await (await _db).rawQuery(
      '''
      SELECT t.*, t.strategy_name_snapshot AS strategy_name
      FROM visual_tests t
      JOIN visual_strategies s ON s.id = t.strategy_id
      WHERE t.id = ? AND t.deleted_at IS NULL
      LIMIT 1
      ''',
      [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Rec>> imagesForTest(String testId) async => (await _db).rawQuery(
        '''
        SELECT i.*, f.local_path AS local_path, ti.sort_order
        FROM visual_test_images ti
        JOIN images i ON i.id = ti.image_id
        LEFT JOIN image_files f ON f.image_id = i.id
        WHERE ti.test_id = ? AND i.deleted_at IS NULL
        ORDER BY ti.sort_order, i.created_at
        ''',
        [testId],
      );

  Future<List<Rec>> annotationsForTest(String testId) async =>
      (await _db).query(
        'visual_annotations',
        where: 'test_id = ?',
        whereArgs: [testId],
        orderBy: 'created_at, id',
      );

  Future<String> saveTest({
    String? id,
    required String strategyId,
    required String testedAt,
    required String outcome,
    required double? resultR,
    required String notes,
    required List<String> imageIds,
    required Map<String, List<Rec>> annotationsByImage,
  }) async {
    final error = validateVisualOutcome(outcome, resultR);
    if (error != null) throw StateError(error);
    if (DateTime.tryParse(testedAt) == null) {
      throw StateError('Choose a valid test date.');
    }
    if (imageIds.isEmpty) {
      throw StateError('Select at least one chart screenshot.');
    }
    final uniqueImageIds = imageIds.toSet().toList();
    if (annotationsByImage.keys
        .any((imageId) => !uniqueImageIds.contains(imageId))) {
      throw StateError(
          'Remove chart marks from screenshots not selected for this test.');
    }
    for (final entry in annotationsByImage.entries) {
      _validateAnnotations(entry.value);
    }
    final testId = id ?? newId();

    await _write((txn, now) async {
      final strategies = await txn.query(
        'visual_strategies',
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [strategyId],
        limit: 1,
      );
      if (strategies.isEmpty) throw StateError('Strategy not found.');

      late String snapshotJson;
      late String strategyName;
      if (id != null) {
        final existing = await txn.query(
          'visual_tests',
          columns: const [
            'strategy_id',
            'strategy_name_snapshot',
            'strategy_snapshot_json',
          ],
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [id],
          limit: 1,
        );
        if (existing.isEmpty) throw StateError('Visual test not found.');
        final previous = existing.first;
        if (previous.s('strategy_id') != strategyId) {
          throw StateError(
              'A saved test cannot be reassigned to another strategy.');
        }
        snapshotJson = previous.s('strategy_snapshot_json');
        strategyName = previous.s('strategy_name_snapshot');
      } else {
        final strategy = strategies.first;
        strategyName = strategy.s('name');
        snapshotJson = jsonEncode({
          'name': strategyName,
          'entry_conditions': strategy.s('entry_conditions'),
          'exit_conditions': strategy.s('exit_conditions'),
          'stop_loss_rules': strategy.s('stop_loss_rules'),
          'take_profit_rules': strategy.s('take_profit_rules'),
          'stay_out_conditions': strategy.s('stay_out_conditions'),
          'sessions_json': strategy.s('sessions_json'),
          'timeframes_json': strategy.s('timeframes_json'),
        });
      }

      for (final imageId in uniqueImageIds) {
        final image = await txn.query(
          'images',
          columns: const ['id'],
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [imageId],
          limit: 1,
        );
        if (image.isEmpty) {
          throw StateError('A selected screenshot is unavailable.');
        }
      }

      final values = <String, Object?>{
        'strategy_id': strategyId,
        'strategy_name_snapshot': strategyName,
        'strategy_snapshot_json': snapshotJson,
        'tested_at': DateTime.parse(testedAt).toUtc().toIso8601String(),
        'outcome': outcome,
        'result_r': resultR,
        'notes': notes.trim().isEmpty ? null : notes.trim(),
        'updated_at': now,
      };
      if (id == null) {
        await txn.insert('visual_tests', {
          ...values,
          'id': testId,
          'created_at': now,
        });
      } else {
        await txn.update(
          'visual_tests',
          values,
          where: 'id = ?',
          whereArgs: [testId],
        );
      }

      await txn.delete(
        'visual_test_images',
        where: 'test_id = ?',
        whereArgs: [testId],
      );
      final placeholders = List.filled(uniqueImageIds.length, '?').join(', ');
      await txn.delete(
        'visual_annotations',
        where: 'test_id = ? AND image_id NOT IN ($placeholders)',
        whereArgs: [testId, ...uniqueImageIds],
      );
      for (var index = 0; index < uniqueImageIds.length; index++) {
        await txn.insert('visual_test_images', {
          'id': newId(),
          'test_id': testId,
          'image_id': uniqueImageIds[index],
          'sort_order': index,
        });
      }
      for (final imageId in uniqueImageIds) {
        await txn.delete(
          'visual_annotations',
          where: 'test_id = ? AND image_id = ?',
          whereArgs: [testId, imageId],
        );
        for (final annotation in annotationsByImage[imageId] ?? const <Rec>[]) {
          await txn.insert('visual_annotations', {
            'id': newId(),
            'test_id': testId,
            'image_id': imageId,
            'kind': annotation['kind'],
            'x': (annotation['x'] as num).toDouble(),
            'y': (annotation['y'] as num).toDouble(),
            'price': (annotation['price'] as num?)?.toDouble(),
            'label': (annotation['label'] as String?)?.trim(),
            'created_at': now,
          });
        }
      }
    });
    return testId;
  }

  void _validateAnnotations(List<Rec> annotations) {
    for (final annotation in annotations) {
      final kind = annotation['kind'];
      final x = annotation['x'];
      final y = annotation['y'];
      final price = annotation['price'];
      if (!visualAnnotationKinds.contains(kind) ||
          x is! num ||
          y is! num ||
          !x.isFinite ||
          !y.isFinite ||
          x < 0 ||
          x > 1 ||
          y < 0 ||
          y > 1 ||
          (price != null && (price is! num || !price.isFinite))) {
        throw const FormatException('A chart annotation has invalid data.');
      }
      if (kind == 'observation' &&
          (annotation['label'] as String? ?? '').trim().isEmpty) {
        throw const FormatException('An observation needs a note.');
      }
    }
  }

  Future<void> deleteTest(String id) => _write((txn, now) async {
        final changed = await txn.update(
          'visual_tests',
          {'deleted_at': now, 'updated_at': now},
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [id],
        );
        if (changed == 0) throw StateError('Visual test not found.');
      });
}
