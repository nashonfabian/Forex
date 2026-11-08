import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/backtesting/strategy_definition.dart';
import '../../data/repositories/visual_backtesting_repository.dart';
import '../../widgets/common.dart';
import 'visual_strategy_rule_editor.dart';

class VisualStrategyFormScreen extends ConsumerStatefulWidget {
  const VisualStrategyFormScreen({
    super.key,
    this.strategyId,
    this.versionId,
  });

  final String? strategyId;
  final String? versionId;

  @override
  ConsumerState<VisualStrategyFormScreen> createState() =>
      _VisualStrategyFormScreenState();
}

class _VisualStrategyFormScreenState
    extends ConsumerState<VisualStrategyFormScreen> {
  final _name = TextEditingController();
  final _instruments = TextEditingController();
  final _riskValue = TextEditingController();
  final _maxTrades = TextEditingController(text: '1');
  final _spread = TextEditingController();
  final _commission = TextEditingController();
  final _slippage = TextEditingController();
  final _swap = TextEditingController();
  final _sessions = <String>{};
  final _timeframes = <String>{};
  final _stages = <VisualStrategyStage>[];
  final _rules = <VisualStrategyRule>[];
  final _scenarios = <VisualEntryScenario>[];
  String _timezone = 'UTC';
  String _riskMode = 'fixed';
  bool _allowPartialCloses = true;
  bool _allowBreakevenStop = true;
  bool _allowTrailingStop = true;
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.strategyId != null) {
      _loading = true;
      _load();
    } else {
      _initializeNew();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _instruments.dispose();
    _riskValue.dispose();
    _maxTrades.dispose();
    _spread.dispose();
    _commission.dispose();
    _slippage.dispose();
    _swap.dispose();
    super.dispose();
  }

  void _initializeNew() {
    _name.text = '';
    _timeframes.add('M15');
    _sessions.add('London');
    _scenarios.add(
      VisualEntryScenario(
        id: newId(),
        name: 'Primary entry',
        description: '',
      ),
    );
    _stages.addAll(
      visualStageCategories.map(
        (category) => VisualStrategyStage(
          id: newId(),
          category: category,
          label: visualStageLabels[category]!,
          dependsOn: const [],
        ),
      ),
    );
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(visualBacktestingRepositoryProvider);
      final strategy = await repo.strategyById(widget.strategyId!);
      if (strategy == null) throw StateError('Strategy not found.');
      final versions = await repo.strategyVersions(widget.strategyId!);
      final matches = widget.versionId == null
          ? versions
          : versions.where((item) => item.s('id') == widget.versionId).toList();
      final version = matches.isEmpty ? null : matches.first;
      if (version == null) throw StateError('Strategy version not found.');
      final definition = visualStrategyDefinitionFromVersion(version);
      _name.text = definition.name;
      _instruments.text = definition.instruments.join(', ');
      _sessions.addAll(definition.sessions);
      _timeframes.addAll(definition.timeframes);
      _timezone = definition.timezone;
      _stages.addAll(definition.stages);
      _rules.addAll(definition.rules);
      _scenarios.addAll(definition.scenarios);
      _riskMode = definition.riskManagement['risk_mode'] is String
          ? definition.riskManagement['risk_mode'] as String
          : 'fixed';
      _riskValue.text = _stringValue(definition.riskManagement['risk_value']);
      _maxTrades.text = _stringValue(
          definition.riskManagement['max_trades_per_session'], '1');
      _allowPartialCloses =
          definition.riskManagement['partial_closes'] != false;
      _allowBreakevenStop =
          definition.riskManagement['breakeven_stop'] != false;
      _allowTrailingStop = definition.riskManagement['trailing_stop'] != false;
      _spread.text = _stringValue(definition.executionAssumptions['spread']);
      _commission.text =
          _stringValue(definition.executionAssumptions['commission']);
      _slippage.text =
          _stringValue(definition.executionAssumptions['slippage']);
      _swap.text = _stringValue(definition.executionAssumptions['swap']);
    } catch (e) {
      if (mounted) snack(context, 'Could not load strategy version: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _stringValue(Object? value, [String fallback = '']) =>
      value == null ? fallback : '$value';

  Future<({String name, String description})?> _editScenarioDialog({
    String name = '',
    String description = '',
  }) async {
    final nameController = TextEditingController(text: name);
    final descriptionController = TextEditingController(text: description);
    final result = await showDialog<({String name, String description})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(name.isEmpty ? 'Add entry scenario' : 'Edit scenario'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Scenario name'),
            ),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description / distinguishing rules',
              ),
              minLines: 2,
              maxLines: 5,
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
              if (nameController.text.trim().isEmpty) {
                snack(dialogContext, 'Enter a scenario name.');
                return;
              }
              Navigator.pop(
                dialogContext,
                (
                  name: nameController.text.trim(),
                  description: descriptionController.text.trim(),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    nameController.dispose();
    descriptionController.dispose();
    return result;
  }

  Future<void> _addScenario() async {
    final result = await _editScenarioDialog();
    if (result == null || !mounted) return;
    setState(() {
      _scenarios.add(
        VisualEntryScenario(
          id: newId(),
          name: result.name,
          description: result.description,
        ),
      );
    });
  }

  Future<void> _editScenario(int index) async {
    final scenario = _scenarios[index];
    final result = await _editScenarioDialog(
      name: scenario.name,
      description: scenario.description,
    );
    if (result == null || !mounted) return;
    setState(() {
      _scenarios[index] = VisualEntryScenario(
        id: scenario.id,
        name: result.name,
        description: result.description,
      );
    });
  }

  Future<void> _addStage() async {
    final categories = visualStageCategories
        .where(
          (category) => !_stages.any((stage) => stage.category == category),
        )
        .toList();
    if (categories.isEmpty) {
      snack(context, 'All checklist categories are already present.');
      return;
    }
    final category = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Add checklist stage'),
        children: [
          for (final item in categories)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, item),
              child: Text(visualStageLabels[item]!),
            ),
        ],
      ),
    );
    if (category == null || !mounted) return;
    setState(() {
      _stages.add(
        VisualStrategyStage(
          id: newId(),
          category: category,
          label: visualStageLabels[category]!,
          dependsOn: const [],
        ),
      );
    });
  }

  Future<void> _editStageLabel(int index) async {
    final controller = TextEditingController(text: _stages[index].label);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Checklist stage label'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Label'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) {
                snack(dialogContext, 'Enter a stage label.');
                return;
              }
              Navigator.pop(dialogContext, controller.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    setState(() {
      final old = _stages[index];
      _stages[index] = VisualStrategyStage(
        id: old.id,
        category: old.category,
        label: result,
        dependsOn: old.dependsOn,
      );
    });
  }

  void _moveStage(int index, int delta) {
    final destination = index + delta;
    if (destination < 0 || destination >= _stages.length) return;
    setState(() {
      final stage = _stages.removeAt(index);
      _stages.insert(destination, stage);
    });
  }

  Future<void> _editRule(VisualStrategyStage stage,
      {VisualStrategyRule? rule}) async {
    final edited = await editVisualStrategyRule(
      context,
      rule: rule,
      stageId: stage.id,
      stageCategory: stage.category,
      otherRules: _rules.where((item) => item.id != rule?.id).toList(),
      scenarios: _scenarios,
    );
    if (edited == null || !mounted) return;
    setState(() {
      final index = _rules.indexWhere((item) => item.id == edited.id);
      if (index < 0) {
        _rules.add(edited);
      } else {
        _rules[index] = edited;
      }
    });
  }

  void _deleteRule(VisualStrategyRule rule) {
    final dependentRules =
        _rules.where((item) => item.dependsOn.contains(rule.id)).toList();
    if (dependentRules.isNotEmpty) {
      snack(
          context, 'Remove this rule from its dependents before deleting it.');
      return;
    }
    setState(() => _rules.removeWhere((item) => item.id == rule.id));
  }

  void _toggleStageDependency(
    VisualStrategyStage stage,
    String dependencyId,
    bool selected,
  ) {
    setState(() {
      final dependencies = {...stage.dependsOn};
      if (selected) {
        dependencies.add(dependencyId);
      } else {
        dependencies.remove(dependencyId);
      }
      final index = _stages.indexWhere((item) => item.id == stage.id);
      _stages[index] = VisualStrategyStage(
        id: stage.id,
        category: stage.category,
        label: stage.label,
        dependsOn: dependencies.toList(),
      );
    });
  }

  double? _optionalNumber(TextEditingController controller, String label) {
    if (controller.text.trim().isEmpty) return null;
    final value = double.tryParse(controller.text.trim());
    if (value == null || !value.isFinite || value < 0) {
      throw StateError('$label must be a non-negative number.');
    }
    return value;
  }

  Future<void> _save() async {
    if (_saving) return;
    double? riskValue;
    try {
      riskValue = _optionalNumber(_riskValue, 'Risk amount');
    } on StateError catch (error) {
      snack(context, error.message);
      return;
    }
    if (riskValue == null) {
      snack(context, 'Set the fixed or percentage risk amount.');
      return;
    }
    final maxTrades = int.tryParse(_maxTrades.text.trim());
    if (maxTrades == null || maxTrades < 1) {
      snack(context, 'Maximum trades per session must be at least one.');
      return;
    }
    double? spread;
    double? commission;
    double? slippage;
    double? swap;
    try {
      spread = _optionalNumber(_spread, 'Spread');
      commission = _optionalNumber(_commission, 'Commission');
      slippage = _optionalNumber(_slippage, 'Slippage');
      swap = _optionalNumber(_swap, 'Swap');
    } on StateError catch (error) {
      snack(context, error.message);
      return;
    }

    final definition = VisualStrategyDefinition(
      name: _name.text.trim(),
      instruments: _instruments.text
          .split(',')
          .map((item) => item.trim().toUpperCase())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(),
      timeframes: _timeframes.toList(),
      sessions: _sessions.toList(),
      timezone: _timezone,
      stages: List.unmodifiable(_stages),
      rules: List.unmodifiable(_rules),
      scenarios: List.unmodifiable(_scenarios),
      riskManagement: {
        'risk_mode': _riskMode,
        'risk_value': riskValue,
        'max_trades_per_session': maxTrades,
        'partial_closes': _allowPartialCloses,
        'breakeven_stop': _allowBreakevenStop,
        'trailing_stop': _allowTrailingStop,
      },
      executionAssumptions: {
        'spread': spread,
        'commission': commission,
        'slippage': slippage,
        'swap': swap,
      },
    );
    final validation = definition.validate();
    if (validation != null) {
      snack(context, validation);
      return;
    }

    setState(() => _saving = true);
    try {
      final strategyId = await ref
          .read(visualBacktestingRepositoryProvider)
          .saveStrategyDefinition(
            id: widget.strategyId,
            definition: definition,
          );
      if (mounted) Navigator.pop(context, strategyId);
    } catch (e) {
      if (mounted) snack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _stageCard(VisualStrategyStage stage, int index) {
    final stageRules =
        _rules.where((rule) => rule.stageId == stage.id).toList();
    return Card(
      key: ValueKey(stage.id),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    stage.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Rename stage',
                  onPressed: () => _editStageLabel(index),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Move stage up',
                  onPressed: index == 0 ? null : () => _moveStage(index, -1),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Move stage down',
                  onPressed: index == _stages.length - 1
                      ? null
                      : () => _moveStage(index, 1),
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: 'Remove stage',
                  onPressed: stageRules.isNotEmpty
                      ? null
                      : () => setState(() {
                            _stages.removeAt(index);
                            for (var i = 0; i < _stages.length; i++) {
                              final current = _stages[i];
                              _stages[i] = VisualStrategyStage(
                                id: current.id,
                                category: current.category,
                                label: current.label,
                                dependsOn: current.dependsOn
                                    .where((id) => id != stage.id)
                                    .toList(),
                              );
                            }
                          }),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              children: [
                Chip(label: Text(visualStageLabels[stage.category]!)),
                for (final dep in stage.dependsOn)
                  Chip(
                    label: Text(
                      _stages.firstWhere((item) => item.id == dep).label,
                    ),
                  ),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Stage dependencies'),
              children: [
                for (final candidate in _stages.where(
                  (item) => item.id != stage.id,
                ))
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(candidate.label),
                    value: stage.dependsOn.contains(candidate.id),
                    onChanged: (value) => _toggleStageDependency(
                      stage,
                      candidate.id,
                      value == true,
                    ),
                  ),
              ],
            ),
            for (final rule in stageRules)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(rule.label),
                subtitle: Text(
                  '${rule.mode == 'numeric' ? '${rule.metric} ${rule.comparator} ${rule.threshold}' : 'Manual'}'
                  ' · ${rule.relation.toUpperCase()}'
                  '${rule.scenarioId == null ? '' : ' · ${_scenarios.firstWhere((item) => item.id == rule.scenarioId).name}'}',
                ),
                leading: Icon(
                  rule.mode == 'numeric'
                      ? Icons.functions
                      : Icons.visibility_outlined,
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Edit rule',
                      onPressed: () => _editRule(stage, rule: rule),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Delete rule',
                      onPressed: () => _deleteRule(rule),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _editRule(stage),
                icon: const Icon(Icons.add),
                label: const Text('Add condition'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(
            widget.strategyId == null ? 'New strategy' : 'New strategy version',
          ),
          actions: [
            IconButton(
              tooltip: 'Save as new immutable version',
              onPressed: _loading || _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SectionCard(
                    title: 'Strategy identity and market scope',
                    children: [
                      LabeledField(
                        controller: _name,
                        label: 'Strategy name',
                      ),
                      LabeledField(
                        controller: _instruments,
                        label: 'Instruments',
                        hint: 'Comma-separated; leave empty for any instrument',
                      ),
                      ChoiceRow(
                        label: 'Timeframes',
                        options: visualTimeframes,
                        value: null,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            if (_timeframes.contains(value)) {
                              _timeframes.remove(value);
                            } else {
                              _timeframes.add(value);
                            }
                          });
                        },
                      ),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final timeframe in _timeframes)
                            InputChip(
                              label: Text(timeframe),
                              onDeleted: () =>
                                  setState(() => _timeframes.remove(timeframe)),
                            ),
                        ],
                      ),
                      ChoiceRow(
                        label: 'Trading sessions',
                        options: visualTradingSessions,
                        value: null,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            if (_sessions.contains(value)) {
                              _sessions.remove(value);
                            } else {
                              _sessions.add(value);
                            }
                          });
                        },
                      ),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final session in _sessions)
                            InputChip(
                              label: Text(session),
                              onDeleted: () =>
                                  setState(() => _sessions.remove(session)),
                            ),
                        ],
                      ),
                      DropdownButtonFormField<String>(
                        value: _timezone,
                        decoration: const InputDecoration(
                            labelText: 'Session timezone'),
                        items: const [
                          DropdownMenuItem(value: 'UTC', child: Text('UTC')),
                          DropdownMenuItem(
                            value: 'local',
                            child: Text('Device local time'),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _timezone = value ?? _timezone),
                      ),
                    ],
                  ),
                  SectionCard(
                    title: 'Alternative entry scenarios',
                    trailing: TextButton.icon(
                      onPressed: _addScenario,
                      icon: const Icon(Icons.add),
                      label: const Text('Add scenario'),
                    ),
                    children: [
                      for (var index = 0; index < _scenarios.length; index++)
                        ListTile(
                          title: Text(_scenarios[index].name),
                          subtitle: Text(_scenarios[index].description),
                          leading: const Icon(Icons.alt_route),
                          trailing: Wrap(
                            children: [
                              IconButton(
                                tooltip: 'Edit scenario',
                                onPressed: () => _editScenario(index),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Remove scenario',
                                onPressed: _scenarios.length <= 1
                                    ? null
                                    : () => setState(() {
                                          final removed =
                                              _scenarios.removeAt(index);
                                          for (var i = 0;
                                              i < _rules.length;
                                              i++) {
                                            final rule = _rules[i];
                                            if (rule.scenarioId == removed.id) {
                                              _rules[i] = VisualStrategyRule(
                                                id: rule.id,
                                                stageId: rule.stageId,
                                                label: rule.label,
                                                mode: rule.mode,
                                                relation: rule.relation,
                                                dependsOn: rule.dependsOn,
                                                required: rule.required,
                                                blocksEntryWhenSatisfied: rule
                                                    .blocksEntryWhenSatisfied,
                                                metric: rule.metric,
                                                comparator: rule.comparator,
                                                threshold: rule.threshold,
                                                period: rule.period,
                                                scenarioId: null,
                                                explanation: rule.explanation,
                                              );
                                            }
                                          }
                                        }),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  SectionCard(
                    title: 'Checklist stages and conditions',
                    trailing: TextButton.icon(
                      onPressed: _addStage,
                      icon: const Icon(Icons.add),
                      label: const Text('Add stage'),
                    ),
                    children: [
                      const Text(
                        'Stages are saved in this strategy version. Their dependencies—not a fixed app-wide sequence—control test progression.',
                      ),
                      const SizedBox(height: 8),
                      for (var index = 0; index < _stages.length; index++)
                        _stageCard(_stages[index], index),
                    ],
                  ),
                  SectionCard(
                    title: 'Risk and trade management',
                    children: [
                      DropdownButtonFormField<String>(
                        value: _riskMode,
                        decoration: const InputDecoration(
                          labelText: 'Risk sizing mode',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'fixed',
                            child: Text('Fixed monetary risk'),
                          ),
                          DropdownMenuItem(
                            value: 'percentage',
                            child: Text('Percentage of account equity'),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _riskMode = value ?? _riskMode),
                      ),
                      LabeledField(
                        controller: _riskValue,
                        label: _riskMode == 'fixed'
                            ? 'Fixed risk amount'
                            : 'Risk percent',
                        helperText:
                            'Monetary sizing requires verified instrument specifications and currency.',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      LabeledField(
                        controller: _maxTrades,
                        label: 'Maximum trades per session',
                        keyboardType: TextInputType.number,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Allow partial closes'),
                        value: _allowPartialCloses,
                        onChanged: (value) =>
                            setState(() => _allowPartialCloses = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Allow breakeven stops'),
                        value: _allowBreakevenStop,
                        onChanged: (value) =>
                            setState(() => _allowBreakevenStop = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Allow trailing stops'),
                        value: _allowTrailingStop,
                        onChanged: (value) =>
                            setState(() => _allowTrailingStop = value),
                      ),
                    ],
                  ),
                  SectionCard(
                    title: 'Execution assumptions',
                    children: [
                      LabeledField(
                        controller: _spread,
                        label: 'Spread assumption (price units)',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      LabeledField(
                        controller: _commission,
                        label: 'Commission assumption',
                        helperText:
                            'Enter the amount and unit in the test notes.',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      LabeledField(
                        controller: _slippage,
                        label: 'Slippage assumption (price units)',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      LabeledField(
                        controller: _swap,
                        label: 'Swap assumption per day',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _saving
                          ? 'Saving version...'
                          : 'Save new strategy version',
                    ),
                  ),
                ],
              ),
      );
}
