import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/repositories/visual_backtesting_repository.dart';
import '../../widgets/common.dart';
import 'visual_strategy_form_screen.dart';
import 'visual_test_screen.dart';

class VisualBacktestingScreen extends ConsumerWidget {
  const VisualBacktestingScreen({super.key});

  List<String> _list(Rec strategy, String key) {
    final decoded = jsonDecode(strategy.s(key, '[]'));
    if (decoded is! List || decoded.any((value) => value is! String)) {
      throw const FormatException('Saved strategy selections are invalid.');
    }
    return decoded.cast<String>();
  }

  Future<void> _openStrategyForm(
    BuildContext context, {
    String? strategyId,
  }) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => VisualStrategyFormScreen(strategyId: strategyId),
      ),
    );
  }

  Future<void> _openTest(
    BuildContext context, {
    required String strategyId,
    String? testId,
  }) async {
    await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        builder: (_) => VisualTestScreen(
          strategyId: strategyId,
          testId: testId,
        ),
      ),
    );
  }

  Widget _stats(VisualBacktestStats stats, BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        Text('Completed ${stats.testCount}', style: style),
        Text('Wins ${stats.wins}', style: style),
        Text('Losses ${stats.losses}', style: style),
        Text('Breakeven ${stats.breakeven}', style: style),
        Text(
          'Win rate (excl. BE) ${stats.winRate == null ? '—' : '${(stats.winRate! * 100).toStringAsFixed(1)}%'}',
          style: style,
        ),
        Text(
          'Average R ${stats.meanR == null ? '—' : stats.meanR!.toStringAsFixed(2)} (${stats.rSampleCount} known)',
          style: style,
        ),
        Text(
          'Max drawdown ${stats.maxDrawdownR == null ? '—' : '${stats.maxDrawdownR!.toStringAsFixed(2)} R'}',
          style: style,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strategies = ref.watch(visualStrategiesProvider);
    final tests = ref.watch(visualTestsProvider(null));
    final testResults = ref.watch(visualTestResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Visual backtesting'),
        actions: [
          IconButton(
            tooltip: 'Create strategy',
            onPressed: () => _openStrategyForm(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Screenshot-based tests are manual. The app does not extract OHLC data or infer trade outcomes from chart pixels. Only outcomes and R values you record are included in statistics.',
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Strategies',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _openStrategyForm(context),
                icon: const Icon(Icons.add),
                label: const Text('New strategy'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          strategies.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                EmptyState('Could not load strategies: $error'),
            data: (items) {
              if (items.isEmpty) {
                return const EmptyState(
                  'No strategies yet. Create a strategy with explicit rules before recording visual tests.',
                );
              }
              return Column(
                children: [
                  for (final strategy in items)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    strategy.s('name'),
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Edit strategy',
                                  onPressed: () => _openStrategyForm(
                                    context,
                                    strategyId: strategy.s('id'),
                                  ),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                              ],
                            ),
                            Text('Entry: ${strategy.s('entry_conditions')}'),
                            Text('Exit: ${strategy.s('exit_conditions')}'),
                            Text('Stop: ${strategy.s('stop_loss_rules')}'),
                            Text('Target: ${strategy.s('take_profit_rules')}'),
                            Text(
                                'Stay out: ${strategy.s('stay_out_conditions')}'),
                            const SizedBox(height: 4),
                            Text(
                              'Sessions: ${_list(strategy, 'sessions_json').join(', ')} · '
                              'Timeframes: ${_list(strategy, 'timeframes_json').join(', ')}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            if (testResults.hasError)
                              Text(
                                'Could not load statistics: ${testResults.error}',
                              )
                            else if (!testResults.hasValue)
                              const LinearProgressIndicator()
                            else
                              _stats(
                                VisualBacktestStats.fromTests(
                                  testResults.value!.where(
                                    (test) =>
                                        test.s('strategy_id') ==
                                        strategy.s('id'),
                                  ),
                                ),
                                context,
                              ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.tonalIcon(
                                onPressed: () => _openTest(
                                  context,
                                  strategyId: strategy.s('id'),
                                ),
                                icon: const Icon(Icons.fact_check_outlined),
                                label: const Text('Test a setup'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text('Recorded tests',
              style: Theme.of(context).textTheme.titleMedium),
          tests.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => EmptyState('Could not load tests: $error'),
            data: (items) {
              if (items.isEmpty) {
                return const EmptyState('No visual tests have been recorded.');
              }
              return Column(
                children: [
                  for (final test in items)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.image_search_outlined),
                        title: Text(
                          '${test.s('strategy_name')} · ${pretty(test.s('outcome'))}',
                        ),
                        subtitle: Text(
                          '${formatLocalDate(test.sn('tested_at'))} · '
                          '${test.i('image_count')} screenshot(s)'
                          '${test['result_r'] is num ? ' · ${numToText((test['result_r'] as num).toDouble())} R' : ''}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openTest(
                          context,
                          strategyId: test.s('strategy_id'),
                          testId: test.s('id'),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
