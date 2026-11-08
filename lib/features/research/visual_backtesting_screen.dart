import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/backtesting/strategy_definition.dart';
import '../../data/repositories/visual_backtesting_repository.dart';
import '../../widgets/common.dart';
import 'automatic_backtest_screen.dart';
import 'visual_experiments_screen.dart';
import 'visual_strategy_form_screen.dart';
import 'visual_test_screen.dart';

class VisualBacktestingScreen extends ConsumerWidget {
  const VisualBacktestingScreen({super.key});

  Future<void> _openStrategyForm(
    BuildContext context, {
    String? strategyId,
    String? versionId,
  }) async {
    await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        builder: (_) => VisualStrategyFormScreen(
          strategyId: strategyId,
          versionId: versionId,
        ),
      ),
    );
  }

  Future<void> _openManualTest(
    BuildContext context,
    Rec strategy,
    Rec version,
  ) async {
    try {
      final selected = await _chooseScenario(context, version);
      if (selected == null || !context.mounted) return;
      await Navigator.push<String>(
        context,
        MaterialPageRoute<String>(
          builder: (_) => VisualTestScreen(
            strategyId: strategy.s('id'),
            strategyVersionId: version.s('id'),
            scenarioId: selected,
            mode: 'manual',
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) snack(context, 'Could not start test: $e');
    }
  }

  Future<void> _openAutomaticTest(
    BuildContext context,
    Rec strategy,
    Rec version,
  ) async {
    try {
      final selected = await _chooseScenario(context, version);
      if (selected == null || !context.mounted) return;
      await Navigator.push<String>(
        context,
        MaterialPageRoute<String>(
          builder: (_) => AutomaticBacktestScreen(
            strategyId: strategy.s('id'),
            strategyVersionId: version.s('id'),
            scenarioId: selected,
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        snack(context, 'Could not start OHLC evaluation: $error');
      }
    }
  }

  Future<String?> _chooseScenario(
    BuildContext context,
    Rec version,
  ) async {
    final definition = visualStrategyDefinitionFromVersion(version);
    return showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Choose entry scenario'),
              subtitle:
                  Text('Each scenario is tested and reported separately.'),
            ),
            for (final scenario in definition.scenarios)
              ListTile(
                leading: const Icon(Icons.alt_route),
                title: Text(scenario.name),
                subtitle: scenario.description.isEmpty
                    ? null
                    : Text(scenario.description),
                onTap: () => Navigator.pop(sheetContext, scenario.id),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _resumeManualTest(
    BuildContext context,
    WidgetRef ref,
    Rec test,
  ) async {
    final versionId = test.sn('strategy_version_id');
    if (versionId == null || test.s('mode') != 'manual') return;
    try {
      final repo = ref.read(visualBacktestingRepositoryProvider);
      final version = await repo.strategyVersionById(versionId);
      if (version == null) {
        throw StateError('Saved strategy version not found.');
      }
      final definition = visualStrategyDefinitionFromVersion(version);
      final scenarioId = test.sn('scenario_id') ??
          (definition.scenarios.isEmpty ? null : definition.scenarios.first.id);
      if (scenarioId == null) {
        throw StateError('Saved test has no entry scenario.');
      }
      if (!context.mounted) return;
      await Navigator.push<String>(
        context,
        MaterialPageRoute<String>(
          builder: (_) => VisualTestScreen(
            strategyId: test.s('strategy_id'),
            strategyVersionId: versionId,
            scenarioId: scenarioId,
            mode: 'manual',
            testId: test.s('id'),
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) snack(context, 'Could not resume test: $error');
    }
  }

  Widget _stats(VisualBacktestStats stats, BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        Text('Setups ${stats.totalSetups}', style: style),
        Text('Valid entries ${stats.validEntries}', style: style),
        Text('Rejected ${stats.rejectedSetups}', style: style),
        Text('Skipped ${stats.skippedTrades}', style: style),
        Text('Invalidated ${stats.invalidatedSetups}', style: style),
        Text('Trades ${stats.testCount}', style: style),
        Text('Incomplete ${stats.incompleteCount}', style: style),
        Text('Wins ${stats.wins}', style: style),
        Text('Losses ${stats.losses}', style: style),
        Text('Breakeven ${stats.breakeven}', style: style),
        Text(
          'Win rate (excl. BE) ${stats.winRate == null ? '—' : '${(stats.winRate! * 100).toStringAsFixed(1)}%'}',
          style: style,
        ),
        Text(
          'Average R ${stats.meanR == null ? '—' : '${stats.meanR!.toStringAsFixed(2)} (${stats.rSampleCount} known)'}',
          style: style,
        ),
        Text(
          'Total R ${stats.totalR == null ? '—' : '${stats.totalR!.toStringAsFixed(2)} (${stats.rSampleCount} known)'}',
          style: style,
        ),
        Text(
          'R profit factor ${stats.profitFactorR == null ? '—' : stats.profitFactorR!.toStringAsFixed(2)}',
          style: style,
        ),
        Text(
          'Cash profit factor ${stats.profitFactorCash == null ? '—' : '${stats.profitFactorCash!.toStringAsFixed(2)} ${stats.cashCurrency ?? ''}'} (${stats.cashSampleCount} saved; same-currency completed sample required)',
          style: style,
        ),
        Text(
          'Max drawdown ${stats.maxDrawdownR == null ? '—' : '${stats.maxDrawdownR!.toStringAsFixed(2)} R'}',
          style: style,
        ),
        Text(
          'Rule adherence ${stats.ruleAdherenceRate == null ? '—' : '${(stats.ruleAdherenceRate! * 100).toStringAsFixed(1)}% (${stats.ruleAdherenceSampleCount} known)'}',
          style: style,
        ),
        if (stats.missingRSampleCount > 0)
          Text('Missing R ${stats.missingRSampleCount}', style: style),
        if (stats.missingAdherenceSampleCount > 0)
          Text(
            'Missing rule-adherence data ${stats.missingAdherenceSampleCount}',
            style: style,
          ),
        Text('Rule violations ${stats.ruleViolationCount}', style: style),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strategies = ref.watch(visualStrategiesProvider);
    final results = ref.watch(visualTestResultsProvider);
    final tests = ref.watch(visualTestsProvider(null));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Study & backtesting'),
        actions: [
          IconButton(
            tooltip: 'Strategy experiments',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const VisualExperimentsScreen(),
              ),
            ),
            icon: const Icon(Icons.compare_arrows),
          ),
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
                'Manual screenshot tests evaluate rules by your input. Automatic mode evaluates only supported numeric rules on imported OHLC data. Neither mode recognizes visual market concepts from image pixels.',
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Strategies and saved versions',
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
                  'No strategies yet. Create a versioned strategy before testing.',
                );
              }
              return Column(
                children: [
                  for (final strategy in items)
                    _VersionedStrategyCard(
                      strategy: strategy,
                      tests: results.valueOrNull ?? const <Rec>[],
                      versions: ref.watch(
                        visualStrategyVersionsProvider(strategy.s('id')),
                      ),
                      onEdit: (versionId) => _openStrategyForm(
                        context,
                        strategyId: strategy.s('id'),
                        versionId: versionId,
                      ),
                      onCreateVersion: () => _openStrategyForm(
                        context,
                        strategyId: strategy.s('id'),
                      ),
                      onTest: (version) =>
                          _openManualTest(context, strategy, version),
                      onAutomatic: (version) =>
                          _openAutomaticTest(context, strategy, version),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text('Test records', style: Theme.of(context).textTheme.titleMedium),
          if (results.hasError)
            EmptyState('Could not load performance records: ${results.error}')
          else if (!results.hasValue)
            const LinearProgressIndicator()
          else
            _PerformanceOverview(
              results: results.value!,
              statsBuilder: _stats,
            ),
          tests.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => EmptyState('Could not load tests: $error'),
            data: (items) {
              if (items.isEmpty) {
                return const EmptyState('No tests have been recorded.');
              }
              return Column(
                children: [
                  for (final test in items)
                    Card(
                      child: ListTile(
                        leading: Icon(test.s('mode') == 'automatic'
                            ? Icons.functions
                            : Icons.image_search_outlined),
                        title: Text(
                          '${test.s('strategy_name_snapshot')} · '
                          '${test.s('scenario_id', 'unspecified scenario')} · '
                          '${pretty(test.s('entry_decision', 'incomplete'))}',
                        ),
                        subtitle: Text(
                          '${pretty(test.s('mode', 'manual'))} · '
                          'v${test.i('strategy_version_number')} · '
                          '${test.s('instrument', 'Unknown instrument')} '
                          '${test.s('timeframe')} · '
                          '${formatLocalDate(test.sn('tested_at'))}'
                          '${test['result_r'] is num ? ' · ${numToText((test['result_r'] as num).toDouble())} R' : ''}',
                        ),
                        onTap: test.s('mode') == 'manual' &&
                                test.i('strategy_version_number') > 0 &&
                                test.s('scenario_id').isNotEmpty
                            ? () => _resumeManualTest(context, ref, test)
                            : null,
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

class _VersionedStrategyCard extends StatelessWidget {
  const _VersionedStrategyCard({
    required this.strategy,
    required this.tests,
    required this.versions,
    required this.onEdit,
    required this.onCreateVersion,
    required this.onTest,
    required this.onAutomatic,
  });

  final Rec strategy;
  final List<Rec> tests;
  final AsyncValue<List<Rec>> versions;
  final ValueChanged<String> onEdit;
  final VoidCallback onCreateVersion;
  final ValueChanged<Rec> onTest;
  final ValueChanged<Rec> onAutomatic;

  @override
  Widget build(BuildContext context) => Card(
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
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Create a new immutable version',
                    onPressed: onCreateVersion,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
              versions.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text('Could not load versions: $error'),
                data: (items) {
                  if (items.isEmpty) {
                    return const EmptyState('No saved strategy versions.');
                  }
                  return Column(
                    children: [
                      for (final version in items)
                        _StrategyVersionTile(
                          strategy: strategy,
                          version: version,
                          tests: tests
                              .where((test) =>
                                  test.s('strategy_version_id') ==
                                  version.s('id'))
                              .toList(),
                          onEdit: () => onEdit(version.s('id')),
                          onTest: () => onTest(version),
                          onAutomatic: () => onAutomatic(version),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
}

class _StrategyVersionTile extends StatelessWidget {
  const _StrategyVersionTile({
    required this.strategy,
    required this.version,
    required this.tests,
    required this.onEdit,
    required this.onTest,
    required this.onAutomatic,
  });

  final Rec strategy;
  final Rec version;
  final List<Rec> tests;
  final VoidCallback onEdit;
  final VoidCallback onTest;
  final VoidCallback onAutomatic;

  @override
  Widget build(BuildContext context) {
    final number = version.i('version_number');
    final label = number == 0 ? 'Legacy snapshot' : 'Version $number';
    VisualStrategyDefinition? definition;
    Object? definitionError;
    try {
      definition = visualStrategyDefinitionFromVersion(version);
    } catch (error) {
      definitionError = error;
    }
    final stats = VisualBacktestStats.fromTests(tests);

    return ExpansionTile(
      key: ValueKey(version.s('id')),
      title: Text('$label · ${version.s('name', strategy.s('name'))}'),
      subtitle:
          Text('${tests.length} test record(s) · ${stats.testCount} completed'),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        if (definitionError != null)
          Text('Could not read strategy definition: $definitionError')
        else if (definition != null) ...[
          Text(
            'Instruments: ${definition.instruments.isEmpty ? 'Any' : definition.instruments.join(', ')}',
          ),
          Text(
            'Timeframes: ${definition.timeframes.join(', ')} · Sessions: ${definition.sessions.join(', ')}',
          ),
          for (final scenario in definition.scenarios)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alt_route),
              title: Text(scenario.name),
              subtitle: Text(scenario.description),
            ),
          _StatsView(stats: stats),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Create next version'),
            ),
            FilledButton.tonalIcon(
              onPressed: number == 0 ? null : onTest,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Manual screenshot test'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: number == 0 ? null : onAutomatic,
              icon: const Icon(Icons.functions),
              label: const Text('Automatic OHLC'),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatsView extends StatelessWidget {
  const _StatsView({required this.stats});

  final VisualBacktestStats stats;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 14,
        runSpacing: 4,
        children: [
          Text('Setups ${stats.totalSetups}'),
          Text('Valid ${stats.validEntries}'),
          Text('Rejected ${stats.rejectedSetups}'),
          Text('Skipped ${stats.skippedTrades}'),
          Text('Invalidated ${stats.invalidatedSetups}'),
          Text('Completed trades ${stats.testCount}'),
          Text(
            'Win rate ${stats.winRate == null ? '—' : '${(stats.winRate! * 100).toStringAsFixed(1)}%'}',
          ),
          Text(
            'Average R ${stats.meanR == null ? '—' : '${stats.meanR!.toStringAsFixed(2)} (${stats.rSampleCount} known)'}',
          ),
          Text(
            'Total R ${stats.totalR == null ? '—' : stats.totalR!.toStringAsFixed(2)}',
          ),
          Text(
            'R profit factor ${stats.profitFactorR == null ? '—' : stats.profitFactorR!.toStringAsFixed(2)}',
          ),
          Text(
            'Cash profit factor ${stats.profitFactorCash == null ? '—' : '${stats.profitFactorCash!.toStringAsFixed(2)} ${stats.cashCurrency ?? ''}'} (${stats.cashSampleCount} saved)',
          ),
          Text(
            'Max drawdown ${stats.maxDrawdownR == null ? '—' : '${stats.maxDrawdownR!.toStringAsFixed(2)} R'}',
          ),
          Text(
            'Rule adherence ${stats.ruleAdherenceRate == null ? '—' : '${(stats.ruleAdherenceRate! * 100).toStringAsFixed(1)}%'}',
          ),
          if (stats.missingRSampleCount > 0)
            Text('Completed trades missing R ${stats.missingRSampleCount}'),
        ],
      );
}

class _PerformanceOverview extends StatelessWidget {
  const _PerformanceOverview({
    required this.results,
    required this.statsBuilder,
  });

  final List<Rec> results;
  final Widget Function(VisualBacktestStats, BuildContext) statsBuilder;

  @override
  Widget build(BuildContext context) {
    final stats = VisualBacktestStats.fromTests(results);
    final dimensions = <String, String Function(Rec)>{
      'Strategy version': (test) =>
          '${test.s('strategy_name_snapshot', 'Unknown strategy')} · v${test.i('strategy_version_number')}',
      'Instrument': (test) => test.s('instrument', 'Unknown instrument'),
      'Timeframe': (test) => test.s('timeframe', 'Unknown timeframe'),
      'Session': (test) => test.s('session', 'Unknown session'),
      'Result currency': (test) =>
          test.s('result_currency', 'No / mixed currency'),
    };
    return ExpansionTile(
      title: Text('${stats.totalSetups} total setup(s) across saved versions'),
      subtitle: const Text(
        'Metrics use only recorded outcomes and known R results; small samples are not a reliability claim.',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: statsBuilder(stats, context),
        ),
        for (final dimension in dimensions.entries)
          ExpansionTile(
            title: Text('Performance by ${dimension.key.toLowerCase()}'),
            children: [
              for (final group in _groupBy(results, dimension.value).entries)
                ExpansionTile(
                  title: Text(group.key),
                  subtitle: Text('${group.value.length} test record(s)'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: statsBuilder(
                        VisualBacktestStats.fromTests(group.value),
                        context,
                      ),
                    ),
                  ],
                ),
            ],
          ),
      ],
    );
  }

  Map<String, List<Rec>> _groupBy(
    List<Rec> tests,
    String Function(Rec) keyOf,
  ) {
    final groups = <String, List<Rec>>{};
    for (final test in tests) {
      groups.putIfAbsent(keyOf(test), () => []).add(test);
    }
    return groups;
  }
}
