import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/backtesting/strategy_definition.dart';
import '../../data/repositories/visual_backtesting_repository.dart';
import '../../widgets/common.dart';
import 'visual_test_screen.dart';

class VisualExperimentsScreen extends ConsumerStatefulWidget {
  const VisualExperimentsScreen({super.key});

  @override
  ConsumerState<VisualExperimentsScreen> createState() =>
      _VisualExperimentsScreenState();
}

class _VisualExperimentsScreenState
    extends ConsumerState<VisualExperimentsScreen> {
  late final Future<List<Rec>> _versionsFuture = _loadVersions();

  Future<List<Rec>> _loadVersions() async {
    final repository = ref.read(visualBacktestingRepositoryProvider);
    final strategies = await repository.strategies();
    final versions = <Rec>[];
    for (final strategy in strategies) {
      for (final version
          in await repository.strategyVersions(strategy.s('id'))) {
        versions.add({
          ...version,
          'strategy_name': strategy.s('name'),
        });
      }
    }
    return versions;
  }

  Future<void> _createExperiment(List<Rec> versions) async {
    final details = await _editExperiment(
      title: 'New experiment',
      versions: versions,
      versionLabel: 'Baseline strategy version',
    );
    if (details == null || !mounted) return;
    await _run(() async {
      await ref.read(visualBacktestingRepositoryProvider).createExperiment(
            name: details.name,
            baselineVersionId: details.versionId,
          );
    });
  }

  Future<void> _addVariant(String experimentId, List<Rec> versions) async {
    final details = await _editExperiment(
      title: 'Add experiment variant',
      versions: versions,
      versionLabel: 'Strategy version for this variant',
    );
    if (details == null || !mounted) return;
    await _run(() async {
      await ref.read(visualBacktestingRepositoryProvider).addExperimentVariant(
            experimentId: experimentId,
            name: details.name,
            strategyVersionId: details.versionId,
          );
    });
  }

  Future<void> _startVariantTest(
    BuildContext context,
    Rec experiment,
    Rec variant,
    Rec version,
  ) async {
    final definition = visualStrategyDefinitionFromVersion(version);
    final scenarioId = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Choose entry scenario'),
              subtitle: Text(
                  'The new test will be linked to this experiment variant.'),
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
    if (scenarioId == null || !context.mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => VisualTestScreen(
          strategyId: version.s('strategy_id'),
          strategyVersionId: version.s('id'),
          scenarioId: scenarioId,
          mode: 'manual',
          experimentId: experiment.s('id'),
          experimentVariantId: variant.s('id'),
        ),
      ),
    );
  }

  Future<_ExperimentDetails?> _editExperiment({
    required String title,
    required List<Rec> versions,
    required String versionLabel,
  }) {
    final name = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? versionId = versions.isEmpty ? null : versions.first.s('id');
    return showDialog<_ExperimentDetails>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a name.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  if (versions.isEmpty)
                    const Text(
                        'Save a strategy version before creating an experiment.')
                  else
                    DropdownButtonFormField<String>(
                      value: versionId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: versionLabel),
                      validator: (value) =>
                          value == null ? 'Choose a strategy version.' : null,
                      items: [
                        for (final version in versions)
                          DropdownMenuItem(
                            value: version.s('id'),
                            child: Text(
                              '${version.s('strategy_name')} · v${version.i('version_number')}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => versionId = value),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: versions.isEmpty
                  ? null
                  : () {
                      if (!formKey.currentState!.validate()) return;
                      final title = name.text.trim();
                      Navigator.pop(
                        dialogContext,
                        _ExperimentDetails(title, versionId!),
                      );
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ).whenComplete(name.dispose);
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) snack(context, 'Could not save experiment: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final experiments = ref.watch(visualExperimentsProvider);
    final tests = ref.watch(visualTestsProvider(null));
    final results = ref.watch(visualTestResultsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Strategy experiments')),
      body: FutureBuilder<List<Rec>>(
        future: _versionsFuture,
        builder: (context, versionSnapshot) {
          if (versionSnapshot.hasError) {
            return EmptyState(
              'Could not load strategy versions: ${versionSnapshot.error}',
            );
          }
          if (!versionSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final versions = versionSnapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Compare saved, immutable strategy versions. Results stay linked to their exact version; parameter overrides are not applied by this manual comparison workflow.',
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: versions.isEmpty
                      ? null
                      : () => _createExperiment(versions),
                  icon: const Icon(Icons.add),
                  label: const Text('New experiment'),
                ),
              ),
              experiments.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) =>
                    EmptyState('Could not load experiments: $error'),
                data: (items) {
                  if (items.isEmpty) {
                    return const EmptyState(
                      'No experiments yet. Compare versions without mixing their test records.',
                    );
                  }
                  return Column(
                    children: [
                      for (final experiment in items)
                        _ExperimentCard(
                          experiment: experiment,
                          versions: versions,
                          tests: tests.valueOrNull ?? const <Rec>[],
                          results: results.valueOrNull ?? const <Rec>[],
                          testsLoading: !tests.hasValue,
                          onAddVariant: () => _addVariant(
                            experiment.s('id'),
                            versions,
                          ),
                          onAssign: (testId, variantId) => _run(
                            () => ref
                                .read(visualBacktestingRepositoryProvider)
                                .assignTestToExperimentVariant(
                                  testId: testId,
                                  variantId: variantId,
                                ),
                          ),
                          onStartTest: (variant, version) => _startVariantTest(
                            context,
                            experiment,
                            variant,
                            version,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ExperimentCard extends ConsumerWidget {
  const _ExperimentCard({
    required this.experiment,
    required this.versions,
    required this.tests,
    required this.results,
    required this.testsLoading,
    required this.onAddVariant,
    required this.onAssign,
    required this.onStartTest,
  });

  final Rec experiment;
  final List<Rec> versions;
  final List<Rec> tests;
  final List<Rec> results;
  final bool testsLoading;
  final VoidCallback onAddVariant;
  final void Function(String testId, String variantId) onAssign;
  final void Function(Rec variant, Rec version) onStartTest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variants = ref.watch(
      visualExperimentVariantsProvider(experiment.s('id')),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(experiment.s('name'),
                style: Theme.of(context).textTheme.titleMedium),
            Text(
              'Baseline: ${experiment.s('baseline_name')} · v${experiment.i('baseline_version_number')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: versions.isEmpty ? null : onAddVariant,
                icon: const Icon(Icons.add),
                label: const Text('Add variant'),
              ),
            ),
            variants.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text('Could not load variants: $error'),
              data: (items) => Column(
                children: [
                  for (final variant in items)
                    _VariantTile(
                      variant: variant,
                      versions: versions,
                      tests: tests,
                      results: results,
                      testsLoading: testsLoading,
                      onAssign: onAssign,
                      onStartTest: onStartTest,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VariantTile extends StatelessWidget {
  const _VariantTile({
    required this.variant,
    required this.versions,
    required this.tests,
    required this.results,
    required this.testsLoading,
    required this.onAssign,
    required this.onStartTest,
  });

  final Rec variant;
  final List<Rec> versions;
  final List<Rec> tests;
  final List<Rec> results;
  final bool testsLoading;
  final void Function(String testId, String variantId) onAssign;
  final void Function(Rec variant, Rec version) onStartTest;

  @override
  Widget build(BuildContext context) {
    final variantId = variant.s('id');
    final versionId = variant.s('strategy_version_id');
    final assignedResults = results
        .where((test) => test.s('experiment_variant_id') == variantId)
        .toList();
    final stats = VisualBacktestStats.fromTests(assignedResults);
    final eligibleTests = tests.where((test) {
      final assignedExperiment = test.sn('experiment_id');
      return test.s('strategy_version_id') == versionId &&
          (assignedExperiment == null ||
              test.sn('experiment_variant_id') == variantId);
    }).toList();
    final matchingVersions =
        versions.where((version) => version.s('id') == versionId).toList();
    final assignedTests = eligibleTests
        .where((test) => test.sn('experiment_variant_id') == variantId)
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${variant.s('name')} · ${variant.s('strategy_name')} v${variant.i('strategy_version_number')}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            '${stats.totalSetups} setups · ${stats.testCount} completed · '
            '${stats.wins} wins / ${stats.losses} losses / ${stats.breakeven} breakeven · '
            'Average R ${stats.meanR?.toStringAsFixed(2) ?? '—'} · '
            '${stats.missingRSampleCount} completed without R',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (matchingVersions.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => onStartTest(variant, matchingVersions.first),
                icon: const Icon(Icons.image_search_outlined),
                label: const Text('Start manual test'),
              ),
            ),
          if (testsLoading)
            const LinearProgressIndicator()
          else if (eligibleTests.isEmpty)
            const Text('No unassigned tests for this exact strategy version.')
          else
            DropdownButtonFormField<String>(
              value: assignedTests.length == 1
                  ? assignedTests.first.s('id')
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Add an existing matching test',
              ),
              items: [
                for (final test in eligibleTests)
                  DropdownMenuItem(
                    value: test.s('id'),
                    child: Text(
                      '${test.s('scenario_id', 'unspecified scenario')} · '
                      '${test.s('instrument', 'Unknown instrument')} '
                      '${test.s('timeframe')} · '
                      '${formatLocalDate(test.sn('tested_at'))}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (testId) {
                if (testId != null) {
                  onAssign(testId, variantId);
                }
              },
            ),
        ],
      ),
    );
  }
}

class _ExperimentDetails {
  const _ExperimentDetails(this.name, this.versionId);

  final String name;
  final String versionId;
}
