import 'package:flutter_test/flutter_test.dart';
import 'package:my_market_lab/data/backtesting/strategy_definition.dart';
import 'package:my_market_lab/data/repositories/visual_backtesting_repository.dart';

void main() {
  test('strategy requires all rule classes and supported market context', () {
    String? validate({
      String name = 'Pullback',
      String entry = 'Enter after reclaim.',
      String exit = 'Exit on invalidation.',
      String stop = 'Beyond swing low.',
      String target = 'At next resistance.',
      String stayOut = 'Avoid high-impact news.',
      List<String> sessions = const ['London'],
      List<String> timeframes = const ['15M'],
    }) =>
        validateVisualStrategy(
          name: name,
          entryConditions: entry,
          exitConditions: exit,
          stopLossRules: stop,
          takeProfitRules: target,
          stayOutConditions: stayOut,
          sessions: sessions,
          timeframes: timeframes,
        );

    expect(validate(), isNull);
    expect(validate(entry: ''), contains('entry conditions'));
    expect(validate(stayOut: ''), contains('staying out'));
    expect(validate(sessions: const []), contains('trading session'));
    expect(validate(timeframes: const ['Monthly']), contains('timeframes'));
  });

  test(
      'manual outcome validation enforces sign and leaves unresolved tests unscored',
      () {
    expect(validateVisualOutcome('win', 1.5), isNull);
    expect(validateVisualOutcome('win', -1), contains('positive'));
    expect(validateVisualOutcome('loss', 1), contains('negative'));
    expect(validateVisualOutcome('breakeven', 0), isNull);
    expect(validateVisualOutcome('pending', 0), contains('cannot have'));
    expect(validateVisualOutcome('inconclusive', null), isNull);
  });

  test(
      'statistics count only recorded outcomes and calculate ordered R drawdown',
      () {
    final stats = VisualBacktestStats.fromTests([
      {'tested_at': '2026-01-01', 'outcome': 'win', 'result_r': 2.0},
      {'tested_at': '2026-01-02', 'outcome': 'loss', 'result_r': -1.0},
      {'tested_at': '2026-01-03', 'outcome': 'loss', 'result_r': -2.0},
      {'tested_at': '2026-01-04', 'outcome': 'breakeven', 'result_r': 0.0},
      {'tested_at': '2026-01-05', 'outcome': 'pending'},
      {'tested_at': '2026-01-06', 'outcome': 'inconclusive'},
    ]);

    expect(stats.testCount, 4);
    expect(stats.wins, 1);
    expect(stats.losses, 2);
    expect(stats.breakeven, 1);
    expect(stats.winRate, closeTo(1 / 3, 0.0001));
    expect(stats.meanR, closeTo(-0.25, 0.0001));
    expect(stats.rSampleCount, 4);
    expect(stats.maxDrawdownR, 3.0);
  });

  test('drawdown is not reported when any completed test lacks an R result',
      () {
    final stats = VisualBacktestStats.fromTests([
      {'tested_at': '2026-01-01', 'outcome': 'win', 'result_r': 1.0},
      {'tested_at': '2026-01-02', 'outcome': 'loss'},
    ]);

    expect(stats.winRate, 0.5);
    expect(stats.meanR, 1.0);
    expect(stats.maxDrawdownR, isNull);
  });

  test('same-day drawdown follows test creation chronology', () {
    final results = <Map<String, Object?>>[
      {'created_at': '2026-01-01T06:00:00Z', 'result_r': 3.0},
      {'created_at': '2026-01-01T05:00:00Z', 'result_r': -4.0},
      {'created_at': '2026-01-01T04:00:00Z', 'result_r': 3.0},
      {'created_at': '2026-01-01T03:00:00Z', 'result_r': -1.0},
      {'created_at': '2026-01-01T02:00:00Z', 'result_r': 2.0},
      {'created_at': '2026-01-01T01:00:00Z', 'result_r': -4.0},
    ].map((result) => {
          ...result,
          'tested_at': '2026-01-01T00:00:00Z',
          'outcome': (result['result_r'] as num) > 0 ? 'win' : 'loss',
        });

    final stats = VisualBacktestStats.fromTests(results);

    expect(stats.maxDrawdownR, 4.0);
  });

  test('checklist blocks entries until required entry rule is satisfied', () {
    final definition = legacyVisualStrategyDefinition(
      name: 'Test',
      entryConditions: 'Confirm break and close.',
      exitConditions: 'Exit at invalidation.',
      stopLossRules: 'Beyond swing.',
      takeProfitRules: 'At target.',
      stayOutConditions: 'Avoid news.',
      sessions: const ['London'],
      timeframes: const ['15M'],
    );
    final entryRule = definition.rules.firstWhere(
      (rule) => rule.stageId == 'legacy-stage-entry',
    );

    final waiting = buildVisualChecklist(
      definition: definition,
      scenarioId: definition.scenarios.first.id,
      states: const {},
    );
    expect(waiting.canRecordEntry, isFalse);
    expect(waiting.entryBlockReason, contains('mandatory stay-out'));

    final ready = buildVisualChecklist(
      definition: definition,
      scenarioId: definition.scenarios.first.id,
      states: {
        entryRule.id: 'satisfied',
        'legacy-rule-stay_out': 'not_satisfied',
      },
    );
    expect(ready.canRecordEntry, isTrue);
    expect(definition.timeframes, ['M15']);
  });

  test('satisfied stay-out rule blocks entry even when entry trigger is met',
      () {
    final definition = legacyVisualStrategyDefinition(
      name: 'Test',
      entryConditions: 'Confirm break and close.',
      exitConditions: 'Exit at invalidation.',
      stopLossRules: 'Beyond swing.',
      takeProfitRules: 'At target.',
      stayOutConditions: 'Avoid news.',
      sessions: const ['London'],
      timeframes: const ['15M'],
    );
    final entryRule = definition.rules.firstWhere(
      (rule) => rule.stageId == 'legacy-stage-entry',
    );
    final stayOutRule = definition.rules.firstWhere(
      (rule) => rule.stageId == 'legacy-stage-stay_out',
    );

    final checklist = buildVisualChecklist(
      definition: definition,
      scenarioId: definition.scenarios.first.id,
      states: {
        entryRule.id: 'satisfied',
        stayOutRule.id: 'satisfied',
      },
    );

    expect(checklist.canRecordEntry, isFalse);
    expect(checklist.entryBlockReason, contains('stay-out'));
  });

  test('statistics expose incomplete and missing-quality samples', () {
    final stats = VisualBacktestStats.fromTests([
      {
        'tested_at': '2026-01-01',
        'outcome': 'win',
        'result_r': 1.0,
        'rule_adherence': 'violated',
      },
      {'tested_at': '2026-01-02', 'outcome': 'pending'},
      {'tested_at': '2026-01-03', 'outcome': 'inconclusive'},
    ]);

    expect(stats.incompleteCount, 2);
    expect(stats.ruleViolationCount, 1);
    expect(stats.missingAdherenceSampleCount, 0);
    expect(stats.testCount, 1);
  });
}
