import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/repositories/visual_backtesting_repository.dart';
import '../../widgets/common.dart';
import 'case_form_screen.dart';

class VisualStrategyFormScreen extends ConsumerStatefulWidget {
  const VisualStrategyFormScreen({super.key, this.strategyId});

  final String? strategyId;

  @override
  ConsumerState<VisualStrategyFormScreen> createState() =>
      _VisualStrategyFormScreenState();
}

class _VisualStrategyFormScreenState
    extends ConsumerState<VisualStrategyFormScreen> {
  final _name = TextEditingController();
  final _entry = TextEditingController();
  final _exit = TextEditingController();
  final _stop = TextEditingController();
  final _target = TextEditingController();
  final _stayOut = TextEditingController();
  final _sessions = <String>{};
  final _timeframes = <String>{};
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.strategyId != null) {
      _loading = true;
      _load();
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _entry,
      _exit,
      _stop,
      _target,
      _stayOut,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> _decodeOptions(Rec strategy, String key) {
    final decoded = jsonDecode(strategy.s(key, '[]'));
    if (decoded is! List || decoded.any((value) => value is! String)) {
      throw const FormatException('Saved strategy selections are invalid.');
    }
    return decoded.cast<String>();
  }

  Future<void> _load() async {
    try {
      final strategy = await ref
          .read(visualBacktestingRepositoryProvider)
          .strategyById(widget.strategyId!);
      if (strategy == null) throw StateError('Strategy not found.');
      _name.text = strategy.s('name');
      _entry.text = strategy.s('entry_conditions');
      _exit.text = strategy.s('exit_conditions');
      _stop.text = strategy.s('stop_loss_rules');
      _target.text = strategy.s('take_profit_rules');
      _stayOut.text = strategy.s('stay_out_conditions');
      _sessions.addAll(_decodeOptions(strategy, 'sessions_json'));
      _timeframes.addAll(_decodeOptions(strategy, 'timeframes_json'));
    } catch (e) {
      if (mounted) snack(context, 'Could not load strategy: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(visualBacktestingRepositoryProvider).saveStrategy(
            id: widget.strategyId,
            name: _name.text,
            entryConditions: _entry.text,
            exitConditions: _exit.text,
            stopLossRules: _stop.text,
            takeProfitRules: _target.text,
            stayOutConditions: _stayOut.text,
            sessions: _sessions.toList(),
            timeframes: _timeframes.toList(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) snack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _multiSelect(
      String title, List<String> options, Set<String> selected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final option in options)
                FilterChip(
                  label: Text(option),
                  selected: selected.contains(option),
                  onSelected: (value) => setState(() {
                    if (value) {
                      selected.add(option);
                    } else {
                      selected.remove(option);
                    }
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.strategyId == null ? 'New strategy' : 'Edit strategy'),
        actions: [
          IconButton(
            tooltip: 'Save strategy',
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
                  title: 'Strategy rules',
                  children: [
                    LabeledField(controller: _name, label: 'Strategy name'),
                    LabeledField(
                      controller: _entry,
                      label: 'Entry conditions',
                      hint: 'What must be true before entry?',
                      minLines: 2,
                      maxLines: 6,
                    ),
                    LabeledField(
                      controller: _exit,
                      label: 'Exit conditions',
                      hint: 'What closes the setup or invalidates it?',
                      minLines: 2,
                      maxLines: 6,
                    ),
                    LabeledField(
                      controller: _stop,
                      label: 'Stop-loss rules',
                      minLines: 2,
                      maxLines: 5,
                    ),
                    LabeledField(
                      controller: _target,
                      label: 'Take-profit rules',
                      minLines: 2,
                      maxLines: 5,
                    ),
                    LabeledField(
                      controller: _stayOut,
                      label: 'Conditions to stay out',
                      hint: 'When must this strategy not be used?',
                      minLines: 2,
                      maxLines: 6,
                    ),
                  ],
                ),
                SectionCard(
                  title: 'Market context',
                  children: [
                    _multiSelect(
                      'Trading sessions',
                      visualTradingSessions,
                      _sessions,
                    ),
                    _multiSelect('Timeframes', kTimeframes, _timeframes),
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
                  label: Text(_saving ? 'Saving...' : 'Save strategy'),
                ),
              ],
            ),
    );
  }
}
