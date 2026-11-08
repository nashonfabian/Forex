import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/backtesting/strategy_definition.dart';
import '../../data/repositories/research_repository.dart';
import '../../data/repositories/visual_backtesting_repository.dart';
import '../../widgets/common.dart';
import 'image_import.dart';

class VisualTestScreen extends ConsumerStatefulWidget {
  const VisualTestScreen({
    super.key,
    required this.strategyId,
    required this.strategyVersionId,
    required this.scenarioId,
    required this.mode,
    this.testId,
    this.experimentId,
    this.experimentVariantId,
  });

  final String strategyId;
  final String strategyVersionId;
  final String scenarioId;
  final String mode;
  final String? testId;
  final String? experimentId;
  final String? experimentVariantId;

  @override
  ConsumerState<VisualTestScreen> createState() => _VisualTestScreenState();
}

class _VisualTestScreenState extends ConsumerState<VisualTestScreen> {
  final _instrument = TextEditingController();
  final _marketContext = TextEditingController();
  final _notes = TextEditingController();
  final _ruleExplanations = <String, String>{};
  final _ruleStates = <String, String>{};
  final _annotations = <String, List<Rec>>{};
  VisualStrategyDefinition? _definition;
  String? _testId;
  String? _strategyName;
  String? _timeframe;
  String? _session;
  String? _annotationKind;
  double _cutoffX = .65;
  DateTime _testedAt = DateTime.now();
  List<Rec> _images = const [];
  List<Rec> _events = const [];
  List<Rec> _ruleHistory = const [];
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _testId = widget.testId;
    if (widget.testId == null) {
      _loadVersion();
    } else {
      _loadExistingTest();
    }
  }

  @override
  void dispose() {
    _instrument.dispose();
    _marketContext.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    try {
      final repo = ref.read(visualBacktestingRepositoryProvider);
      final version = await repo.strategyVersionById(widget.strategyVersionId);
      if (version == null || version.s('strategy_id') != widget.strategyId) {
        throw StateError('The selected strategy version is unavailable.');
      }

      final definition = visualStrategyDefinitionFromVersion(version);
      if (!definition.scenarios.any((item) => item.id == widget.scenarioId)) {
        throw StateError('The selected entry scenario is unavailable.');
      }
      if (widget.mode != 'manual') {
        throw StateError('This screen supports manual screenshot tests only.');
      }
      _definition = definition;
      _strategyName = definition.name;
      _timeframe = definition.timeframes.first;
      _session = definition.sessions.first;
      _instrument.text = definition.instruments.firstOrNull ?? '';
      if (mounted) setState(() {});
    } catch (error) {
      _loadError = '$error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadExistingTest() async {
    try {
      final repo = ref.read(visualBacktestingRepositoryProvider);
      final test = await repo.testById(widget.testId!);
      if (test == null) throw StateError('Saved test not found.');
      if (test.s('strategy_id') != widget.strategyId ||
          test.s('strategy_version_id') != widget.strategyVersionId ||
          test.s('scenario_id') != widget.scenarioId ||
          test.s('mode') != 'manual') {
        throw StateError('Saved test does not match the selected version.');
      }
      final version = await repo.strategyVersionById(widget.strategyVersionId);
      if (version == null) {
        throw StateError('Saved strategy version not found.');
      }
      _definition = visualStrategyDefinitionFromVersion(version);
      _strategyName = test.s('strategy_name_snapshot');
      _instrument.text = test.s('instrument');
      _timeframe = test.sn('timeframe') ?? _definition!.timeframes.first;
      _session = test.sn('session') ?? _definition!.sessions.first;
      _marketContext.text = test.s('market_context');
      final parsedDate = DateTime.tryParse(test.s('tested_at'));
      if (parsedDate != null) _testedAt = parsedDate.toLocal();
      await _refresh();
    } catch (error) {
      _loadError = '$error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startTest() async {
    final definition = _definition;
    if (definition == null || _saving) return;
    if (_instrument.text.trim().isEmpty ||
        _timeframe == null ||
        _session == null) {
      snack(context, 'Enter the instrument, timeframe and session.');
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await ref.read(visualBacktestingRepositoryProvider).startTest(
            strategyId: widget.strategyId,
            strategyVersionId: widget.strategyVersionId,
            scenarioId: widget.scenarioId,
            mode: 'manual',
            testedAt: _testedAt.toUtc().toIso8601String(),
            instrument: _instrument.text.trim().toUpperCase(),
            timeframe: _timeframe!,
            session: _session!,
            marketContext: _marketContext.text,
            experimentId: widget.experimentId,
            experimentVariantId: widget.experimentVariantId,
          );
      final repo = ref.read(visualBacktestingRepositoryProvider);
      for (final rule in definition.rules.where(
        (rule) =>
            rule.scenarioId != null &&
            rule.scenarioId != widget.scenarioId,
      )) {
        await repo.recordRuleState(
          testId: id,
          ruleId: rule.id,
          state: 'not_applicable',
          explanation: 'Rule belongs to a different entry scenario.',
          decision: 'manual',
          eventTimestampMs: _testedAt.toUtc().millisecondsSinceEpoch,
        );
      }
      if (!mounted) return;
      setState(() => _testId = id);
      await _refresh();
    } catch (error) {
      if (mounted) snack(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refresh() async {
    final id = _testId;
    if (id == null) return;
    try {
      final repo = ref.read(visualBacktestingRepositoryProvider);
      final test = await repo.testById(id);
      if (test == null) throw StateError('Visual test not found.');
      final images = await repo.imagesForTest(id);
      final annotations = await repo.annotationsForTest(id);
      final states = await repo.latestRuleStates(id);
      final events = await repo.testEventHistory(id);
      final history = await repo.ruleStateHistory(id);
      if (!mounted) return;
      setState(() {
        _images = images;
        _ruleStates
          ..clear()
          ..addAll(states);
        _events = events;
        _ruleHistory = history;
        _ruleExplanations
          ..clear()
          ..addEntries(
            history
                .where((event) => event.sn('explanation') != null)
                .map(
                  (event) => MapEntry(
                    event.s('rule_id'),
                    event.s('explanation'),
                  ),
                ),
          );
        _notes.text = test.s('notes');
        _annotations.clear();
        for (final annotation in annotations) {
          _annotations
              .putIfAbsent(annotation.s('image_id'), () => [])
              .add(annotation);
        }
      });
    } catch (error) {
      if (mounted) snack(context, 'Could not refresh test: $error');
    }
  }

  Future<void> _importScreenshots() async {
    await pickAndImport(
      context,
      ref,
      instrument: _instrument.text.trim().toUpperCase(),
      timeframe: _timeframe,
      caption: 'Visual backtest screenshot',
    );
  }

  Future<void> _attachDecisionImage(Rec image) async {
    final id = _testId;
    if (id == null) return;
    try {
      await ref.read(visualBacktestingRepositoryProvider).addTestImage(
            testId: id,
            imageId: image.s('id'),
            role: 'decision',
            cutoffX: _cutoffX,
            decisionAtMs: _testedAt.toUtc().millisecondsSinceEpoch,
          );
      await _refresh();
    } catch (error) {
      if (mounted) snack(context, friendlyError(error));
    }
  }

  Future<void> _attachEvidence(Rec image) async {
    final id = _testId;
    if (id == null) return;
    try {
      await ref.read(visualBacktestingRepositoryProvider).addTestImage(
            testId: id,
            imageId: image.s('id'),
            role: 'evidence',
            decisionAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          );
      await _refresh();
    } catch (error) {
      if (mounted) snack(context, friendlyError(error));
    }
  }

  Future<void> _removeDecisionImage() async {
    final id = _testId;
    final image =
        _images.where((item) => item.s('test_role') == 'decision').firstOrNull;
    if (id == null || image == null) return;
    try {
      await ref.read(visualBacktestingRepositoryProvider).removeTestImage(
            testId: id,
            imageId: image.s('id'),
          );
      await _refresh();
    } catch (error) {
      if (mounted) snack(context, friendlyError(error));
    }
  }

  Future<void> _changeRuleState(VisualStrategyRule rule, String state) async {
    final id = _testId;
    if (id == null) return;
    final explanation = _ruleExplanations.putIfAbsent(
      rule.id,
      () => '',
    );
    try {
      await ref.read(visualBacktestingRepositoryProvider).recordRuleState(
            testId: id,
            ruleId: rule.id,
            state: state,
            explanation: explanation,
            decision: 'manual',
            eventTimestampMs: _testedAt.toUtc().millisecondsSinceEpoch,
          );
      await _refresh();
    } catch (error) {
      if (mounted) snack(context, friendlyError(error));
    }
  }

  Future<void> _editExplanation(VisualStrategyRule rule) async {
    final controller = TextEditingController(
      text: _ruleExplanations[rule.id] ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Evidence for ${rule.label}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Observation / evidence',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    setState(() => _ruleExplanations[rule.id] = value.trim());
    final state = _ruleStates[rule.id];
    if (state != null && state != 'pending') {
      await _changeRuleState(rule, state);
    }
  }

  Future<void> _addAnnotation(String imageId, double x, double y) async {
    final id = _testId;
    final kind = _annotationKind;
    if (id == null || kind == null) {
      snack(context, 'Choose a chart mark after starting the test.');
      return;
    }
    final label = TextEditingController(
      text: kind == 'observation' ? '' : pretty(kind),
    );
    final price = TextEditingController();
    final value = await showDialog<({String label, double? price})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Add ${pretty(kind).toLowerCase()} mark'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: label,
              decoration: InputDecoration(
                labelText: kind == 'observation' ? 'Observation' : 'Label',
              ),
            ),
            TextField(
              controller: price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Price (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed =
                  price.text.trim().isEmpty ? null : parseDouble(price.text);
              if (price.text.trim().isNotEmpty && parsed == null) {
                snack(dialogContext, 'Enter a valid finite price.');
                return;
              }
              if (kind == 'observation' && label.text.trim().isEmpty) {
                snack(dialogContext, 'Enter an observation.');
                return;
              }
              Navigator.pop(
                dialogContext,
                (label: label.text.trim(), price: parsed),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    label.dispose();
    price.dispose();
    if (value == null || !mounted) return;
    try {
      await ref.read(visualBacktestingRepositoryProvider).addAnnotation(
            testId: id,
            imageId: imageId,
            kind: kind,
            x: x,
            y: y,
            label: value.label,
            price: value.price,
          );
      await _refresh();
    } catch (error) {
      if (mounted) snack(context, friendlyError(error));
    }
  }

  Future<void> _lockDecision(String decision) async {
    final id = _testId;
    if (id == null) return;
    final explanation = TextEditingController();
    final confirmed = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Lock ${pretty(decision).toLowerCase()} decision?'),
        content: TextField(
          controller: explanation,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Reason (recommended)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, explanation.text.trim()),
            child: const Text('Lock decision'),
          ),
        ],
      ),
    );
    explanation.dispose();
    if (confirmed == null || !mounted) return;
    try {
      await ref.read(visualBacktestingRepositoryProvider).lockDecision(
            testId: id,
            decision: decision,
            explanation: confirmed,
            eventTimestampMs: _testedAt.toUtc().millisecondsSinceEpoch,
          );
      await _refresh();
    } catch (error) {
      if (mounted) snack(context, friendlyError(error));
    }
  }

  Future<void> _saveDraftNotes() async {
    final id = _testId;
    if (id == null) return;
    try {
      await ref.read(visualBacktestingRepositoryProvider).saveTestNotes(
            testId: id,
            notes: _notes.text,
          );
      if (mounted) snack(context, 'Notes saved locally.');
    } catch (error) {
      if (mounted) snack(context, friendlyError(error));
    }
  }

  Future<void> _recordTradeEvent(String kind) async {
    final id = _testId;
    if (id == null) return;
    final price = TextEditingController();
    final quantity = TextEditingController();
    final notes = TextEditingController();
    final result =
        await showDialog<({double? price, double? quantity, String notes})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(pretty(kind)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (kind != 'management_decision' && kind != 'uncertainty')
              TextField(
                controller: price,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Price (optional)'),
              ),
            if (kind == 'entry' || kind == 'partial_close')
              TextField(
                controller: quantity,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Quantity (optional)'),
              ),
            TextField(
              controller: notes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Decision / notes'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsedPrice =
                  price.text.trim().isEmpty ? null : parseDouble(price.text);
              final parsedQuantity = quantity.text.trim().isEmpty
                  ? null
                  : parseDouble(quantity.text);
              if (price.text.trim().isNotEmpty && parsedPrice == null ||
                  quantity.text.trim().isNotEmpty && parsedQuantity == null) {
                snack(dialogContext, 'Enter valid finite numeric values.');
                return;
              }
              Navigator.pop(
                dialogContext,
                (
                  price: parsedPrice,
                  quantity: parsedQuantity,
                  notes: notes.text.trim(),
                ),
              );
            },
            child: const Text('Record event'),
          ),
        ],
      ),
    );
    price.dispose();
    quantity.dispose();
    notes.dispose();
    if (result == null || !mounted) return;
    try {
      await ref.read(visualBacktestingRepositoryProvider).recordExecutionEvent(
            testId: id,
            kind: kind,
            decision: 'manual',
            notes: result.notes,
            price: result.price,
            quantity: result.quantity,
          );
      await _refresh();
    } catch (error) {
      if (mounted) snack(context, friendlyError(error));
    }
  }

  Future<void> _completeTest({required bool isTrade}) async {
    final id = _testId;
    if (id == null) return;
    final outcome = ValueNotifier<String>(isTrade ? 'win' : 'not_traded');
    final adherence = ValueNotifier<String>('unknown');
    final resultR = TextEditingController();
    final entry = TextEditingController();
    final stop = TextEditingController();
    final target = TextEditingController();
    final exit = TextEditingController();
    final cashResult = TextEditingController();
    final currency = TextEditingController();
    final result = await showDialog<
        ({
          String outcome,
          String adherence,
          double? resultR,
          double? entry,
          double? stop,
          double? target,
          double? exit,
          double? cash,
          String currency,
        })>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Complete test record'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<String>(
                valueListenable: outcome,
                builder: (_, value, __) => DropdownButtonFormField<String>(
                  value: value,
                  decoration: const InputDecoration(labelText: 'Outcome'),
                  items: (isTrade
                          ? const ['win', 'loss', 'breakeven', 'inconclusive']
                          : const ['not_traded', 'inconclusive'])
                      .map((item) => DropdownMenuItem(
                            value: item,
                            child: Text(pretty(item)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) outcome.value = value;
                  },
                ),
              ),
              ValueListenableBuilder<String>(
                valueListenable: adherence,
                builder: (_, value, __) => DropdownButtonFormField<String>(
                  value: value,
                  decoration:
                      const InputDecoration(labelText: 'Rule adherence'),
                  items: const ['followed', 'violated', 'unknown']
                      .map((item) => DropdownMenuItem(
                            value: item,
                            child: Text(pretty(item)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) adherence.value = value;
                  },
                ),
              ),
              if (isTrade) ...[
                for (final (controller, label) in [
                  (entry, 'Entry price'),
                  (stop, 'Stop-loss price'),
                  (target, 'Take-profit price'),
                  (exit, 'Exit price'),
                  (resultR, 'Result in R (leave empty if unknown)'),
                ])
                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: InputDecoration(labelText: label),
                  ),
                TextField(
                  controller: cashResult,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Cash result (optional)',
                  ),
                ),
                TextField(
                  controller: currency,
                  textCapitalization: TextCapitalization.characters,
                  decoration:
                      const InputDecoration(labelText: 'Result currency'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              double? read(TextEditingController controller) =>
                  controller.text.trim().isEmpty
                      ? null
                      : parseDouble(controller.text);
              final controllers = [
                resultR,
                entry,
                stop,
                target,
                exit,
                cashResult,
              ];
              if (controllers.any((controller) =>
                  controller.text.trim().isNotEmpty &&
                  read(controller) == null)) {
                snack(dialogContext, 'Enter valid finite numeric values.');
                return;
              }
              Navigator.pop(
                dialogContext,
                (
                  outcome: outcome.value,
                  adherence: adherence.value,
                  resultR: read(resultR),
                  entry: read(entry),
                  stop: read(stop),
                  target: read(target),
                  exit: read(exit),
                  cash: read(cashResult),
                  currency: currency.text.trim().toUpperCase(),
                ),
              );
            },
            child: const Text('Complete'),
          ),
        ],
      ),
    );
    outcome.dispose();
    adherence.dispose();
    for (final controller in [
      resultR,
      entry,
      stop,
      target,
      exit,
      cashResult,
      currency,
    ]) {
      controller.dispose();
    }
    if (result == null || !mounted) return;
    try {
      await ref.read(visualBacktestingRepositoryProvider).completeTest(
            testId: id,
            outcome: result.outcome,
            resultR: result.resultR,
            notes: _notes.text,
            ruleAdherence: result.adherence,
            entryPrice: result.entry,
            stopLossPrice: result.stop,
            takeProfitPrice: result.target,
            exitPrice: result.exit,
            cashResult: result.cash,
            currency: result.currency.isEmpty ? null : result.currency,
          );
      await _refresh();
      if (mounted) snack(context, 'Test record completed and saved locally.');
    } catch (error) {
      if (mounted) snack(context, friendlyError(error));
    }
  }

  Future<void> _deleteTest() async {
    final id = _testId;
    if (id == null) return;
    final confirmed = await confirmDialog(
      context,
      title: 'Delete this test?',
      message: 'This will hide this visual test from performance records.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(visualBacktestingRepositoryProvider).deleteTest(id);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) snack(context, friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final gallery = ref.watch(galleryProvider(const GalleryFilter()));
    final definition = _definition;
    final testId = _testId;
    final decisionImage = _images
        .where((image) => image.s('test_role') == 'decision')
        .firstOrNull;
    final isLocked =
        _events.any((event) => event.s('kind') == 'entry_decision');
    final states = Map<String, String>.from(_ruleStates);
    final checklist = definition == null
        ? null
        : buildVisualChecklist(
            definition: definition,
            scenarioId: widget.scenarioId,
            states: states,
          );
    final scenario = definition?.scenarios
        .where((item) => item.id == widget.scenarioId)
        .firstOrNull;
    final isTrade = _events.any(
      (event) =>
          event.s('kind') == 'entry_decision' &&
          event.s('decision') == 'valid_entry',
    );
    final hasEntryEvent = _events.any((event) => event.s('kind') == 'entry');
    final hasExitEvent = _events.any((event) => event.s('kind') == 'exit');
    final complete =
        _events.any((event) => event.s('kind') == 'test_completed');

    return Scaffold(
      appBar: AppBar(
        title: Text(
            testId == null ? 'Start visual test' : 'Manual screenshot test'),
        actions: [
          if (testId != null)
            IconButton(
              tooltip: 'Delete test',
              onPressed: _deleteTest,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? EmptyState('Could not load strategy version: $_loadError')
              : definition == null
                  ? const EmptyState('Strategy version is unavailable.')
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        SectionCard(
                          title: 'Exact strategy version and entry scenario',
                          children: [
                            Text(_strategyName ?? definition.name),
                            Text(
                              scenario == null
                                  ? 'Entry scenario unavailable'
                                  : '${scenario.name}${scenario.description.isEmpty ? '' : ' · ${scenario.description}'}',
                            ),
                            const Text(
                              'Screenshot testing is manual. No chart pixels are interpreted as OHLC data.',
                            ),
                          ],
                        ),
                        if (testId == null) ...[
                          SectionCard(
                            title: 'Market context',
                            children: [
                              TextField(
                                controller: _instrument,
                                textCapitalization:
                                    TextCapitalization.characters,
                                decoration: const InputDecoration(
                                  labelText: 'Instrument',
                                ),
                              ),
                              DropdownButtonFormField<String>(
                                value: _timeframe,
                                decoration: const InputDecoration(
                                  labelText: 'Timeframe',
                                ),
                                items: definition.timeframes
                                    .map((value) => DropdownMenuItem(
                                          value: value,
                                          child: Text(value),
                                        ))
                                    .toList(),
                                onChanged: (value) =>
                                    setState(() => _timeframe = value),
                              ),
                              DropdownButtonFormField<String>(
                                value: _session,
                                decoration: const InputDecoration(
                                  labelText: 'Market session',
                                ),
                                items: definition.sessions
                                    .map((value) => DropdownMenuItem(
                                          value: value,
                                          child: Text(value),
                                        ))
                                    .toList(),
                                onChanged: (value) =>
                                    setState(() => _session = value),
                              ),
                              PickerField(
                                label: 'Decision date and time',
                                text: formatLocalDateTime(
                                  _testedAt.toUtc().toIso8601String(),
                                ),
                                onTap: () async {
                                  final date = await pickDateTime(
                                    context,
                                    _testedAt,
                                  );
                                  if (date != null) {
                                    setState(() => _testedAt = date);
                                  }
                                },
                              ),
                              TextField(
                                controller: _marketContext,
                                minLines: 2,
                                maxLines: 5,
                                decoration: const InputDecoration(
                                  labelText: 'Market conditions / context',
                                ),
                              ),
                            ],
                          ),
                          FilledButton.icon(
                            onPressed: _saving ? null : _startTest,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.play_arrow),
                            label: Text(
                              _saving ? 'Starting...' : 'Create test and begin',
                            ),
                          ),
                        ] else ...[
                          _buildEvidenceSection(
                            context,
                            gallery,
                            decisionImage,
                            isLocked,
                          ),
                          if (decisionImage != null)
                            SectionCard(
                              title: 'Mark decision-point chart',
                              children: [
                                const Text(
                                  'The right side of the selected image is covered at the saved decision boundary. Decision marks become read-only after locking.',
                                ),
                                ChoiceRow(
                                  label: 'Mark type',
                                  options: visualAnnotationKinds,
                                  value: _annotationKind,
                                  enabled: !isLocked,
                                  onChanged: (value) => setState(
                                    () => _annotationKind = value,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _BacktestChart(
                                  image: decisionImage,
                                  annotations:
                                      _annotations[decisionImage.s('id')] ??
                                          const [],
                                  cutoffX: decisionImage.d('cutoff_x'),
                                  maskAfterCutoff: true,
                                  onTap: isLocked
                                      ? null
                                      : (x, y) => _addAnnotation(
                                            decisionImage.s('id'),
                                            x,
                                            y,
                                          ),
                                  cutoffValue: _cutoffX,
                                ),
                              ],
                            ),
                          if (!isLocked)
                            SectionCard(
                              title: 'Version-driven execution checklist',
                              children: [
                                LinearProgressIndicator(
                                  value: checklist?.progress ?? 0,
                                ),
                                Text(
                                  checklist?.currentStageId == null
                                      ? 'All mandatory checklist stages are complete or blocked by a decision.'
                                      : 'Current stage: ${definition.stages.firstWhere((stage) => stage.id == checklist!.currentStageId).label}',
                                ),
                                const SizedBox(height: 8),
                                for (final stage in definition.stages)
                                  _stageCard(stage, definition, checklist),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _notes,
                                  minLines: 2,
                                  maxLines: 6,
                                  decoration: const InputDecoration(
                                    labelText: 'Test notes',
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: _saveDraftNotes,
                                    icon: const Icon(Icons.save_outlined),
                                    label: const Text('Save draft notes'),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (checklist?.canRecordEntry == true)
                                      FilledButton.icon(
                                        onPressed: () =>
                                            _lockDecision('valid_entry'),
                                        icon: const Icon(Icons.login),
                                        label: const Text('Record valid entry'),
                                      ),
                                    if (checklist?.canRecordEntry != true &&
                                        checklist?.hasInvalidatedRule != true &&
                                        !_stayOutSatisfied(definition, states))
                                      OutlinedButton(
                                        onPressed: () =>
                                            _lockDecision('rejected_setup'),
                                        child: const Text('Reject setup'),
                                      ),
                                    if (_stayOutSatisfied(definition, states))
                                      OutlinedButton(
                                        onPressed: () =>
                                            _lockDecision('skipped_trade'),
                                        child:
                                            const Text('Skip: stay-out rule'),
                                      ),
                                    if (checklist?.hasInvalidatedRule == true)
                                      OutlinedButton(
                                        onPressed: () => _lockDecision(
                                          'invalidated_setup',
                                        ),
                                        child: const Text('Invalidate setup'),
                                      ),
                                  ],
                                ),
                                if (checklist?.entryBlockReason != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(checklist!.entryBlockReason!),
                                  ),
                              ],
                            ),
                          if (isLocked)
                            SectionCard(
                              title: 'Decision locked',
                              children: [
                                Text(
                                  'Decision: ${pretty(_events.firstWhere((event) => event.s('kind') == 'entry_decision').s('decision'))}',
                                ),
                                if (isTrade) ...[
                                  const Text(
                                    'Record execution and management in sequence. Unknown prices remain blank; no results are inferred.',
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      if (!hasEntryEvent)
                                        FilledButton.tonal(
                                          onPressed: () =>
                                              _recordTradeEvent('entry'),
                                          child: const Text('Record entry'),
                                        ),
                                      if (hasEntryEvent && !hasExitEvent)
                                        PopupMenuButton<String>(
                                          onSelected: _recordTradeEvent,
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                              value: 'partial_close',
                                              child: Text('Partial close'),
                                            ),
                                            PopupMenuItem(
                                              value: 'stop_moved',
                                              child: Text('Move stop'),
                                            ),
                                            PopupMenuItem(
                                              value: 'breakeven_stop',
                                              child: Text('Breakeven stop'),
                                            ),
                                            PopupMenuItem(
                                              value: 'trailing_stop',
                                              child: Text('Trailing stop'),
                                            ),
                                            PopupMenuItem(
                                              value: 'management_decision',
                                              child:
                                                  Text('Management decision'),
                                            ),
                                            PopupMenuItem(
                                              value: 'uncertainty',
                                              child:
                                                  Text('Execution uncertainty'),
                                            ),
                                          ],
                                          child: const Padding(
                                            padding: EdgeInsets.all(12),
                                            child: Text('Manage trade'),
                                          ),
                                        ),
                                      if (hasEntryEvent && !hasExitEvent)
                                        FilledButton.tonal(
                                          onPressed: () =>
                                              _recordTradeEvent('exit'),
                                          child: const Text('Record exit'),
                                        ),
                                    ],
                                  ),
                                ],
                                if (!complete)
                                  FilledButton(
                                    onPressed: isTrade
                                        ? hasExitEvent
                                            ? () => _completeTest(isTrade: true)
                                            : null
                                        : () => _completeTest(isTrade: false),
                                    child: const Text('Complete test record'),
                                  ),
                                if (complete)
                                  const Text(
                                    'This test result is complete and included only in its exact strategy-version statistics.',
                                  ),
                              ],
                            ),
                          if (_events.isNotEmpty || _ruleHistory.isNotEmpty)
                            SectionCard(
                              title: 'Timestamped decision history',
                              children: [
                                for (final event in _ruleHistory)
                                  ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.rule),
                                    title: Text(
                                      '${_ruleLabel(definition, event.s('rule_id'))}: ${pretty(event.s('state'))}',
                                    ),
                                    subtitle: Text(
                                      '${formatLocalDateTime(event.sn('created_at'))}'
                                      '${event.s('explanation').isEmpty ? '' : ' · ${event.s('explanation')}'}',
                                    ),
                                  ),
                                for (final event in _events)
                                  ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.history),
                                    title: Text(
                                      '${pretty(event.s('kind'))}${event.s('decision').isEmpty ? '' : ' · ${pretty(event.s('decision'))}'}',
                                    ),
                                    subtitle: Text(
                                      formatLocalDateTime(
                                          event.sn('created_at')),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ],
                    ),
    );
  }

  Widget _buildEvidenceSection(
    BuildContext context,
    AsyncValue<List<Rec>> gallery,
    Rec? decisionImage,
    bool locked,
  ) {
    return SectionCard(
      title: 'Decision and subsequent evidence',
      trailing: TextButton.icon(
        onPressed: _importScreenshots,
        icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
        label: const Text('Import'),
      ),
      children: [
        Text(
          locked
              ? 'Add subsequent screenshots as evidence only after the decision is locked.'
              : 'Choose a screenshot for the decision point, then set the right-edge cutoff before evaluating the strategy.',
        ),
        if (!locked && decisionImage == null) ...[
          Slider(
            value: _cutoffX,
            min: .1,
            max: .99,
            divisions: 89,
            label: '${(_cutoffX * 100).round()}%',
            onChanged: (value) => setState(() => _cutoffX = value),
          ),
          Text('Visible at decision: ${(_cutoffX * 100).round()}% of width'),
        ],
        gallery.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Text('Could not load screenshot gallery: $error'),
          data: (images) {
            final attachable = images
                .where((image) => image.s('id') != decisionImage?.s('id'))
                .toList();
            if (attachable.isEmpty) {
              return const EmptyState(
                'No screenshots available. Import a PNG, JPG or JPEG chart.',
              );
            }
            return Column(
              children: [
                for (final image in attachable)
                  ListTile(
                    leading: const Icon(Icons.image_outlined),
                    title: Text(
                      image.s('original_name', image.s('caption', 'Chart')),
                    ),
                    subtitle: Text(
                      '${image.s('instrument', 'Instrument not set')} · '
                      '${image.s('timeframe', 'Timeframe not set')}',
                    ),
                    trailing: IconButton(
                      tooltip: locked
                          ? 'Add as subsequent evidence'
                          : 'Set as decision-point screenshot',
                      onPressed: locked
                          ? () => _attachEvidence(image)
                          : () => _attachDecisionImage(image),
                      icon: Icon(locked ? Icons.add_link : Icons.visibility),
                    ),
                  ),
              ],
            );
          },
        ),
        if (decisionImage != null)
          ListTile(
            leading: const Icon(Icons.lock_clock_outlined),
            title: Text(
              decisionImage.s(
                'original_name',
                decisionImage.s('caption', 'Decision-point screenshot'),
              ),
            ),
            subtitle: Text(
              'Cutoff ${((decisionImage.d('cutoff_x') ?? 1) * 100).round()}%',
            ),
            trailing: locked
                ? null
                : IconButton(
                    tooltip: 'Change decision screenshot',
                    onPressed: _removeDecisionImage,
                    icon: const Icon(Icons.change_circle_outlined),
                  ),
          ),
        if (_images.any((image) => image.s('test_role') == 'evidence'))
          ..._images
              .where((image) => image.s('test_role') == 'evidence')
              .expand(
                (image) => [
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: Text(image.s('caption', 'Subsequent evidence')),
                    subtitle: Text(image.s('original_name')),
                  ),
                  _BacktestChart(
                    image: image,
                    annotations: _annotations[image.s('id')] ?? const [],
                    maskAfterCutoff: false,
                    cutoffValue: 1,
                  ),
                ],
              ),
      ],
    );
  }

  Widget _stageCard(
    VisualStrategyStage stage,
    VisualStrategyDefinition definition,
    VisualChecklistSnapshot? checklist,
  ) {
    final stageState = checklist?.stages
        .where((item) => item.stage.id == stage.id)
        .firstOrNull;
    final rules =
        definition.rules.where((rule) => rule.stageId == stage.id).toList();
    if (rules.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      initiallyExpanded: checklist?.currentStageId == stage.id,
      title: Text(stage.label),
      subtitle: Text(
        stageState == null
            ? 'Not evaluated'
            : stageState.complete
                ? 'Complete'
                : stageState.ready
                    ? 'Ready to evaluate'
                    : 'Waiting for earlier stage',
      ),
      children: [
        for (final rule in rules)
          _ruleTile(rule, stageState, definition, checklist),
      ],
    );
  }

  Widget _ruleTile(
    VisualStrategyRule rule,
    VisualChecklistStageState? stageState,
    VisualStrategyDefinition definition,
    VisualChecklistSnapshot? checklist,
  ) {
    final savedState = _ruleStates[rule.id] ?? 'pending';
    final isApplicable =
        rule.scenarioId == null || rule.scenarioId == widget.scenarioId;
    final enabled = !isLockedForRule(rule, definition);
    final available = canEvaluateVisualRule(rule, _ruleStates);
    final stageReady = stageState?.ready ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rule.label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (rule.explanation.isNotEmpty) Text(rule.explanation),
            if (rule.mode == 'numeric')
              Text(
                'Numeric condition: ${rule.metric} ${rule.comparator} ${rule.threshold} (manual mode does not calculate this condition)',
                style: const TextStyle(fontSize: 12),
              ),
            if (!isApplicable)
              const Text('Not applicable to this entry scenario.'),
            if (rule.blocksEntryWhenSatisfied)
              const Text(
                'When satisfied, this stay-out rule blocks entry.',
              ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: isApplicable ? savedState : 'not_applicable',
                    decoration: const InputDecoration(
                      labelText: 'Evaluation state',
                    ),
                    items: visualRuleStates
                        .map((state) => DropdownMenuItem(
                              value: state,
                              child: Text(pretty(state)),
                            ))
                        .toList(),
                    onChanged: enabled &&
                            stageReady &&
                            available &&
                            isApplicable
                        ? (value) {
                            if (value != null) _changeRuleState(rule, value);
                          }
                        : null,
                  ),
                ),
                IconButton(
                  tooltip: 'Add supporting evidence',
                  onPressed: enabled ? () => _editExplanation(rule) : null,
                  icon: const Icon(Icons.edit_note),
                ),
              ],
            ),
            if (!available && rule.dependsOn.isNotEmpty)
              Text(
                'Waiting for dependencies: ${rule.dependsOn.map((id) => _ruleLabel(definition, id)).join(', ')}',
              ),
            if ((_ruleExplanations[rule.id] ?? '').isNotEmpty)
              Text('Evidence: ${_ruleExplanations[rule.id]}'),
          ],
        ),
      ),
    );
  }

  bool isLockedForRule(
    VisualStrategyRule rule,
    VisualStrategyDefinition definition,
  ) {
    if (_testId == null) return true;
    final locked = _events.any((event) => event.s('kind') == 'entry_decision');
    if (!locked) return false;
    final stage =
        definition.stages.firstWhere((item) => item.id == rule.stageId);
    return !{
      'management',
      'stop_invalidation',
      'take_profit',
      'exit',
      'outcome',
    }.contains(stage.category);
  }

  bool _stayOutSatisfied(
    VisualStrategyDefinition definition,
    Map<String, String> states,
  ) =>
      definition.rules.any(
        (rule) =>
            rule.blocksEntryWhenSatisfied && states[rule.id] == 'satisfied',
      );

  String _ruleLabel(VisualStrategyDefinition definition, String id) {
    final match = definition.rules.where((rule) => rule.id == id);
    return match.isEmpty ? id : match.first.label;
  }
}

class _BacktestChart extends ConsumerWidget {
  const _BacktestChart({
    required this.image,
    required this.annotations,
    required this.maskAfterCutoff,
    required this.cutoffValue,
    this.cutoffX,
    this.onTap,
  });

  final Rec image;
  final List<Rec> annotations;
  final bool maskAfterCutoff;
  final double cutoffValue;
  final double? cutoffX;
  final void Function(double x, double y)? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relativePath = image.sn('local_path');
    if (relativePath == null) {
      return const EmptyState('Screenshot is not stored on this device.');
    }
    final file = File(ref.read(imageStoreProvider).absolutePath(relativePath));
    final width = image.d('width') ?? 16;
    final height = image.d('height') ?? 9;
    final aspectRatio = width > 0 && height > 0 ? width / height : 16 / 9;
    final cutoff = cutoffX ?? cutoffValue;

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const viewportHeight = 340.0;
            final displayScale = math.min(
              constraints.maxWidth / 1000,
              viewportHeight / (1000 / aspectRatio),
            );
            final chartWidth = 1000 * displayScale;
            final chartHeight = chartWidth / aspectRatio;
            return SizedBox(
              height: viewportHeight,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 6,
                boundaryMargin: const EdgeInsets.all(60),
                constrained: false,
                child: SizedBox(
                  width: chartWidth,
                  height: chartHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: onTap == null
                        ? null
                        : (details) {
                            final x = (details.localPosition.dx / chartWidth)
                                .clamp(0.0, 1.0);
                            final y = (details.localPosition.dy / chartHeight)
                                .clamp(0.0, 1.0);
                            if (maskAfterCutoff && x >= cutoff) {
                              snack(
                                context,
                                'The hidden chart region is beyond the decision point.',
                              );
                              return;
                            }
                            onTap!(x, y);
                          },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          file,
                          fit: BoxFit.fill,
                          errorBuilder: (_, __, ___) => const ColoredBox(
                            color: Colors.black12,
                            child: Center(
                              child: Text('Screenshot file is unavailable.'),
                            ),
                          ),
                        ),
                        CustomPaint(
                          painter: _BacktestAnnotationPainter(annotations),
                        ),
                        if (maskAfterCutoff)
                          Positioned(
                            left: chartWidth * cutoff,
                            top: 0,
                            bottom: 0,
                            right: 0,
                            child: const ColoredBox(
                              color: Color(0xFF202938),
                              child: Center(
                                child: Text(
                                  'Future hidden',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (onTap != null)
                          Positioned(
                            left: chartWidth * cutoff - 1,
                            top: 0,
                            bottom: 0,
                            child: Container(width: 2, color: Colors.amber),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _BacktestAnnotationPainter extends CustomPainter {
  const _BacktestAnnotationPainter(this.annotations);

  final List<Rec> annotations;

  @override
  void paint(Canvas canvas, Size size) {
    for (final annotation in annotations) {
      final kind = annotation.s('kind');
      final x = annotation.d('x') ?? 0;
      final y = annotation.d('y') ?? 0;
      final color = switch (kind) {
        'entry' => const Color(0xFF22C55E),
        'stop_loss' => const Color(0xFFEF4444),
        'take_profit' => const Color(0xFF3B82F6),
        'exit' => const Color(0xFFF59E0B),
        _ => Colors.white,
      };
      final position = Offset(x * size.width, y * size.height);
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      if (kind == 'observation') {
        canvas.drawCircle(position, 8, paint);
      } else {
        canvas.drawLine(
          Offset(0, position.dy),
          Offset(size.width, position.dy),
          paint,
        );
      }
      final label = annotation.s('label', pretty(kind));
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white,
            backgroundColor: color.withAlpha(210),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      painter.paint(
        canvas,
        Offset(
          kind == 'observation' ? position.dx + 10 : 4,
          (position.dy - painter.height - 2)
              .clamp(0.0, size.height - painter.height),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BacktestAnnotationPainter oldDelegate) =>
      oldDelegate.annotations != annotations;
}
