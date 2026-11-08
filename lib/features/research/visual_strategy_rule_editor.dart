import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/ids.dart';
import '../../data/backtesting/strategy_definition.dart';
import '../../widgets/common.dart';

Future<VisualStrategyRule?> editVisualStrategyRule(
  BuildContext context, {
  VisualStrategyRule? rule,
  required String stageId,
  required String stageCategory,
  required List<VisualStrategyRule> otherRules,
  required List<VisualEntryScenario> scenarios,
}) =>
    showDialog<VisualStrategyRule>(
      context: context,
      builder: (_) => _VisualStrategyRuleDialog(
        rule: rule,
        stageId: stageId,
        stageCategory: stageCategory,
        otherRules: otherRules,
        scenarios: scenarios,
      ),
    );

class _VisualStrategyRuleDialog extends StatefulWidget {
  const _VisualStrategyRuleDialog({
    required this.rule,
    required this.stageId,
    required this.stageCategory,
    required this.otherRules,
    required this.scenarios,
  });

  final VisualStrategyRule? rule;
  final String stageId;
  final String stageCategory;
  final List<VisualStrategyRule> otherRules;
  final List<VisualEntryScenario> scenarios;

  @override
  State<_VisualStrategyRuleDialog> createState() =>
      _VisualStrategyRuleDialogState();
}

class _VisualStrategyRuleDialogState extends State<_VisualStrategyRuleDialog> {
  late final TextEditingController _label;
  late final TextEditingController _explanation;
  late final TextEditingController _threshold;
  late final TextEditingController _period;
  late String _mode;
  late String _relation;
  late String _metric;
  late String _comparator;
  late String? _scenarioId;
  late bool _required;
  late bool _blocksEntry;
  late Set<String> _dependencies;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _label = TextEditingController(text: rule?.label ?? '');
    _explanation = TextEditingController(text: rule?.explanation ?? '');
    _threshold = TextEditingController(
      text: rule?.threshold == null ? '' : numToText(rule!.threshold!),
    );
    _period = TextEditingController(text: '${rule?.period ?? 14}');
    _mode = rule?.mode ?? 'manual';
    _relation = rule?.relation ?? 'and';
    _metric = rule?.metric.isNotEmpty == true ? rule!.metric : 'close';
    _comparator = rule?.comparator ?? '>';
    _scenarioId = rule?.scenarioId;
    _required = rule?.required ?? true;
    _blocksEntry = rule?.blocksEntryWhenSatisfied ?? false;
    _dependencies = {...?rule?.dependsOn};
  }

  @override
  void dispose() {
    _label.dispose();
    _explanation.dispose();
    _threshold.dispose();
    _period.dispose();
    super.dispose();
  }

  void _save() {
    if (_label.text.trim().isEmpty) {
      snack(context, 'Enter a clear rule description.');
      return;
    }
    double? threshold;
    int period = 1;
    if (_mode == 'numeric') {
      threshold = parseDouble(_threshold.text);
      if (threshold == null || !threshold.isFinite) {
        snack(context, 'Enter a finite numerical threshold.');
        return;
      }
      period = int.tryParse(_period.text.trim()) ?? 0;
      if (period < 1 || period > 10000) {
        snack(context, 'Indicator period must be between 1 and 10,000.');
        return;
      }
    }
    final currentId = widget.rule?.id ?? newId();
    if (_dependencies.contains(currentId)) {
      snack(context, 'A rule cannot depend on itself.');
      return;
    }
    Navigator.pop(
      context,
      VisualStrategyRule(
        id: currentId,
        stageId: widget.stageId,
        label: _label.text.trim(),
        mode: _mode,
        relation: _relation,
        dependsOn: _dependencies.toList(),
        required: _required,
        blocksEntryWhenSatisfied:
            widget.stageCategory == 'stay_out' && _blocksEntry,
        metric: _mode == 'numeric' ? _metric : '',
        comparator: _mode == 'numeric' ? _comparator : '>',
        threshold: threshold,
        period: period,
        scenarioId: _scenarioId,
        explanation: _explanation.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.rule == null ? 'Add rule' : 'Edit rule'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _label,
                  decoration: const InputDecoration(
                    labelText: 'Rule',
                    hintText: 'Describe a condition that can be evaluated',
                  ),
                  minLines: 2,
                  maxLines: 5,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _explanation,
                  decoration: const InputDecoration(
                    labelText: 'Evaluation guidance (optional)',
                  ),
                  minLines: 1,
                  maxLines: 4,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _mode,
                  decoration: const InputDecoration(labelText: 'Evaluation'),
                  items: const [
                    DropdownMenuItem(
                      value: 'manual',
                      child: Text('Manual concept or observation'),
                    ),
                    DropdownMenuItem(
                      value: 'numeric',
                      child: Text('Numerical condition'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _mode = value ?? _mode),
                ),
                if (_mode == 'numeric') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _metric,
                    decoration: const InputDecoration(labelText: 'OHLC metric'),
                    items: [
                      for (final metric in visualRuleMetrics)
                        DropdownMenuItem(
                          value: metric,
                          child: Text(metric.replaceAll('_', ' ')),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _metric = value ?? _metric),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _comparator,
                          decoration:
                              const InputDecoration(labelText: 'Comparison'),
                          items: [
                            for (final comparator in visualRuleComparators)
                              DropdownMenuItem(
                                value: comparator,
                                child: Text(comparator.replaceAll('_', ' ')),
                              ),
                          ],
                          onChanged: (value) => setState(
                            () => _comparator = value ?? _comparator,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _threshold,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration:
                              const InputDecoration(labelText: 'Threshold'),
                        ),
                      ),
                    ],
                  ),
                  if (const {'sma', 'ema', 'rsi', 'atr'}.contains(_metric))
                    TextField(
                      controller: _period,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Period / length'),
                    ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Automatic mode evaluates only supported metrics using available candles. Manual concepts are never inferred from screenshot pixels.',
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _relation,
                  decoration: const InputDecoration(
                    labelText: 'Dependency relationship',
                  ),
                  items: [
                    for (final relation in visualRuleRelations)
                      DropdownMenuItem(
                        value: relation,
                        child: Text(relation.toUpperCase()),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _relation = value ?? _relation),
                ),
                if (widget.otherRules.isNotEmpty) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Depends on'),
                    ),
                  ),
                  for (final dependency in widget.otherRules)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(dependency.label),
                      value: _dependencies.contains(dependency.id),
                      onChanged: (selected) => setState(() {
                        if (selected == true) {
                          _dependencies.add(dependency.id);
                        } else {
                          _dependencies.remove(dependency.id);
                        }
                      }),
                    ),
                ],
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: _scenarioId,
                  decoration: const InputDecoration(
                    labelText: 'Entry scenario',
                    helperText: 'Leave unassigned to apply to every scenario.',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All scenarios'),
                    ),
                    for (final scenario in widget.scenarios)
                      DropdownMenuItem<String?>(
                        value: scenario.id,
                        child: Text(scenario.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _scenarioId = value),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mandatory for progression'),
                  value: _required,
                  onChanged: (value) =>
                      setState(() => _required = value ?? _required),
                ),
                if (widget.stageCategory == 'stay_out')
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Prohibits entry when satisfied'),
                    value: _blocksEntry,
                    onChanged: (value) =>
                        setState(() => _blocksEntry = value ?? false),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _save,
            child: const Text('Save rule'),
          ),
        ],
      );
}
