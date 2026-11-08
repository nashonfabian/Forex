import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';
import '../../core/db/app_database.dart';
import '../../core/db/table_changes.dart';
import '../../core/ids.dart';
import '../../core/rows.dart';
import '../backtesting/strategy_definition.dart';

const visualTradingSessions = [
  'Sydney',
  'Tokyo',
  'London',
  'New York',
  'Other'
];
const visualOutcomes = [
  'pending',
  'win',
  'loss',
  'breakeven',
  'inconclusive',
  'not_traded',
];
const visualAnnotationKinds = [
  'entry',
  'stop_loss',
  'take_profit',
  'exit',
  'observation',
];
const visualBacktestingTables = [
  'visual_strategies',
  'visual_strategy_versions',
  'visual_experiments',
  'visual_experiment_variants',
  'visual_tests',
  'visual_test_images',
  'visual_annotations',
  'visual_test_rule_events',
  'visual_test_events',
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
  if (timeframes
      .map(canonicalVisualTimeframe)
      .any((value) => !visualTimeframes.contains(value))) {
    return 'Choose valid timeframes.';
  }
  return null;
}

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
  if ((outcome == 'pending' ||
          outcome == 'inconclusive' ||
          outcome == 'not_traded') &&
      resultR != null) {
    return 'Incomplete or non-trade tests cannot have a result R-multiple.';
  }
  return null;
}

class VisualBacktestStats {
  const VisualBacktestStats({
    required this.totalSetups,
    required this.validEntries,
    required this.rejectedSetups,
    required this.skippedTrades,
    required this.invalidatedSetups,
    required this.testCount,
    required this.incompleteCount,
    required this.wins,
    required this.losses,
    required this.breakeven,
    required this.winRate,
    required this.meanR,
    required this.totalR,
    required this.profitFactorR,
    required this.profitFactorCash,
    required this.cashSampleCount,
    required this.cashCurrency,
    required this.rSampleCount,
    required this.missingRSampleCount,
    required this.maxDrawdownR,
    required this.ruleAdherenceRate,
    required this.ruleAdherenceSampleCount,
    required this.missingAdherenceSampleCount,
    required this.ruleViolationCount,
  });

  final int totalSetups;
  final int validEntries;
  final int rejectedSetups;
  final int skippedTrades;
  final int invalidatedSetups;
  final int testCount;
  final int incompleteCount;
  final int wins;
  final int losses;
  final int breakeven;
  final double? winRate;
  final double? meanR;
  final double? totalR;
  final double? profitFactorR;
  final double? profitFactorCash;
  final int cashSampleCount;
  final String? cashCurrency;
  final int rSampleCount;
  final int missingRSampleCount;
  final double? maxDrawdownR;
  final double? ruleAdherenceRate;
  final int ruleAdherenceSampleCount;
  final int missingAdherenceSampleCount;
  final int ruleViolationCount;

  factory VisualBacktestStats.fromTests(Iterable<Rec> tests) {
    final allTests = tests.toList();
    final completed = allTests
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
    final positiveR = rValues.where((value) => value > 0).fold<double>(
          0,
          (sum, value) => sum + value,
        );
    final cashResults = completed
        .where((test) => test['result_cash'] is num)
        .toList();
    final cashCurrencies =
        cashResults.map((test) => test.s('result_currency')).toSet();
    final comparableCashResults = cashCurrencies.length == 1
        ? cashResults
            .map((test) => (test['result_cash'] as num).toDouble())
            .toList()
        : const <double>[];
    final positiveCash = comparableCashResults
        .where((value) => value > 0)
        .fold<double>(0, (sum, value) => sum + value);
    final negativeCash = comparableCashResults
        .where((value) => value < 0)
        .fold<double>(0, (sum, value) => sum + value.abs());
    final negativeR = rValues.where((value) => value < 0).fold<double>(
          0,
          (sum, value) => sum + value.abs(),
        );
    final adherent = allTests
        .where((test) =>
            test.s('rule_adherence') == 'followed' ||
            test.s('rule_adherence') == 'violated')
        .toList();
    final followed =
        adherent.where((test) => test.s('rule_adherence') == 'followed').length;
    final violations =
        adherent.where((test) => test.s('rule_adherence') == 'violated').length;
    final outcomesWithoutR = completed.length - rValues.length;

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
      totalSetups: allTests.length,
      validEntries: allTests
          .where((test) => test.s('entry_decision') == 'valid_entry')
          .length,
      rejectedSetups: allTests
          .where((test) => test.s('entry_decision') == 'rejected_setup')
          .length,
      skippedTrades: allTests
          .where((test) => test.s('entry_decision') == 'skipped_trade')
          .length,
      invalidatedSetups: allTests
          .where((test) => test.s('entry_decision') == 'invalidated_setup')
          .length,
      testCount: completed.length,
      incompleteCount: allTests
          .where((test) =>
              test.s('outcome') == 'pending' ||
              test.s('outcome') == 'inconclusive')
          .length,
      wins: wins,
      losses: losses,
      breakeven: breakeven,
      winRate: wins + losses == 0 ? null : wins / (wins + losses),
      meanR: rValues.isEmpty
          ? null
          : rValues.reduce((a, b) => a + b) / rValues.length,
      totalR: rValues.isEmpty ? null : rValues.reduce((a, b) => a + b),
      profitFactorR: outcomesWithoutR != 0 || negativeR == 0
          ? null
          : positiveR / negativeR,
      profitFactorCash: cashResults.length != completed.length ||
              cashCurrencies.length != 1 ||
              negativeCash == 0
          ? null
          : positiveCash / negativeCash,
      cashSampleCount: cashResults.length,
      cashCurrency:
          cashCurrencies.length == 1 ? cashCurrencies.first : null,
      rSampleCount: rValues.length,
      missingRSampleCount: outcomesWithoutR,
      maxDrawdownR: maxDrawdown,
      ruleAdherenceRate: adherent.isEmpty ? null : followed / adherent.length,
      ruleAdherenceSampleCount: adherent.length,
      missingAdherenceSampleCount: completed.length - adherent.length,
      ruleViolationCount: violations,
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

  Future<List<Rec>> strategyVersions(String strategyId) async =>
      (await _db).query(
        'visual_strategy_versions',
        where: 'strategy_id = ?',
        whereArgs: [strategyId],
        orderBy: 'version_number DESC, created_at DESC',
      );

  Stream<List<Rec>> watchStrategyVersions(String strategyId) => watchQuery(
        _changes,
        {'visual_strategy_versions'},
        () => strategyVersions(strategyId),
      );

  Future<List<Rec>> experiments() async => (await _db).rawQuery(
        '''
        SELECT e.*, v.name AS baseline_name,
               v.version_number AS baseline_version_number
        FROM visual_experiments e
        JOIN visual_strategy_versions v ON v.id = e.baseline_version_id
        WHERE e.deleted_at IS NULL
        ORDER BY e.updated_at DESC, e.name COLLATE NOCASE
        ''',
      );

  Stream<List<Rec>> watchExperiments() => watchQuery(
        _changes,
        {'visual_experiments', 'visual_experiment_variants'},
        experiments,
      );

  Future<List<Rec>> experimentVariants(String experimentId) async =>
      (await _db).rawQuery(
        '''
        SELECT v.*, sv.name AS strategy_name,
               sv.version_number AS strategy_version_number
        FROM visual_experiment_variants v
        JOIN visual_strategy_versions sv ON sv.id = v.strategy_version_id
        WHERE v.experiment_id = ?
        ORDER BY v.created_at, v.name COLLATE NOCASE
        ''',
        [experimentId],
      );

  Stream<List<Rec>> watchExperimentVariants(String experimentId) => watchQuery(
        _changes,
        {'visual_experiment_variants', 'visual_strategy_versions'},
        () => experimentVariants(experimentId),
      );

  Future<String> createExperiment({
    required String name,
    required String baselineVersionId,
  }) async {
    final title = name.trim();
    if (title.isEmpty) throw StateError('Enter an experiment name.');
    final experimentId = newId();
    final baselineVariantId = newId();
    await _write((txn, now) async {
      final versions = await txn.query(
        'visual_strategy_versions',
        columns: const ['id', 'name'],
        where: 'id = ?',
        whereArgs: [baselineVersionId],
        limit: 1,
      );
      if (versions.isEmpty) throw StateError('Baseline version not found.');
      await txn.insert('visual_experiments', {
        'id': experimentId,
        'name': title,
        'baseline_version_id': baselineVersionId,
        'created_at': now,
        'updated_at': now,
      });
      await txn.insert('visual_experiment_variants', {
        'id': baselineVariantId,
        'experiment_id': experimentId,
        'name': 'Baseline',
        'strategy_version_id': baselineVersionId,
        'parameter_overrides_json': '{}',
        'created_at': now,
      });
    });
    return experimentId;
  }

  Future<String> addExperimentVariant({
    required String experimentId,
    required String name,
    required String strategyVersionId,
  }) async {
    final title = name.trim();
    if (title.isEmpty) throw StateError('Enter a variant name.');
    final id = newId();
    await _write((txn, now) async {
      final experiments = await txn.query(
        'visual_experiments',
        columns: const ['id'],
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [experimentId],
        limit: 1,
      );
      if (experiments.isEmpty) throw StateError('Experiment not found.');
      final versions = await txn.query(
        'visual_strategy_versions',
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [strategyVersionId],
        limit: 1,
      );
      if (versions.isEmpty) throw StateError('Strategy version not found.');
      final duplicateVersion = await txn.query(
        'visual_experiment_variants',
        columns: const ['id'],
        where: 'experiment_id = ? AND strategy_version_id = ?',
        whereArgs: [experimentId, strategyVersionId],
        limit: 1,
      );
      if (duplicateVersion.isNotEmpty) {
        throw StateError(
          'This experiment already contains that exact strategy version.',
        );
      }
      await txn.insert('visual_experiment_variants', {
        'id': id,
        'experiment_id': experimentId,
        'name': title,
        'strategy_version_id': strategyVersionId,
        'parameter_overrides_json': '{}',
        'created_at': now,
      });
      await txn.update(
        'visual_experiments',
        {'updated_at': now},
        where: 'id = ?',
        whereArgs: [experimentId],
      );
    });
    return id;
  }

  Future<void> assignTestToExperimentVariant({
    required String testId,
    required String variantId,
  }) =>
      _write((txn, now) async {
        final variants = await txn.query(
          'visual_experiment_variants',
          columns: const ['id', 'experiment_id', 'strategy_version_id'],
          where: 'id = ?',
          whereArgs: [variantId],
          limit: 1,
        );
        if (variants.isEmpty) throw StateError('Experiment variant not found.');
        final tests = await txn.query(
          'visual_tests',
          columns: const [
            'strategy_version_id',
            'experiment_id',
            'experiment_variant_id',
            'deleted_at',
          ],
          where: 'id = ?',
          whereArgs: [testId],
          limit: 1,
        );
        if (tests.isEmpty || tests.first.sn('deleted_at') != null) {
          throw StateError('Visual test not found.');
        }
        final variant = variants.first;
        final test = tests.first;
        if (test.s('strategy_version_id') !=
            variant.s('strategy_version_id')) {
          throw StateError(
            'A test can only be assigned to a variant using its exact strategy version.',
          );
        }
        if (test.sn('experiment_id') != null &&
            (test.s('experiment_id') != variant.s('experiment_id') ||
                test.s('experiment_variant_id') != variantId)) {
          throw StateError(
            'A test already belongs to a different experiment variant.',
          );
        }
        await txn.update(
          'visual_tests',
          {
            'experiment_id': variant.s('experiment_id'),
            'experiment_variant_id': variantId,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [testId],
        );
      });

  Future<Rec?> strategyVersionById(String id) async {
    final rows = await (await _db).query(
      'visual_strategy_versions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<VisualStrategyDefinition?> definitionForVersion(
      String versionId) async {
    final version = await strategyVersionById(versionId);
    return version == null
        ? null
        : visualStrategyDefinitionFromVersion(version);
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

    return saveStrategyDefinition(
      id: id,
      definition: legacyVisualStrategyDefinition(
        name: name,
        entryConditions: entryConditions,
        exitConditions: exitConditions,
        stopLossRules: stopLossRules,
        takeProfitRules: takeProfitRules,
        stayOutConditions: stayOutConditions,
        sessions: sessions,
        timeframes: timeframes,
      ),
    );
  }

  Future<String> saveStrategyDefinition({
    String? id,
    required VisualStrategyDefinition definition,
  }) async {
    final error = definition.validate();
    if (error != null) throw StateError(error);

    final strategyId = id ?? newId();
    final values = <String, Object?>{
      'name': definition.name.trim(),
      'entry_conditions': _legacySummary(definition, 'entry'),
      'exit_conditions': _legacySummary(definition, 'exit'),
      'stop_loss_rules': _legacySummary(definition, 'stop_invalidation'),
      'take_profit_rules': _legacySummary(definition, 'take_profit'),
      'stay_out_conditions': _legacySummary(definition, 'stay_out'),
      'sessions_json': jsonEncode(definition.sessions.toSet().toList()),
      'timeframes_json': jsonEncode(definition.timeframes.toSet().toList()),
    };
    final versionId = newId();
    await _write((txn, now) async {
      if (id == null) {
        await txn.insert('visual_strategies', {
          ...values,
          'id': strategyId,
          'created_at': now,
          'updated_at': now,
        });
      } else {
        final existing = await txn.query(
          'visual_strategies',
          columns: const ['id'],
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [id],
          limit: 1,
        );
        if (existing.isEmpty) throw StateError('Strategy not found.');
        await txn.update(
          'visual_strategies',
          {...values, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [strategyId],
        );
      }

      final latest = await txn.rawQuery(
        'SELECT COALESCE(MAX(version_number), 0) AS version_number '
        'FROM visual_strategy_versions WHERE strategy_id = ?',
        [strategyId],
      );
      final versionNumber = (latest.first['version_number'] as num).toInt() + 1;
      await txn.insert('visual_strategy_versions', {
        'id': versionId,
        'strategy_id': strategyId,
        'version_number': versionNumber,
        'name': definition.name.trim(),
        'definition_json': definition.encode(),
        'created_at': now,
      });
    });
    return strategyId;
  }

  String _legacySummary(
    VisualStrategyDefinition definition,
    String category,
  ) {
    final stageIds = definition.stages
        .where((stage) => stage.category == category)
        .map((stage) => stage.id)
        .toSet();
    return definition.rules
        .where((rule) => stageIds.contains(rule.stageId))
        .map((rule) => rule.label)
        .join('\n');
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
             v.version_number AS strategy_version_number,
             (SELECT COUNT(*) FROM visual_test_images ti WHERE ti.test_id = t.id) AS image_count
      FROM visual_tests t
      JOIN visual_strategies s ON s.id = t.strategy_id
      LEFT JOIN visual_strategy_versions v ON v.id = t.strategy_version_id
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

  Future<List<Rec>> testResults() async => (await _db).rawQuery(
        '''
        SELECT t.strategy_id, t.strategy_version_id, t.scenario_id, t.mode,
               t.experiment_id, t.experiment_variant_id,
               t.instrument, t.timeframe, t.session, t.tested_at, t.outcome,
               t.entry_decision, t.result_r, t.rule_adherence, t.created_at,
               t.result_cash, t.result_currency, t.strategy_name_snapshot,
               v.version_number
        FROM visual_tests t
        LEFT JOIN visual_strategy_versions v ON v.id = t.strategy_version_id
        WHERE t.deleted_at IS NULL
        ORDER BY t.tested_at, t.created_at
        ''',
      );

  Stream<List<Rec>> watchTestResults() => watchQuery(
        _changes,
        {'visual_tests'},
        testResults,
      );

  Future<Rec?> testById(String id) async {
    final rows = await (await _db).rawQuery(
      '''
      SELECT t.*, t.strategy_name_snapshot AS strategy_name,
             v.version_number AS strategy_version_number
      FROM visual_tests t
      JOIN visual_strategies s ON s.id = t.strategy_id
      LEFT JOIN visual_strategy_versions v ON v.id = t.strategy_version_id
      WHERE t.id = ? AND t.deleted_at IS NULL
      LIMIT 1
      ''',
      [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Rec>> imagesForTest(String testId) async => (await _db).rawQuery(
        '''
        SELECT i.*, f.local_path AS local_path, ti.sort_order,
               ti.role AS test_role, ti.cutoff_x AS cutoff_x,
               ti.visible_through_timestamp_ms AS visible_through_timestamp_ms,
               ti.decision_at_ms AS decision_at_ms
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

  Future<String> addAnnotation({
    required String testId,
    required String imageId,
    required String kind,
    required double x,
    required double y,
    required String label,
    double? price,
  }) async {
    final annotation = <String, Object?>{
      'kind': kind,
      'x': x,
      'y': y,
      'label': label,
      'price': price,
    };
    _validateAnnotations([annotation]);
    final annotationId = newId();
    await _write((txn, now) async {
      final linked = await txn.query(
        'visual_test_images',
        columns: const ['id', 'role'],
        where: 'test_id = ? AND image_id = ?',
        whereArgs: [testId, imageId],
        limit: 1,
      );
      if (linked.isEmpty) {
        throw StateError('Attach this screenshot to the test first.');
      }
      final testRows = await txn.query(
        'visual_tests',
        columns: const ['decision_locked_at'],
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [testId],
        limit: 1,
      );
      if (testRows.isEmpty) throw StateError('Visual test not found.');
      if (testRows.first.sn('decision_locked_at') != null &&
          linked.first.s('role') == 'decision') {
        throw StateError('Decision-point chart marks are locked.');
      }
      await txn.insert('visual_annotations', {
        ...annotation,
        'id': annotationId,
        'test_id': testId,
        'image_id': imageId,
        'created_at': now,
      });
    });
    return annotationId;
  }

  Future<void> deleteAnnotation(String id) => _write((txn, _) async {
        final rows = await txn.query(
          'visual_annotations',
          columns: const ['test_id', 'image_id'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (rows.isEmpty) throw StateError('Chart mark not found.');
        final test = await txn.query(
          'visual_tests',
          columns: const ['decision_locked_at'],
          where: 'id = ?',
          whereArgs: [rows.first.s('test_id')],
          limit: 1,
        );
        if (test.isNotEmpty && test.first.sn('decision_locked_at') != null) {
          final image = await txn.query(
            'visual_test_images',
            columns: const ['role'],
            where: 'test_id = ? AND image_id = ?',
            whereArgs: [rows.first.s('test_id'), rows.first.s('image_id')],
            limit: 1,
          );
          if (image.isNotEmpty && image.first.s('role') == 'decision') {
            throw StateError('Decision-point chart marks are locked.');
          }
        }
        await txn.delete(
          'visual_annotations',
          where: 'id = ?',
          whereArgs: [id],
        );
      });

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

  Future<String> startTest({
    required String strategyId,
    required String strategyVersionId,
    required String scenarioId,
    required String mode,
    required String testedAt,
    required String instrument,
    required String timeframe,
    required String session,
    required String marketContext,
    String? datasetId,
    String? experimentId,
    String? experimentVariantId,
  }) async {
    if (mode != 'manual' && mode != 'automatic') {
      throw StateError('Choose manual screenshot or automatic OHLC mode.');
    }
    if (DateTime.tryParse(testedAt) == null) {
      throw StateError('Choose a valid test date.');
    }
    if (mode == 'automatic' && datasetId == null) {
      throw StateError('Select a historical dataset for automatic testing.');
    }
    if ((experimentId == null) != (experimentVariantId == null)) {
      throw StateError('Choose both an experiment and its variant.');
    }

    final testId = newId();
    await _write((txn, now) async {
      final strategyRows = await txn.query(
        'visual_strategies',
        columns: const ['id'],
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [strategyId],
        limit: 1,
      );
      if (strategyRows.isEmpty) throw StateError('Strategy not found.');
      final versionRows = await txn.query(
        'visual_strategy_versions',
        where: 'id = ? AND strategy_id = ?',
        whereArgs: [strategyVersionId, strategyId],
        limit: 1,
      );
      if (versionRows.isEmpty) throw StateError('Strategy version not found.');
      final version = versionRows.first;
      final definition = visualStrategyDefinitionFromVersion(version);
      if (!definition.scenarios.any((item) => item.id == scenarioId)) {
        throw StateError(
            'Choose an entry scenario from this strategy version.');
      }
      final normalizedInstrument = instrument.trim().toUpperCase();
      final normalizedTimeframe = canonicalVisualTimeframe(timeframe);
      if (normalizedInstrument.isEmpty ||
          (definition.instruments.isNotEmpty &&
              !definition.instruments.contains(normalizedInstrument))) {
        throw StateError(
            'Choose an instrument allowed by this strategy version.');
      }
      if (!definition.timeframes.contains(normalizedTimeframe)) {
        throw StateError(
            'Choose a timeframe allowed by this strategy version.');
      }
      if (session.trim().isNotEmpty &&
          !definition.sessions.contains(session)) {
        throw StateError('Choose a trading session allowed by this version.');
      }
      if (datasetId != null) {
        final dataset = await txn.query(
          'historical_datasets',
          columns: const ['id', 'instrument', 'timeframe'],
          where: 'id = ?',
          whereArgs: [datasetId],
          limit: 1,
        );
        if (dataset.isEmpty) throw StateError('Historical dataset not found.');
        if (mode == 'automatic' &&
            (dataset.first.s('instrument') != normalizedInstrument ||
                canonicalVisualTimeframe(dataset.first.s('timeframe')) !=
                    normalizedTimeframe)) {
          throw StateError(
              'Dataset instrument/timeframe does not match the test.');
        }
      }
      if (experimentId != null) {
        final variants = await txn.query(
          'visual_experiment_variants',
          columns: const ['id'],
          where: 'id = ? AND experiment_id = ? AND strategy_version_id = ?',
          whereArgs: [experimentVariantId, experimentId, strategyVersionId],
          limit: 1,
        );
        if (variants.isEmpty) {
          throw StateError(
            'The selected experiment variant uses a different strategy version.',
          );
        }
      }

      final strategy = await txn.query(
        'visual_strategies',
        columns: const ['name'],
        where: 'id = ?',
        whereArgs: [strategyId],
        limit: 1,
      );
      await txn.insert('visual_tests', {
        'id': testId,
        'strategy_id': strategyId,
        'strategy_version_id': strategyVersionId,
        'strategy_name_snapshot': version.s('name', strategy.first.s('name')),
        'strategy_snapshot_json': definition.encode(),
        'scenario_id': scenarioId,
        'mode': mode,
        'tested_at': DateTime.parse(testedAt).toUtc().toIso8601String(),
        'instrument': normalizedInstrument,
        'timeframe': normalizedTimeframe,
        'session': session.trim().isEmpty ? null : session.trim(),
        'market_context':
            marketContext.trim().isEmpty ? null : marketContext.trim(),
        'dataset_id': datasetId,
        'experiment_id': experimentId,
        'experiment_variant_id': experimentVariantId,
        'outcome': 'pending',
        'risk_config_json': jsonEncode(definition.riskManagement),
        'execution_config_json': jsonEncode(definition.executionAssumptions),
        'created_at': now,
        'updated_at': now,
      });
    });
    return testId;
  }

  Future<Map<String, String>> latestRuleStates(String testId) async {
    final events = await (await _db).query(
      'visual_test_rule_events',
      columns: const ['rule_id', 'state'],
      where: 'test_id = ?',
      whereArgs: [testId],
      orderBy: 'sequence',
    );
    return {
      for (final event in events) event.s('rule_id'): event.s('state'),
    };
  }

  Future<List<Rec>> ruleStateHistory(String testId) async => (await _db).query(
        'visual_test_rule_events',
        where: 'test_id = ?',
        whereArgs: [testId],
        orderBy: 'sequence',
      );

  Future<List<Rec>> testEventHistory(String testId) async => (await _db).query(
        'visual_test_events',
        where: 'test_id = ?',
        whereArgs: [testId],
        orderBy: 'sequence',
      );

  Future<void> recordRuleState({
    required String testId,
    required String ruleId,
    required String state,
    required String explanation,
    String? observedValue,
    String? decision,
    int? eventTimestampMs,
    bool automatic = false,
  }) async {
    if (!visualRuleStates.contains(state)) {
      throw StateError('Choose a valid rule state.');
    }
    await _write((txn, now) async {
      final testRows = await txn.query(
        'visual_tests',
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [testId],
        limit: 1,
      );
      if (testRows.isEmpty) throw StateError('Visual test not found.');
      final test = testRows.first;
      final versionId = test.sn('strategy_version_id');
      if (versionId == null) {
        throw StateError('Test has no saved strategy version.');
      }
      final versionRows = await txn.query(
        'visual_strategy_versions',
        where: 'id = ?',
        whereArgs: [versionId],
        limit: 1,
      );
      if (versionRows.isEmpty) throw StateError('Strategy version not found.');
      final definition = visualStrategyDefinitionFromVersion(versionRows.first);
      final rule = definition.rules.where((item) => item.id == ruleId);
      if (rule.isEmpty) {
        throw StateError('Rule is not part of this test version.');
      }
      final selectedRule = rule.first;
      final selectedStage = definition.stages.firstWhere(
        (item) => item.id == selectedRule.stageId,
      );
      final scenarioMismatch = test.s('scenario_id').isNotEmpty &&
          selectedRule.scenarioId != null &&
          selectedRule.scenarioId != test.s('scenario_id');
      if (scenarioMismatch && state != 'not_applicable') {
        throw StateError('Rule is not part of the selected entry scenario.');
      }
      if (automatic &&
          state != 'not_applicable' &&
          (test.s('mode') != 'automatic' || selectedRule.mode != 'numeric')) {
        throw StateError(
            'Automatic evaluation is only available for numeric rules.');
      }
      final completedEvents = await txn.query(
        'visual_test_events',
        columns: const ['id'],
        where: 'test_id = ? AND kind = ?',
        whereArgs: [testId, 'test_completed'],
        limit: 1,
      );
      if (completedEvents.isNotEmpty) {
        throw StateError('A completed test cannot be changed.');
      }
      if (test.sn('decision_locked_at') != null) {
        final allowedAfterLock = {
          'management',
          'stop_invalidation',
          'take_profit',
          'exit',
          'outcome',
        };
        if (!allowedAfterLock.contains(selectedStage.category)) {
          throw StateError('Decision-stage rule states are locked.');
        }
      }

      final statesBefore = await _latestRuleStatesIn(txn, testId);
      if (state != 'pending' && state != 'not_applicable' &&
          selectedStage.dependsOn.any((stageId) {
            final stage = definition.stages.firstWhere(
              (item) => item.id == stageId,
            );
            final requiredRules = definition.rules.where(
              (item) =>
                  item.stageId == stage.id &&
                  item.required &&
                  (item.scenarioId == null ||
                      item.scenarioId == test.s('scenario_id')),
            );
            return requiredRules.any((item) {
              final current = statesBefore[item.id] ?? 'pending';
              return current != 'satisfied' && current != 'not_applicable';
            });
          })) {
        throw StateError('Complete the previous checklist stage first.');
      }
      if (state != 'pending' && state != 'not_applicable' &&
          !canEvaluateVisualRule(selectedRule, statesBefore)) {
        throw StateError(
            'Complete this rule’s dependencies before evaluating it.');
      }

      final latest = await txn.rawQuery(
        'SELECT state FROM visual_test_rule_events '
        'WHERE test_id = ? AND rule_id = ? ORDER BY sequence DESC LIMIT 1',
        [testId, ruleId],
      );
      final previousState = latest.isEmpty ? null : latest.first.s('state');
      if (previousState == state &&
          (observedValue ?? '') == '' &&
          explanation.trim().isEmpty &&
          decision == null) {
        return;
      }
      final sequenceRows = await txn.rawQuery(
        'SELECT COALESCE(MAX(sequence), 0) + 1 AS next_sequence '
        'FROM visual_test_rule_events WHERE test_id = ?',
        [testId],
      );
      await txn.insert('visual_test_rule_events', {
        'id': newId(),
        'test_id': testId,
        'sequence': (sequenceRows.first['next_sequence'] as num).toInt(),
        'rule_id': ruleId,
        'previous_state': previousState,
        'state': state,
        'observed_value': observedValue,
        'explanation': explanation.trim().isEmpty ? null : explanation.trim(),
        'decision': decision ?? (automatic ? 'automatic' : 'manual'),
        'event_timestamp_ms': eventTimestampMs,
        'created_at': now,
      });
    });
  }

  Future<void> addTestImage({
    required String testId,
    required String imageId,
    required String role,
    double? cutoffX,
    int? visibleThroughTimestampMs,
    int? decisionAtMs,
  }) async {
    const roles = {'decision', 'evidence', 'legacy'};
    if (!roles.contains(role)) {
      throw StateError('Choose a valid evidence role.');
    }
    if (role == 'decision' &&
        (cutoffX == null ||
            !cutoffX.isFinite ||
            cutoffX <= 0 ||
            cutoffX >= 1)) {
      throw StateError('Set the visible chart boundary for decision evidence.');
    }
    await _write((txn, now) async {
      final testRows = await txn.query(
        'visual_tests',
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [testId],
        limit: 1,
      );
      if (testRows.isEmpty) throw StateError('Visual test not found.');
      final isLocked = testRows.first.sn('decision_locked_at') != null;
      if ((role == 'decision' && isLocked) ||
          (role == 'evidence' && !isLocked)) {
        throw StateError(
          role == 'decision'
              ? 'Decision evidence cannot be changed after the decision is locked.'
              : 'Lock the decision before adding subsequent evidence.',
        );
      }
      final image = await txn.query(
        'images',
        columns: const ['id'],
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [imageId],
        limit: 1,
      );
      if (image.isEmpty) {
        throw StateError('Selected screenshot is unavailable.');
      }
      final existing = await txn.query(
        'visual_test_images',
        columns: const ['id', 'role'],
        where: 'test_id = ? AND image_id = ?',
        whereArgs: [testId, imageId],
        limit: 1,
      );
      if (role == 'decision') {
        final otherDecisionImages = await txn.query(
          'visual_test_images',
          columns: const ['image_id'],
          where: 'test_id = ? AND role = ? AND image_id != ?',
          whereArgs: [testId, 'decision', imageId],
          limit: 1,
        );
        if (otherDecisionImages.isNotEmpty) {
          throw StateError(
            'A test can have only one decision-point screenshot. Remove the old link before replacing it.',
          );
        }
      }
      if (existing.isEmpty) {
        await txn.insert('visual_test_images', {
          'id': newId(),
          'test_id': testId,
          'image_id': imageId,
          'sort_order': existing.length,
          'role': role,
          'cutoff_x': cutoffX,
          'visible_through_timestamp_ms': visibleThroughTimestampMs,
          'decision_at_ms': decisionAtMs,
        });
      } else {
        await txn.update(
          'visual_test_images',
          {
            'role': role,
            'cutoff_x': cutoffX,
            'visible_through_timestamp_ms': visibleThroughTimestampMs,
            'decision_at_ms': decisionAtMs,
          },
          where: 'id = ?',
          whereArgs: [existing.first.s('id')],
        );
      }
      await txn.update(
        'visual_tests',
        {'updated_at': now},
        where: 'id = ?',
        whereArgs: [testId],
      );
    });
  }

  Future<void> removeTestImage({
    required String testId,
    required String imageId,
  }) =>
      _write((txn, _) async {
        final links = await txn.query(
          'visual_test_images',
          columns: const ['id', 'role'],
          where: 'test_id = ? AND image_id = ?',
          whereArgs: [testId, imageId],
          limit: 1,
        );
        if (links.isEmpty) throw StateError('Test screenshot not found.');
        final tests = await txn.query(
          'visual_tests',
          columns: const ['decision_locked_at'],
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [testId],
          limit: 1,
        );
        if (tests.isEmpty) throw StateError('Visual test not found.');
        final completed = await txn.query(
          'visual_test_events',
          columns: const ['id'],
          where: 'test_id = ? AND kind = ?',
          whereArgs: [testId, 'test_completed'],
          limit: 1,
        );
        if (completed.isNotEmpty) {
          throw StateError('Evidence cannot be changed after test completion.');
        }
        if (links.first.s('role') == 'decision' &&
            tests.first.sn('decision_locked_at') != null) {
          throw StateError('Decision-point evidence is locked.');
        }
        await txn.delete(
          'visual_annotations',
          where: 'test_id = ? AND image_id = ?',
          whereArgs: [testId, imageId],
        );
        await txn.delete(
          'visual_test_images',
          where: 'id = ?',
          whereArgs: [links.first.s('id')],
        );
      });

  Future<void> lockDecision({
    required String testId,
    required String decision,
    required String explanation,
    int? eventTimestampMs,
  }) async {
    const decisions = {
      'valid_entry',
      'rejected_setup',
      'skipped_trade',
      'invalidated_setup',
    };
    if (!decisions.contains(decision)) {
      throw StateError('Choose a valid setup decision.');
    }
    await _write((txn, now) async {
      final testRows = await txn.query(
        'visual_tests',
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [testId],
        limit: 1,
      );
      if (testRows.isEmpty) throw StateError('Visual test not found.');
      final test = testRows.first;
      if (test.sn('decision_locked_at') != null) {
        throw StateError('This decision is already locked.');
      }
      final decisionImages = await txn.query(
        'visual_test_images',
        columns: const ['id'],
        where: 'test_id = ? AND role = ?',
        whereArgs: [testId, 'decision'],
        limit: 1,
      );
      if (test.s('mode') == 'manual' && decisionImages.isEmpty) {
        throw StateError(
            'Add decision-point evidence before locking the decision.');
      }
      final versionId = test.sn('strategy_version_id');
      if (versionId == null) {
        throw StateError('Test has no saved strategy version.');
      }
      final versions = await txn.query(
        'visual_strategy_versions',
        where: 'id = ?',
        whereArgs: [versionId],
        limit: 1,
      );
      if (versions.isEmpty) throw StateError('Strategy version not found.');
      final definition = visualStrategyDefinitionFromVersion(versions.first);
      final states = await _latestRuleStatesIn(txn, testId);
      final applicableRules = definition.rules.where(
        (rule) =>
            rule.scenarioId == null || rule.scenarioId == test.s('scenario_id'),
      );
      final checklist = buildVisualChecklist(
        definition: definition,
        scenarioId: test.s('scenario_id'),
        states: states,
      );
      if (decision == 'valid_entry' && !checklist.canRecordEntry) {
        throw StateError(
          checklist.entryBlockReason ?? 'Mandatory entry rules are incomplete.',
        );
      }
      if (decision == 'skipped_trade' &&
          !applicableRules.any((rule) =>
              rule.blocksEntryWhenSatisfied &&
              states[rule.id] == 'satisfied')) {
        throw StateError(
            'A stay-out rule must be satisfied to skip this trade.');
      }
      if (decision == 'invalidated_setup' && !checklist.hasInvalidatedRule) {
        throw StateError('No strategy rule has invalidated this setup.');
      }
      final stayOutApplies = applicableRules.any((rule) =>
          rule.blocksEntryWhenSatisfied && states[rule.id] == 'satisfied');
      if (decision == 'rejected_setup' &&
          (checklist.canRecordEntry || stayOutApplies)) {
        throw StateError(
          stayOutApplies
              ? 'A satisfied stay-out rule must be recorded as a skipped trade.'
              : 'The checklist permits an entry; this setup is not rejected.',
        );
      }

      final sequenceRows = await txn.rawQuery(
        'SELECT COALESCE(MAX(sequence), 0) + 1 AS next_sequence '
        'FROM visual_test_events WHERE test_id = ?',
        [testId],
      );
      await txn.insert('visual_test_events', {
        'id': newId(),
        'test_id': testId,
        'sequence': (sequenceRows.first['next_sequence'] as num).toInt(),
        'kind': 'entry_decision',
        'decision': decision,
        'event_timestamp_ms': eventTimestampMs,
        'details_json': jsonEncode({'explanation': explanation.trim()}),
        'created_at': now,
      });
      await txn.update(
        'visual_tests',
        {
          'entry_decision': decision,
          'decision_locked_at': now,
          'decision_timestamp_ms': eventTimestampMs,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [testId],
      );
    });
  }

  Future<Map<String, String>> _latestRuleStatesIn(
    Transaction txn,
    String testId,
  ) async {
    final events = await txn.query(
      'visual_test_rule_events',
      columns: const ['rule_id', 'state'],
      where: 'test_id = ?',
      whereArgs: [testId],
      orderBy: 'sequence',
    );
    return {
      for (final event in events) event.s('rule_id'): event.s('state'),
    };
  }

  Future<void> recordExecutionEvent({
    required String testId,
    required String kind,
    required String decision,
    required String notes,
    int? eventTimestampMs,
    double? price,
    double? quantity,
    Map<String, Object?> details = const {},
  }) async {
    const kinds = {
      'entry',
      'partial_close',
      'stop_moved',
      'target_updated',
      'breakeven_stop',
      'trailing_stop',
      'management_decision',
      'exit',
      'uncertainty',
    };
    if (!kinds.contains(kind)) throw StateError('Choose a valid trade event.');
    if (price != null && (!price.isFinite || price <= 0)) {
      throw StateError('Enter a valid event price.');
    }
    if (quantity != null && (!quantity.isFinite || quantity <= 0)) {
      throw StateError('Enter a valid event quantity.');
    }
    if (kind == 'uncertainty' && notes.trim().isEmpty) {
      throw StateError('Describe the execution uncertainty.');
    }
    await _write((txn, now) async {
      final tests = await txn.query(
        'visual_tests',
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [testId],
        limit: 1,
      );
      if (tests.isEmpty) throw StateError('Visual test not found.');
      final test = tests.first;
      if (test.s('entry_decision') != 'valid_entry') {
        throw StateError('Trade management requires a valid recorded entry.');
      }
      if (test.s('decision_locked_at').isEmpty) {
        throw StateError(
            'Lock the entry decision before recording trade events.');
      }
      final previous = await txn.query(
        'visual_test_events',
        columns: const ['kind'],
        where: 'test_id = ?',
        whereArgs: [testId],
        orderBy: 'sequence',
      );
      if (previous.any((event) => event.s('kind') == 'test_completed')) {
        throw StateError('A completed test cannot be changed.');
      }
      final hasEntry = previous.any((event) => event.s('kind') == 'entry');
      final hasExit = previous.any((event) => event.s('kind') == 'exit');
      if (kind == 'entry' && hasEntry) {
        throw StateError('An entry event is already recorded.');
      }
      if (kind != 'entry' && !hasEntry) {
        throw StateError('Record the entry before trade-management events.');
      }
      if (hasExit) throw StateError('The simulated trade is already closed.');
      if (kind == 'exit' && price == null) {
        throw StateError('Record the exit price.');
      }
      final next = await txn.rawQuery(
        'SELECT COALESCE(MAX(sequence), 0) + 1 AS next_sequence '
        'FROM visual_test_events WHERE test_id = ?',
        [testId],
      );
      await txn.insert('visual_test_events', {
        'id': newId(),
        'test_id': testId,
        'sequence': (next.first['next_sequence'] as num).toInt(),
        'kind': kind,
        'decision': decision,
        'event_timestamp_ms': eventTimestampMs,
        'price': price,
        'quantity': quantity,
        'details_json': jsonEncode({
          ...details,
          if (notes.trim().isNotEmpty) 'notes': notes.trim(),
        }),
        'created_at': now,
      });
    });
  }

  Future<void> completeTest({
    required String testId,
    required String outcome,
    required double? resultR,
    required String notes,
    required String ruleAdherence,
    double? entryPrice,
    double? stopLossPrice,
    double? takeProfitPrice,
    double? exitPrice,
    double? cashResult,
    String? currency,
  }) async {
    final error = validateVisualOutcome(outcome, resultR);
    if (error != null) throw StateError(error);
    const adherenceValues = {'followed', 'violated', 'unknown'};
    if (!adherenceValues.contains(ruleAdherence)) {
      throw StateError('Choose a valid rule-adherence result.');
    }

    for (final (label, value) in <(String, double?)>[
      ('entry', entryPrice),
      ('stop-loss', stopLossPrice),
      ('take-profit', takeProfitPrice),
      ('exit', exitPrice),
    ]) {
      if (value != null && (!value.isFinite || value <= 0)) {
        throw StateError('Enter a valid $label price.');
      }
    }
    if (cashResult != null && !cashResult.isFinite) {
      throw StateError('Enter a finite cash result.');
    }

    await _write((txn, now) async {
      final tests = await txn.query(
        'visual_tests',
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [testId],
        limit: 1,
      );
      if (tests.isEmpty) throw StateError('Visual test not found.');
      final test = tests.first;
      final completed = await txn.query(
        'visual_test_events',
        columns: const ['id'],
        where: 'test_id = ? AND kind = ?',
        whereArgs: [testId, 'test_completed'],
        limit: 1,
      );
      if (completed.isNotEmpty) {
        throw StateError('This test is already complete.');
      }
      if (test.sn('decision_locked_at') == null) {
        throw StateError(
            'Lock the strategy decision before completing the test.');
      }
      final isTrade = test.s('entry_decision') == 'valid_entry';
      if (!isTrade && outcome != 'not_traded' && outcome != 'inconclusive') {
        throw StateError(
            'A rejected, skipped or invalidated setup is not a trade result.');
      }
      if (!isTrade && resultR != null) {
        throw StateError('A setup without an entry cannot have an R result.');
      }
      if (isTrade &&
          outcome != 'win' &&
          outcome != 'loss' &&
          outcome != 'breakeven' &&
          outcome != 'inconclusive') {
        throw StateError('Record the outcome of the valid entry.');
      }
      if (cashResult != null && (currency == null || currency.trim().isEmpty)) {
        throw StateError('Choose a currency for the monetary result.');
      }
      final events = await txn.query(
        'visual_test_events',
        columns: const ['kind'],
        where: 'test_id = ?',
        whereArgs: [testId],
      );
      if (isTrade && !events.any((event) => event.s('kind') == 'entry')) {
        throw StateError(
            'Record the simulated entry before completing the trade.');
      }
      if (isTrade &&
          outcome != 'inconclusive' &&
          !events.any((event) => event.s('kind') == 'exit')) {
        throw StateError(
            'Record the simulated exit before completing the trade.');
      }
      final next = await txn.rawQuery(
        'SELECT COALESCE(MAX(sequence), 0) + 1 AS next_sequence '
        'FROM visual_test_events WHERE test_id = ?',
        [testId],
      );
      await txn.insert('visual_test_events', {
        'id': newId(),
        'test_id': testId,
        'sequence': (next.first['next_sequence'] as num).toInt(),
        'kind': 'test_completed',
        'decision': outcome,
        'details_json': jsonEncode({'rule_adherence': ruleAdherence}),
        'created_at': now,
      });
      await txn.update(
        'visual_tests',
        {
          'outcome': outcome,
          'result_r': resultR,
          'notes': notes.trim().isEmpty ? null : notes.trim(),
          'rule_adherence': ruleAdherence,
          'entry_price': entryPrice,
          'stop_loss_price': stopLossPrice,
          'take_profit_price': takeProfitPrice,
          'exit_price': exitPrice,
          'result_cash': cashResult,
          'result_currency': cashResult == null ? null : currency!.trim(),
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [testId],
      );
    });
  }

  Future<void> saveTestNotes({
    required String testId,
    required String notes,
  }) =>
      _write((txn, now) async {
        final tests = await txn.query(
          'visual_tests',
          columns: const ['id'],
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [testId],
          limit: 1,
        );
        if (tests.isEmpty) throw StateError('Visual test not found.');
        final completed = await txn.query(
          'visual_test_events',
          columns: const ['id'],
          where: 'test_id = ? AND kind = ?',
          whereArgs: [testId, 'test_completed'],
          limit: 1,
        );
        if (completed.isNotEmpty) {
          throw StateError('Notes cannot be changed after test completion.');
        }
        await txn.update(
          'visual_tests',
          {
            'notes': notes.trim().isEmpty ? null : notes.trim(),
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [testId],
        );
      });

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
