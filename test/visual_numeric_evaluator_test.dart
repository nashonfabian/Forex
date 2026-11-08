import 'package:flutter_test/flutter_test.dart';
import 'package:my_market_lab/data/backtesting/strategy_definition.dart';
import 'package:my_market_lab/data/backtesting/visual_numeric_evaluator.dart';

void main() {
  VisualStrategyRule rule({
    String metric = 'close',
    String comparator = '>',
    double threshold = 10,
    int period = 1,
  }) =>
      VisualStrategyRule(
        id: 'rule',
        stageId: 'entry',
        label: 'numeric condition',
        mode: 'numeric',
        relation: 'and',
        dependsOn: const [],
        required: true,
        blocksEntryWhenSatisfied: false,
        metric: metric,
        comparator: comparator,
        threshold: threshold,
        period: period,
      );

  Map<String, Object?> candle(
    double close, {
    double? open,
    double? high,
    double? low,
  }) =>
      {
        'open': open ?? close,
        'high': high ?? close,
        'low': low ?? close,
        'close': close,
      };

  test('evaluates a numeric comparison from the selected candle', () {
    final result = evaluateVisualNumericRule(
      rule(comparator: '>=', threshold: 10),
      [candle(10)],
    );

    expect(result.state, 'satisfied');
    expect(result.observedValue, '10.0');
  });

  test('cross comparisons use only the previous and current candles', () {
    final result = evaluateVisualNumericRule(
      rule(comparator: 'cross_above', threshold: 10),
      [candle(9), candle(11)],
    );

    expect(result.state, 'satisfied');
    expect(result.observedValue, '11.0');
  });

  test('moving averages do not use bars after the decision index', () {
    final bars = [candle(10), candle(20), candle(30), candle(100)];
    final selectedPrefix = evaluateVisualNumericRule(
      rule(metric: 'sma', comparator: '>=', threshold: 25, period: 2),
      bars.take(3).toList(),
    );

    expect(selectedPrefix.state, 'satisfied');
    expect(selectedPrefix.observedValue, '25.0');
  });

  test('returns pending when the required indicator history is unavailable',
      () {
    final result = evaluateVisualNumericRule(
      rule(metric: 'atr', period: 3),
      [candle(10, high: 12, low: 8)],
    );

    expect(result.state, 'pending');
    expect(result.observedValue, isNull);
  });

  test('computes true range using prior close and current OHLC', () {
    final result = evaluateVisualNumericRule(
      rule(
        metric: 'atr',
        comparator: '>=',
        threshold: 3,
        period: 1,
      ),
      [
        candle(10, high: 11, low: 9),
        candle(12, high: 13, low: 11),
      ],
    );

    expect(result.state, 'satisfied');
    expect(result.observedValue, '3.0');
  });
}
