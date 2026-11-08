import 'dart:convert';

const visualRuleStates = [
  'satisfied',
  'pending',
  'failed',
  'invalidated',
  'not_applicable',
];

const visualRuleRelations = [
  'and',
  'or',
  'not',
  'then',
  'wait',
  'invalidate',
];

const visualRuleModes = ['manual', 'numeric'];

const visualRuleMetrics = [
  'open',
  'high',
  'low',
  'close',
  'previous_open',
  'previous_high',
  'previous_low',
  'previous_close',
  'range',
  'body',
  'tick_volume',
  'real_volume',
  'spread',
  'sma',
  'ema',
  'rsi',
  'atr',
];

const visualRuleComparators = [
  '>',
  '>=',
  '<',
  '<=',
  'cross_above',
  'cross_below',
];

const visualStageCategories = [
  'market_context',
  'setup',
  'confirmation',
  'entry',
  'stay_out',
  'stop_invalidation',
  'take_profit',
  'management',
  'exit',
  'outcome',
];

const visualStageLabels = {
  'market_context': 'Market context and bias',
  'setup': 'Setup identification',
  'confirmation': 'Entry confirmation',
  'entry': 'Entry trigger',
  'stay_out': 'Stay-out conditions',
  'stop_invalidation': 'Stop-loss and invalidation',
  'take_profit': 'Take-profit conditions',
  'management': 'Holding and trade management',
  'exit': 'Exit conditions',
  'outcome': 'Final outcome and rule adherence',
};

const visualTimeframes = ['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1'];

String canonicalVisualTimeframe(String value) {
  switch (value.trim().toUpperCase()) {
    case '1M':
    case 'M1':
      return 'M1';
    case '5M':
    case 'M5':
      return 'M5';
    case '15M':
    case 'M15':
      return 'M15';
    case '30M':
    case 'M30':
      return 'M30';
    case '1H':
    case 'H1':
      return 'H1';
    case '4H':
    case 'H4':
      return 'H4';
    case '1D':
    case 'D1':
      return 'D1';
    default:
      return value.trim().toUpperCase();
  }
}

class VisualStrategyStage {
  const VisualStrategyStage({
    required this.id,
    required this.category,
    required this.label,
    required this.dependsOn,
  });

  final String id;
  final String category;
  final String label;
  final List<String> dependsOn;

  Map<String, Object?> toJson() => {
        'id': id,
        'category': category,
        'label': label,
        'depends_on': dependsOn,
      };

  factory VisualStrategyStage.fromJson(Object? value) {
    final map = _stringMap(value, 'stage');
    return VisualStrategyStage(
      id: _string(map, 'id'),
      category: _string(map, 'category'),
      label: _string(map, 'label'),
      dependsOn: _stringList(map['depends_on'], 'stage dependencies'),
    );
  }
}

class VisualStrategyRule {
  const VisualStrategyRule({
    required this.id,
    required this.stageId,
    required this.label,
    required this.mode,
    required this.relation,
    required this.dependsOn,
    required this.required,
    required this.blocksEntryWhenSatisfied,
    required this.metric,
    required this.comparator,
    required this.threshold,
    required this.period,
    this.scenarioId,
    this.explanation = '',
  });

  final String id;
  final String stageId;
  final String label;
  final String mode;
  final String relation;
  final List<String> dependsOn;
  final bool required;
  final bool blocksEntryWhenSatisfied;
  final String metric;
  final String comparator;
  final double? threshold;
  final int period;
  final String? scenarioId;
  final String explanation;

  Map<String, Object?> toJson() => {
        'id': id,
        'stage_id': stageId,
        'label': label,
        'mode': mode,
        'relation': relation,
        'depends_on': dependsOn,
        'required': required,
        'blocks_entry_when_satisfied': blocksEntryWhenSatisfied,
        'metric': metric,
        'comparator': comparator,
        'threshold': threshold,
        'period': period,
        'scenario_id': scenarioId,
        'explanation': explanation,
      };

  factory VisualStrategyRule.fromJson(Object? value) {
    final map = _stringMap(value, 'rule');
    final threshold = map['threshold'];
    return VisualStrategyRule(
      id: _string(map, 'id'),
      stageId: _string(map, 'stage_id'),
      label: _string(map, 'label'),
      mode: _string(map, 'mode'),
      relation: _string(map, 'relation'),
      dependsOn: _stringList(map['depends_on'], 'rule dependencies'),
      required: map['required'] == true,
      blocksEntryWhenSatisfied: map['blocks_entry_when_satisfied'] == true,
      metric: _string(map, 'metric'),
      comparator: _string(map, 'comparator'),
      threshold: threshold is num ? threshold.toDouble() : null,
      period: map['period'] is num ? (map['period'] as num).toInt() : 1,
      scenarioId:
          map['scenario_id'] is String ? map['scenario_id'] as String : null,
      explanation:
          map['explanation'] is String ? map['explanation'] as String : '',
    );
  }
}

class VisualEntryScenario {
  const VisualEntryScenario({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'description': description,
      };

  factory VisualEntryScenario.fromJson(Object? value) {
    final map = _stringMap(value, 'entry scenario');
    return VisualEntryScenario(
      id: _string(map, 'id'),
      name: _string(map, 'name'),
      description:
          map['description'] is String ? map['description'] as String : '',
    );
  }
}

class VisualStrategyDefinition {
  const VisualStrategyDefinition({
    required this.name,
    required this.instruments,
    required this.timeframes,
    required this.sessions,
    required this.timezone,
    required this.stages,
    required this.rules,
    required this.scenarios,
    required this.riskManagement,
    required this.executionAssumptions,
  });

  final String name;
  final List<String> instruments;
  final List<String> timeframes;
  final List<String> sessions;
  final String timezone;
  final List<VisualStrategyStage> stages;
  final List<VisualStrategyRule> rules;
  final List<VisualEntryScenario> scenarios;
  final Map<String, Object?> riskManagement;
  final Map<String, Object?> executionAssumptions;

  Map<String, Object?> toJson() => {
        'schema_version': 1,
        'name': name,
        'instruments': instruments,
        'timeframes': timeframes,
        'sessions': sessions,
        'timezone': timezone,
        'stages': stages.map((stage) => stage.toJson()).toList(),
        'rules': rules.map((rule) => rule.toJson()).toList(),
        'scenarios': scenarios.map((scenario) => scenario.toJson()).toList(),
        'risk_management': riskManagement,
        'execution_assumptions': executionAssumptions,
      };

  String encode() => jsonEncode(toJson());

  factory VisualStrategyDefinition.fromJson(Object? value) {
    final map = _stringMap(value, 'strategy definition');
    if (map['schema_version'] != 1) {
      throw const FormatException('Unsupported strategy definition version.');
    }
    return VisualStrategyDefinition(
      name: _string(map, 'name'),
      instruments: _stringList(map['instruments'], 'instruments'),
      timeframes: _stringList(map['timeframes'], 'timeframes')
          .map(canonicalVisualTimeframe)
          .toList(),
      sessions: _stringList(map['sessions'], 'sessions'),
      timezone: _string(map, 'timezone'),
      stages: _objectList(map['stages'], VisualStrategyStage.fromJson),
      rules: _objectList(map['rules'], VisualStrategyRule.fromJson),
      scenarios: _objectList(map['scenarios'], VisualEntryScenario.fromJson),
      riskManagement: _stringMap(
        map['risk_management'] ?? const <String, Object?>{},
        'risk management',
      ),
      executionAssumptions: _stringMap(
        map['execution_assumptions'] ?? const <String, Object?>{},
        'execution assumptions',
      ),
    );
  }

  factory VisualStrategyDefinition.decode(String value) =>
      VisualStrategyDefinition.fromJson(jsonDecode(value));

  String? validate() {
    if (name.trim().isEmpty) return 'Enter a strategy name.';
    if (timeframes.isEmpty) return 'Select at least one timeframe.';
    if (timeframes.any((timeframe) => !visualTimeframes.contains(timeframe))) {
      return 'Select supported market timeframes.';
    }
    if (sessions.isEmpty) return 'Select at least one trading session.';
    if (stages.isEmpty) return 'Add at least one checklist stage.';
    if (scenarios.isEmpty) return 'Add at least one entry scenario.';
    if (rules.isEmpty) return 'Add at least one strategy rule.';

    final stageIds = stages.map((stage) => stage.id).toSet();
    final ruleIds = rules.map((rule) => rule.id).toSet();
    final scenarioIds = scenarios.map((scenario) => scenario.id).toSet();
    if (stageIds.length != stages.length ||
        ruleIds.length != rules.length ||
        scenarioIds.length != scenarios.length) {
      return 'Stage, rule and scenario identifiers must be unique.';
    }
    if (scenarios.any((scenario) => scenario.name.trim().isEmpty)) {
      return 'Give every entry scenario a name.';
    }

    final stageIndex = {
      for (var index = 0; index < stages.length; index++)
        stages[index].id: index,
    };
    for (final stage in stages) {
      if (stage.id.trim().isEmpty ||
          stage.label.trim().isEmpty ||
          !visualStageCategories.contains(stage.category)) {
        return 'Each checklist stage needs a valid category and label.';
      }
      if (stage.dependsOn
          .any((id) => !stageIds.contains(id) || id == stage.id)) {
        return 'A checklist stage has an invalid dependency.';
      }
      if (stage.dependsOn
          .any((id) => stageIndex[id]! >= stageIndex[stage.id]!)) {
        return 'A stage can depend only on an earlier stage.';
      }
    }
    if (_hasCycle(stages.map((stage) => (stage.id, stage.dependsOn)))) {
      return 'Checklist stage dependencies contain a cycle.';
    }

    for (final rule in rules) {
      if (rule.id.trim().isEmpty || rule.label.trim().isEmpty) {
        return 'Every rule needs a label.';
      }
      if (!stageIds.contains(rule.stageId)) {
        return 'A rule refers to a missing checklist stage.';
      }
      if (rule.dependsOn.any((id) => !ruleIds.contains(id) || id == rule.id)) {
        return 'A rule has an invalid dependency.';
      }
      if (rule.dependsOn.any((id) {
        final dependency = rules.firstWhere((item) => item.id == id);
        return rule.scenarioId != null &&
            dependency.scenarioId != null &&
            rule.scenarioId != dependency.scenarioId;
      })) {
        return 'A rule cannot depend on a rule from another entry scenario.';
      }
      if (!visualRuleModes.contains(rule.mode) ||
          !visualRuleRelations.contains(rule.relation)) {
        return 'A rule has an unsupported evaluation mode or relationship.';
      }
      if (rule.scenarioId != null && !scenarioIds.contains(rule.scenarioId)) {
        return 'A rule refers to a missing entry scenario.';
      }
      if (rule.mode == 'numeric') {
        if (!visualRuleMetrics.contains(rule.metric) ||
            !visualRuleComparators.contains(rule.comparator) ||
            rule.threshold == null ||
            !rule.threshold!.isFinite ||
            rule.period < 1 ||
            rule.period > 10000) {
          return 'A numerical rule has an invalid metric, comparison or value.';
        }
      } else if (rule.blocksEntryWhenSatisfied &&
          stages.firstWhere((stage) => stage.id == rule.stageId).category !=
              'stay_out') {
        return 'Only stay-out rules can prohibit an entry.';
      }
    }
    for (final scenario in scenarios) {
      final hasEntryRule = rules.any((rule) =>
          rule.stageId ==
              stages
                  .firstWhere((stage) => stage.category == 'entry',
                      orElse: () => const VisualStrategyStage(
                            id: '',
                            category: '',
                            label: '',
                            dependsOn: [],
                          ))
                  .id &&
          (rule.scenarioId == null || rule.scenarioId == scenario.id));
      if (!hasEntryRule) {
        return 'Each entry scenario needs at least one entry-trigger rule.';
      }
    }
    if (_hasCycle(rules.map((rule) => (rule.id, rule.dependsOn)))) {
      return 'Rule dependencies contain a cycle.';
    }
    return null;
  }
}

VisualStrategyDefinition legacyVisualStrategyDefinition({
  required String name,
  required String entryConditions,
  required String exitConditions,
  required String stopLossRules,
  required String takeProfitRules,
  required String stayOutConditions,
  required List<String> sessions,
  required List<String> timeframes,
}) {
  const legacyCategories = [
    ('setup', 'Legacy setup'),
    ('entry', 'Legacy entry conditions'),
    ('stay_out', 'Legacy stay-out conditions'),
    ('stop_invalidation', 'Legacy stop-loss rules'),
    ('take_profit', 'Legacy take-profit rules'),
    ('exit', 'Legacy exit conditions'),
  ];
  final stages = visualStageCategories
      .map((category) => VisualStrategyStage(
            id: 'legacy-stage-$category',
            category: category,
            label: visualStageLabels[category]!,
            dependsOn: const [],
          ))
      .toList();
  final legacyText = <String, String>{
    'entry': entryConditions,
    'exit': exitConditions,
    'stop_invalidation': stopLossRules,
    'take_profit': takeProfitRules,
    'stay_out': stayOutConditions,
  };
  final rules = <VisualStrategyRule>[];
  for (final category in legacyCategories.map((entry) => entry.$1).toSet()) {
    final text = legacyText[category]?.trim();
    if (text == null || text.isEmpty) continue;
    rules.add(VisualStrategyRule(
      id: 'legacy-rule-$category',
      stageId: 'legacy-stage-$category',
      label: text,
      mode: 'manual',
      relation: 'and',
      dependsOn: const [],
      required: true,
      blocksEntryWhenSatisfied: category == 'stay_out',
      metric: '',
      comparator: '>',
      threshold: null,
      period: 1,
    ));
  }
  return VisualStrategyDefinition(
    name: name,
    instruments: const [],
    timeframes: timeframes.map(canonicalVisualTimeframe).toList(),
    sessions: sessions,
    timezone: 'local',
    stages: stages,
    rules: rules,
    scenarios: const [
      VisualEntryScenario(
        id: 'legacy-default-scenario',
        name: 'Legacy entry scenario',
        description: '',
      ),
    ],
    riskManagement: const {},
    executionAssumptions: const {},
  );
}

class VisualChecklistStageState {
  const VisualChecklistStageState({
    required this.stage,
    required this.rules,
    required this.ready,
    required this.complete,
  });

  final VisualStrategyStage stage;
  final List<(VisualStrategyRule, String)> rules;
  final bool ready;
  final bool complete;
}

class VisualChecklistSnapshot {
  const VisualChecklistSnapshot({
    required this.stages,
    required this.currentStageId,
    required this.canRecordEntry,
    required this.entryBlockReason,
    required this.hasInvalidatedRule,
    required this.progress,
  });

  final List<VisualChecklistStageState> stages;
  final String? currentStageId;
  final bool canRecordEntry;
  final String? entryBlockReason;
  final bool hasInvalidatedRule;
  final double progress;
}

VisualChecklistSnapshot buildVisualChecklist({
  required VisualStrategyDefinition definition,
  required String scenarioId,
  required Map<String, String> states,
}) {
  final scenarioExists =
      definition.scenarios.any((scenario) => scenario.id == scenarioId);
  if (!scenarioExists) {
    throw StateError('The selected entry scenario is not in this version.');
  }
  final rules = definition.rules
      .where((rule) => rule.scenarioId == null || rule.scenarioId == scenarioId)
      .toList();
  String effectiveState(VisualStrategyRule rule) {
    final dependencyStates =
        rule.dependsOn.map((id) => states[id] ?? 'pending').toList();
    if (rule.relation == 'invalidate' &&
        dependencyStates.any((state) => state == 'satisfied')) {
      return 'invalidated';
    }
    return states[rule.id] ?? 'pending';
  }

  bool dependenciesSatisfied(VisualStrategyRule rule) {
    if (rule.dependsOn.isEmpty) return true;
    final dependencies =
        rule.dependsOn.map((id) => states[id] ?? 'pending').toList();
    return switch (rule.relation) {
      'or' => dependencies.any((state) => state == 'satisfied'),
      'not' => dependencies.every((state) => state != 'satisfied'),
      'and' ||
      'then' ||
      'wait' ||
      'invalidate' =>
        dependencies.every((state) => state == 'satisfied'),
      _ => false,
    };
  }

  final stageResults = <VisualChecklistStageState>[];
  for (final stage in definition.stages) {
    final stageRules = rules.where((rule) => rule.stageId == stage.id).toList();
    final stageDependenciesComplete = stage.dependsOn.every((stageId) {
      final dependency = stageResults.where(
        (result) => result.stage.id == stageId,
      );
      return dependency.isNotEmpty && dependency.first.complete;
    });
    final ready = stageDependenciesComplete &&
        stageRules.where((rule) => rule.required).every(dependenciesSatisfied);
    final complete = stageDependenciesComplete &&
        stageRules.where((rule) => rule.required).every((rule) {
          final state = effectiveState(rule);
          return state == 'satisfied' || state == 'not_applicable';
        });
    stageResults.add(VisualChecklistStageState(
      stage: stage,
      rules: stageRules.map((rule) => (rule, effectiveState(rule))).toList(),
      ready: ready,
      complete: complete,
    ));
  }

  final stayOutSatisfied = rules.any((rule) =>
      rule.blocksEntryWhenSatisfied && effectiveState(rule) == 'satisfied');
  final stayOutPending = rules.any((rule) =>
      rule.blocksEntryWhenSatisfied &&
      rule.required &&
      effectiveState(rule) == 'pending');
  final entryStages =
      definition.stages.where((stage) => stage.category == 'entry').toList();
  final entryRules = rules
      .where((rule) =>
          entryStages.any((stage) => stage.id == rule.stageId) && rule.required)
      .toList();
  final unmetEntryRule = entryRules.any(
    (rule) =>
        effectiveState(rule) != 'satisfied' || !dependenciesSatisfied(rule),
  );
  final invalidated = rules.any(
    (rule) => effectiveState(rule) == 'invalidated',
  );
  final canRecordEntry = !stayOutSatisfied &&
      !stayOutPending &&
      !unmetEntryRule &&
      !invalidated &&
      entryStages.every((stage) => stageResults
          .where((result) => result.stage.id == stage.id)
          .any((result) => result.ready)) &&
      entryRules.isNotEmpty;
  final current = stageResults.where((stage) => stage.ready && !stage.complete);
  final totalRules = rules.length;
  final resolvedRules =
      rules.where((rule) => effectiveState(rule) != 'pending').length;

  return VisualChecklistSnapshot(
    stages: stageResults,
    currentStageId: current.isEmpty ? null : current.first.stage.id,
    canRecordEntry: canRecordEntry,
    entryBlockReason: stayOutSatisfied
        ? 'A stay-out condition prohibits this entry.'
        : stayOutPending
            ? 'Evaluate all mandatory stay-out conditions before entry.'
        : invalidated
            ? 'A rule invalidates this setup.'
            : unmetEntryRule
                ? 'Complete all mandatory entry rules before entering.'
                : entryRules.isEmpty
                    ? 'This version has no applicable entry-trigger rules.'
                    : null,
    hasInvalidatedRule: invalidated,
    progress: totalRules == 0 ? 0 : resolvedRules / totalRules,
  );
}

VisualStrategyDefinition visualStrategyDefinitionFromVersion(
  Map<String, Object?> version,
) {
  final definitionJson = version['definition_json'];
  if (definitionJson is String && definitionJson.isNotEmpty) {
    return VisualStrategyDefinition.decode(definitionJson);
  }

  final legacySnapshot = version['legacy_snapshot_json'];
  final legacy = legacySnapshot is String && legacySnapshot.isNotEmpty
      ? _stringMap(jsonDecode(legacySnapshot), 'legacy strategy snapshot')
      : version;
  return legacyVisualStrategyDefinition(
    name: _legacyText(legacy, 'name', version['name']),
    entryConditions: _legacyText(
      legacy,
      'entry_conditions',
      version['legacy_entry_conditions'],
    ),
    exitConditions: _legacyText(
      legacy,
      'exit_conditions',
      version['legacy_exit_conditions'],
    ),
    stopLossRules: _legacyText(
      legacy,
      'stop_loss_rules',
      version['legacy_stop_loss_rules'],
    ),
    takeProfitRules: _legacyText(
      legacy,
      'take_profit_rules',
      version['legacy_take_profit_rules'],
    ),
    stayOutConditions: _legacyText(
      legacy,
      'stay_out_conditions',
      version['legacy_stay_out_conditions'],
    ),
    sessions: _legacyJsonList(
      legacy,
      'sessions_json',
      version['legacy_sessions_json'],
    ),
    timeframes: _legacyJsonList(
      legacy,
      'timeframes_json',
      version['legacy_timeframes_json'],
    ),
  );
}

String _legacyText(
  Map<String, Object?> source,
  String key,
  Object? fallback,
) {
  final value = source[key] ?? fallback;
  return value is String ? value : '';
}

List<String> _legacyJsonList(
  Map<String, Object?> source,
  String key,
  Object? fallback,
) {
  final value = source[key] ?? fallback;
  if (value is! String || value.isEmpty) return const [];
  final decoded = jsonDecode(value);
  return _stringList(decoded, key);
}

bool _hasCycle(Iterable<(String, List<String>)> graph) {
  final edges = Map<String, List<String>>.fromEntries(
    graph.map((entry) => MapEntry(entry.$1, entry.$2)),
  );
  final visiting = <String>{};
  final visited = <String>{};

  bool visit(String id) {
    if (visiting.contains(id)) return true;
    if (!visited.add(id)) return false;
    visiting.add(id);
    for (final dependency in edges[id] ?? const <String>[]) {
      if (visit(dependency)) return true;
    }
    visiting.remove(id);
    return false;
  }

  return edges.keys.any(visit);
}

bool canEvaluateVisualRule(
  VisualStrategyRule rule,
  Map<String, String> states,
) {
  if (rule.dependsOn.isEmpty) return true;
  final dependencies =
      rule.dependsOn.map((id) => states[id] ?? 'pending').toList();
  return switch (rule.relation) {
    'and' ||
    'then' ||
    'wait' =>
      dependencies.every((state) => state == 'satisfied'),
    'or' => dependencies.any((state) => state == 'satisfied'),
    'not' => dependencies.every(
        (state) => state == 'failed' || state == 'not_applicable',
      ),
    'invalidate' => dependencies.every((state) => state == 'satisfied'),
    _ => false,
  };
}

Map<String, Object?> _stringMap(Object? value, String label) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('Saved $label is invalid.');
  }
  return value.map((key, value) => MapEntry(key as String, value));
}

String _string(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) throw FormatException('Saved field "$key" is invalid.');
  return value;
}

List<String> _stringList(Object? value, String label) {
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('Saved $label are invalid.');
  }
  return value.cast<String>();
}

List<T> _objectList<T>(
  Object? value,
  T Function(Object?) decode,
) {
  if (value is! List) throw const FormatException('Saved list is invalid.');
  return value.map(decode).toList();
}
