import '../../core/rows.dart';
import 'strategy_definition.dart';

class VisualRuleEvaluation {
  const VisualRuleEvaluation({
    required this.state,
    required this.observedValue,
  });

  final String state;
  final String? observedValue;
}

VisualRuleEvaluation evaluateVisualNumericRule(
  VisualStrategyRule rule,
  List<Rec> candles,
) {
  if (rule.mode != 'numeric') {
    throw StateError('Only numeric strategy rules can be evaluated on OHLC.');
  }
  if (candles.isEmpty) {
    return const VisualRuleEvaluation(state: 'pending', observedValue: null);
  }

  final value =
      _metricAt(rule.metric, candles, candles.length - 1, rule.period);
  if (value == null || !value.isFinite) {
    return const VisualRuleEvaluation(state: 'pending', observedValue: null);
  }
  final threshold = rule.threshold!;
  final previous = _metricAt(
    rule.metric,
    candles,
    candles.length - 2,
    rule.period,
  );
  final satisfied = switch (rule.comparator) {
    '>' => value > threshold,
    '>=' => value >= threshold,
    '<' => value < threshold,
    '<=' => value <= threshold,
    'cross_above' =>
      previous != null && previous <= threshold && value > threshold,
    'cross_below' =>
      previous != null && previous >= threshold && value < threshold,
    _ => false,
  };
  return VisualRuleEvaluation(
    state: satisfied ? 'satisfied' : 'failed',
    observedValue: value.toString(),
  );
}

double? _metricAt(
  String metric,
  List<Rec> candles,
  int index,
  int period,
) {
  if (index < 0 || index >= candles.length) return null;
  final candle = candles[index];
  double? value(String key) => (candle[key] as num?)?.toDouble();

  switch (metric) {
    case 'open':
    case 'high':
    case 'low':
    case 'close':
    case 'tick_volume':
    case 'real_volume':
    case 'spread':
      return value(metric);
    case 'previous_open':
    case 'previous_high':
    case 'previous_low':
    case 'previous_close':
      if (index == 0) return null;
      return (candles[index - 1][metric.substring('previous_'.length)] as num?)
          ?.toDouble();
    case 'range':
      final high = value('high');
      final low = value('low');
      return high == null || low == null ? null : high - low;
    case 'body':
      final open = value('open');
      final close = value('close');
      return open == null || close == null ? null : close - open;
    case 'sma':
      if (index + 1 < period) return null;
      var total = 0.0;
      for (var i = index - period + 1; i <= index; i++) {
        final close = (candles[i]['close'] as num?)?.toDouble();
        if (close == null) return null;
        total += close;
      }
      return total / period;
    case 'ema':
      if (index + 1 < period) return null;
      final alpha = 2 / (period + 1);
      var initialTotal = 0.0;
      for (var i = 0; i < period; i++) {
        final close = (candles[i]['close'] as num?)?.toDouble();
        if (close == null) return null;
        initialTotal += close;
      }
      var ema = initialTotal / period;
      for (var i = period; i <= index; i++) {
        final close = (candles[i]['close'] as num?)?.toDouble();
        if (close == null) return null;
        ema = alpha * close + (1 - alpha) * ema;
      }
      return ema;
    case 'rsi':
      if (index < period) return null;
      var gains = 0.0;
      var losses = 0.0;
      for (var i = 1; i <= period; i++) {
        final current = (candles[i]['close'] as num?)?.toDouble();
        final previous = (candles[i - 1]['close'] as num?)?.toDouble();
        if (current == null || previous == null) return null;
        final change = current - previous;
        if (change > 0) {
          gains += change;
        } else {
          losses -= change;
        }
      }
      var averageGain = gains / period;
      var averageLoss = losses / period;
      for (var i = period + 1; i <= index; i++) {
        final current = (candles[i]['close'] as num?)?.toDouble();
        final previous = (candles[i - 1]['close'] as num?)?.toDouble();
        if (current == null || previous == null) return null;
        final change = current - previous;
        averageGain =
            (averageGain * (period - 1) + (change > 0 ? change : 0)) / period;
        averageLoss =
            (averageLoss * (period - 1) + (change < 0 ? -change : 0)) / period;
      }
      if (averageLoss == 0) return 100;
      final relativeStrength = averageGain / averageLoss;
      return 100 - 100 / (1 + relativeStrength);
    case 'atr':
      if (index < period) return null;
      var total = 0.0;
      double? trueRangeAt(int i) {
        final high = (candles[i]['high'] as num?)?.toDouble();
        final low = (candles[i]['low'] as num?)?.toDouble();
        final previousClose = (candles[i - 1]['close'] as num?)?.toDouble();
        if (high == null || low == null || previousClose == null) return null;
        return [
          high - low,
          (high - previousClose).abs(),
          (low - previousClose).abs(),
        ].reduce((a, b) => a > b ? a : b);
      }
      for (var i = 1; i <= period; i++) {
        final range = trueRangeAt(i);
        if (range == null) return null;
        total += range;
      }
      var atr = total / period;
      for (var i = period + 1; i <= index; i++) {
        final range = trueRangeAt(i);
        if (range == null) return null;
        atr = (atr * (period - 1) + range) / period;
      }
      return atr;
    default:
      return null;
  }
}
