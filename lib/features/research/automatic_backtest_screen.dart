import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/backtesting/strategy_definition.dart';
import '../../data/backtesting/visual_numeric_evaluator.dart';
import '../../widgets/common.dart';

class AutomaticBacktestScreen extends ConsumerStatefulWidget {
  const AutomaticBacktestScreen({
    super.key,
    required this.strategyId,
    required this.strategyVersionId,
    required this.scenarioId,
  });

  final String strategyId;
  final String strategyVersionId;
  final String scenarioId;

  @override
  ConsumerState<AutomaticBacktestScreen> createState() =>
      _AutomaticBacktestScreenState();
}

class _AutomaticBacktestScreenState
    extends ConsumerState<AutomaticBacktestScreen> {
  VisualStrategyDefinition? _definition;
  List<Rec> _datasets = const [];
  String? _datasetId;
  DateTime _decisionAt = DateTime.now();
  bool _loading = true;
  bool _running = false;
  String? _error;
  String? _savedTestId;
  String? _savedDecision;
  Map<String, String> _savedStates = const {};
  Map<String, String?> _observedValues = const {};
  Rec? _savedCandle;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repository = ref.read(visualBacktestingRepositoryProvider);
      final version =
          await repository.strategyVersionById(widget.strategyVersionId);
      if (version == null || version.s('strategy_id') != widget.strategyId) {
        throw StateError('The selected strategy version is unavailable.');
      }
      final definition = visualStrategyDefinitionFromVersion(version);
      if (!definition.scenarios.any((item) => item.id == widget.scenarioId)) {
        throw StateError('The selected entry scenario is unavailable.');
      }
      final datasets =
          await ref.read(historicalDataRepositoryProvider).datasets();
      _definition = definition;
      _datasets = datasets;
      final matching = datasets.where(_matchesStrategy).toList();
      _datasetId = matching.isEmpty ? null : matching.first.s('id');
    } catch (error) {
      _error = '$error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _matchesStrategy(Rec dataset) {
    final definition = _definition;
    if (definition == null) return false;
    return (definition.instruments.isEmpty ||
            definition.instruments.contains(dataset.s('instrument'))) &&
        definition.timeframes
            .contains(canonicalVisualTimeframe(dataset.s('timeframe')));
  }

  List<VisualStrategyRule> _applicableRules(
    VisualStrategyDefinition definition,
  ) =>
      definition.rules
          .where((rule) =>
              rule.scenarioId == null || rule.scenarioId == widget.scenarioId)
          .toList();

  Future<void> _run() async {
    final definition = _definition;
    final dataset =
        _datasets.where((item) => item.s('id') == _datasetId).firstOrNull;
    if (definition == null || dataset == null || _running) return;
    final rules = _applicableRules(definition);
    final unsupported = rules.where((rule) => rule.mode != 'numeric').toList();
    if (unsupported.isNotEmpty) {
      snack(
        context,
        'Automatic OHLC evaluation cannot run because this version has manual-only rules: ${unsupported.map((rule) => rule.label).join(', ')}',
      );
      return;
    }
    if (rules.isEmpty) {
      snack(context, 'This scenario has no applicable strategy rules.');
      return;
    }

    setState(() {
      _running = true;
      _error = null;
      _savedTestId = null;
    });
    try {
      final candleRepository = ref.read(historicalDataRepositoryProvider);
      final throughTimestamp = _decisionAt.toUtc().millisecondsSinceEpoch;
      final candles = await candleRepository.candlesUpTo(
        datasetId: dataset.s('id'),
        throughTimestampMs: throughTimestamp,
        limit: 5000,
      );
      if (candles.isEmpty) {
        throw StateError(
          'No candle is available at or before the selected decision time.',
        );
      }
      final decisionCandle = candles.last;
      final timestamp = decisionCandle['timestamp_ms'] as int;
      final testId = await ref
          .read(visualBacktestingRepositoryProvider)
          .startTest(
            strategyId: widget.strategyId,
            strategyVersionId: widget.strategyVersionId,
            scenarioId: widget.scenarioId,
            mode: 'automatic',
            testedAt: DateTime.fromMillisecondsSinceEpoch(
              timestamp,
              isUtc: true,
            ).toIso8601String(),
            instrument: dataset.s('instrument'),
            timeframe: dataset.s('timeframe'),
            session: '',
            marketContext: 'Automatic OHLC evaluation at a selected candle.',
            datasetId: dataset.s('id'),
          );
      if (mounted) setState(() => _savedTestId = testId);

      final repository = ref.read(visualBacktestingRepositoryProvider);
      final states = <String, String>{};
      final observedValues = <String, String?>{};
      final stageComplete = <String, bool>{};
      for (final rule in definition.rules.where(
        (rule) =>
            rule.scenarioId != null &&
            rule.scenarioId != widget.scenarioId,
      )) {
        await repository.recordRuleState(
          testId: testId,
          ruleId: rule.id,
          state: 'not_applicable',
          explanation: 'Rule belongs to a different entry scenario.',
          eventTimestampMs: timestamp,
          automatic: true,
        );
      }
      for (final stage in definition.stages) {
        final stageReady = stage.dependsOn.every(
          (id) => stageComplete[id] == true,
        );
        final stageRules = rules.where((rule) => rule.stageId == stage.id);
        for (final rule in stageRules) {
          String state;
          String? observedValue;
          if (!stageReady || !canEvaluateVisualRule(rule, states)) {
            state = 'pending';
          } else if (rule.relation == 'invalidate' &&
              rule.dependsOn.any((id) => states[id] == 'satisfied')) {
            state = 'invalidated';
          } else {
            final evaluation = evaluateVisualNumericRule(rule, candles);
            state = evaluation.state;
            observedValue = evaluation.observedValue;
          }
          states[rule.id] = state;
          observedValues[rule.id] = observedValue;
          await repository.recordRuleState(
            testId: testId,
            ruleId: rule.id,
            state: state,
            explanation: state == 'pending'
                ? 'Not evaluable at this decision point.'
                : 'Evaluated using candles available through ${DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true).toIso8601String()}.',
            observedValue: observedValue,
            eventTimestampMs: timestamp,
            automatic: true,
          );
        }
        final required = stageRules.where((rule) => rule.required);
        stageComplete[stage.id] = stageReady &&
            required.every((rule) =>
                states[rule.id] == 'satisfied' ||
                states[rule.id] == 'not_applicable');
      }

      final checklist = buildVisualChecklist(
        definition: definition,
        scenarioId: widget.scenarioId,
        states: states,
      );
      final stayOutApplies = rules.any((rule) =>
          rule.blocksEntryWhenSatisfied && states[rule.id] == 'satisfied');
      final decision = checklist.canRecordEntry
          ? 'valid_entry'
          : stayOutApplies
              ? 'skipped_trade'
              : checklist.hasInvalidatedRule
                  ? 'invalidated_setup'
                  : 'rejected_setup';
      await repository.lockDecision(
        testId: testId,
        decision: decision,
        explanation:
            'Automatic numeric-rule evaluation. Only candles at or before the recorded decision time were read.',
        eventTimestampMs: timestamp,
      );
      if (!mounted) return;
      setState(() {
        _savedDecision = decision;
        _savedStates = states;
        _observedValues = observedValues;
        _savedCandle = decisionCandle;
        _decisionAt = DateTime.fromMillisecondsSinceEpoch(
          timestamp,
          isUtc: true,
        ).toLocal();
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
        snack(context, 'Automatic evaluation stopped: $error');
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final definition = _definition;
    final matching = _datasets.where(_matchesStrategy).toList();
    final dataset =
        matching.where((item) => item.s('id') == _datasetId).firstOrNull;
    final scenario = definition?.scenarios
        .where((item) => item.id == widget.scenarioId)
        .firstOrNull;
    final rules = definition == null
        ? const <VisualStrategyRule>[]
        : _applicableRules(definition);

    return Scaffold(
      appBar: AppBar(title: const Text('Automatic OHLC evaluation')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && definition == null
              ? EmptyState('Could not load automatic testing: $_error')
              : definition == null
                  ? const EmptyState('Strategy version is unavailable.')
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        SectionCard(
                          title: 'Version and scenario',
                          children: [
                            Text(definition.name),
                            Text(
                              scenario == null
                                  ? 'Entry scenario unavailable'
                                  : scenario.name,
                            ),
                            const Text(
                              'This mode evaluates supported numeric rules on imported OHLC data. It does not interpret screenshots or simulate fills, stop/target execution, costs, or trade outcomes.',
                            ),
                          ],
                        ),
                        if (matching.isEmpty)
                          const EmptyState(
                            'No compatible imported OHLC dataset. Import CSV data for an instrument and timeframe allowed by this strategy.',
                          )
                        else ...[
                          DropdownButtonFormField<String>(
                            value: _datasetId,
                            decoration: const InputDecoration(
                              labelText: 'Historical dataset',
                            ),
                            items: matching
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item.s('id'),
                                    child: Text(
                                      '${item.s('instrument')} ${item.s('timeframe')} · ${item.s('candle_count')} candles · ${item.s('source_name')}',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _savedTestId != null
                                ? null
                                : (value) => setState(() => _datasetId = value),
                          ),
                          if (dataset != null)
                            Text(
                              'Range: ${DateTime.fromMillisecondsSinceEpoch(dataset.i('first_timestamp_ms'), isUtc: true).toLocal()} — ${DateTime.fromMillisecondsSinceEpoch(dataset.i('last_timestamp_ms'), isUtc: true).toLocal()} · ${dataset.i('gap_count')} missing-period gap(s)',
                            ),
                          PickerField(
                            label: 'Decision point',
                            text: formatLocalDateTime(
                              _decisionAt.toUtc().toIso8601String(),
                            ),
                            enabled: _savedTestId == null,
                            onTap: () async {
                              final date =
                                  await pickDateTime(context, _decisionAt);
                              if (date != null) {
                                setState(() => _decisionAt = date);
                              }
                            },
                          ),
                          if (rules.any((rule) => rule.mode != 'numeric'))
                            const SectionCard(
                              title: 'Manual-only conditions block automation',
                              children: [
                                Text(
                                  'This strategy version includes manually evaluated concepts. Automatic mode will not guess their state; create a numeric-only version for OHLC evaluation.',
                                ),
                              ],
                            ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          FilledButton.icon(
                            onPressed:
                                _running || _savedTestId != null ? null : _run,
                            icon: _running
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.functions),
                            label: Text(
                              _running
                                  ? 'Evaluating available OHLC...'
                                  : 'Evaluate selected candle',
                            ),
                          ),
                        ],
                        if (_savedTestId != null) ...[
                          const SizedBox(height: 12),
                          SectionCard(
                            title: 'Saved decision point',
                            children: [
                              Text(
                                'Time: ${formatLocalDateTime(_decisionAt.toUtc().toIso8601String())}',
                              ),
                              Text(
                                'Decision: ${pretty(_savedDecision)}',
                              ),
                              Text(
                                'OHLC: ${_ohlcSummary(_savedCandle)}',
                              ),
                              const Text(
                                'The result remains incomplete until a verified execution and exit model is provided. No win/loss or R result was generated.',
                              ),
                            ],
                          ),
                          SectionCard(
                            title: 'Rule evaluation at this candle',
                            children: [
                              for (final rule in rules)
                                ListTile(
                                  leading: Icon(
                                    _stateIcon(
                                        _savedStates[rule.id] ?? 'pending'),
                                  ),
                                  title: Text(rule.label),
                                  subtitle: Text(
                                    '${pretty(_savedStates[rule.id] ?? 'pending')}'
                                    '${_observedValues[rule.id] == null ? '' : ' · observed ${_observedValues[rule.id]}'}',
                                  ),
                                ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                Navigator.pop(context, _savedTestId),
                            icon: const Icon(Icons.done),
                            label: const Text('Return to performance review'),
                          ),
                        ],
                      ],
                    ),
    );
  }

  String _ohlcSummary(Rec? candle) {
    if (candle == null) return 'Unavailable';
    String field(String key) => (candle[key] as num?)?.toString() ?? 'n/a';
    return 'O ${field('open')} · H ${field('high')} · L ${field('low')} · C ${field('close')}';
  }

  IconData _stateIcon(String state) => switch (state) {
        'satisfied' => Icons.check_circle_outline,
        'failed' => Icons.cancel_outlined,
        'invalidated' => Icons.block_outlined,
        'not_applicable' => Icons.remove_circle_outline,
        _ => Icons.hourglass_empty,
      };
}
