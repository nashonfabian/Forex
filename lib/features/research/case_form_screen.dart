import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/repositories/research_repository.dart';
import '../../widgets/common.dart';

const kInstrumentSuggestions = ['XAUUSD', 'BTCUSD', 'US100'];
const kTimeframes = ['1M', '5M', '15M', '30M', '1H', '4H', '1D'];

/// Create or edit a research case. The hypothesis block can be edited until it is locked.
class CaseFormScreen extends ConsumerStatefulWidget {
  const CaseFormScreen({super.key, this.caseId});

  final String? caseId;

  @override
  ConsumerState<CaseFormScreen> createState() => _CaseFormScreenState();
}

class _CaseFormScreenState extends ConsumerState<CaseFormScreen> {
  final _title = TextEditingController();
  final _instrument = TextEditingController();
  final _reference = TextEditingController();
  final _tags = TextEditingController();
  final _hypothesis = TextEditingController();
  final _evidenceFor = TextEditingController();
  final _evidenceAgainst = TextEditingController();
  final _acceptance = TextEditingController();
  final _alternatives = TextEditingController();
  final _invalidation = TextEditingController();

  String? _timeframe;
  String? _condition;
  String? _direction;
  int? _confidence;
  late DateTime _observedAt = ref.read(clockProvider).nowUtc().toLocal();
  bool _locked = false;
  bool _loading = false;
  bool _saving = false;
  String? _id;

  @override
  void initState() {
    super.initState();
    _id = widget.caseId;
    if (_id != null) {
      _loading = true;
      _load();
    }
  }

  @override
  void dispose() {
    for (final c in [
      _title, _instrument, _reference, _tags, _hypothesis,
      _evidenceFor, _evidenceAgainst, _acceptance, _alternatives, _invalidation,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final c = await ref.read(researchRepositoryProvider).caseById(_id!);
    final tags = await ref.read(tagsRepositoryProvider).namesFor('research_cases', _id!);
    if (!mounted) return;
    if (c != null) {
      _title.text = c.s('title');
      _instrument.text = c.s('instrument');
      _timeframe = c.sn('timeframe');
      _condition = c.sn('market_condition');
      _direction = c.sn('exploration_direction');
      _reference.text = c.s('reference_level');
      _tags.text = tags.join(', ');
      _hypothesis.text = c.s('hypothesis');
      _evidenceFor.text = c.s('evidence_for');
      _evidenceAgainst.text = c.s('evidence_against');
      _acceptance.text = c.s('acceptance_rejection');
      _alternatives.text = c.s('alternatives');
      _invalidation.text = c.s('invalidation');
      _confidence = c.iN('confidence');
      final observed = DateTime.tryParse(c.s('observed_at'));
      if (observed != null) _observedAt = observed.toLocal();
      _locked = c.sn('hypothesis_locked_at') != null;
    }
    setState(() => _loading = false);
  }

  Map<String, Object?> _values() {
    final values = <String, Object?>{
      'title': _title.text.trim(),
      'instrument': emptyToNull(_instrument.text),
      'timeframe': _timeframe,
      'observed_at': _observedAt.toUtc().toIso8601String(),
      'market_condition': _condition,
      'reference_level': emptyToNull(_reference.text),
      'exploration_direction': _direction,
    };
    // Once locked, the hypothesis fields are not sent at all.
    if (!_locked) {
      values.addAll({
        'hypothesis': emptyToNull(_hypothesis.text),
        'evidence_for': emptyToNull(_evidenceFor.text),
        'evidence_against': emptyToNull(_evidenceAgainst.text),
        'acceptance_rejection': emptyToNull(_acceptance.text),
        'alternatives': emptyToNull(_alternatives.text),
        'invalidation': emptyToNull(_invalidation.text),
        'confidence': _confidence,
      });
    }
    return values;
  }

  /// Saves and returns the case id, or null if something was missing.
  Future<String?> _persist() async {
    if (_title.text.trim().isEmpty) {
      snack(context, 'Give the case a title.');
      return null;
    }
    final repo = ref.read(researchRepositoryProvider);
    final tags = splitTags(_tags.text);
    if (_id == null) {
      _id = await repo.createCase(_values(), tags);
    } else {
      await repo.updateCase(_id!, _values(), tags);
    }
    return _id;
  }

  Future<void> _save({bool lock = false}) async {
    if (_saving) return;
    if (lock && _hypothesis.text.trim().isEmpty) {
      snack(context, 'Write a hypothesis before locking it.');
      return;
    }
    if (lock) {
      final ok = await confirmDialog(
        context,
        title: 'Lock this hypothesis?',
        message: 'Locking is permanent. The text is kept exactly as written, so you can '
            'compare it honestly with what happens. Later thoughts go in as addenda.',
        confirmLabel: 'Lock it',
      );
      if (!ok) return;
    }
    setState(() => _saving = true);
    try {
      final id = await _persist();
      if (id != null && lock) {
        await ref.read(researchRepositoryProvider).lockHypothesis(id);
      }
      if (id != null && mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) snack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final instruments = ref.watch(instrumentsProvider).valueOrNull ?? const <String>[];
    final suggestions = {...kInstrumentSuggestions, ...instruments}.toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.caseId == null ? 'New research case' : 'Edit case')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionCard(
                  title: 'Setup',
                  children: [
                    LabeledField(controller: _title, label: 'Title', hint: 'For example: XAUUSD 15M - failed push above value'),
                    SuggestField(controller: _instrument, label: 'Instrument', suggestions: suggestions),
                    ChoiceRow(
                      label: 'Timeframe',
                      options: kTimeframes,
                      value: _timeframe,
                      onChanged: (v) => setState(() => _timeframe = v),
                    ),
                    PickerField(
                      label: 'Date and time observed',
                      text: formatLocalDateTime(_observedAt.toUtc().toIso8601String()),
                      onTap: () async {
                        final picked = await pickDateTime(context, _observedAt);
                        if (picked != null) setState(() => _observedAt = picked);
                      },
                    ),
                    ChoiceRow(
                      label: 'Market condition',
                      options: marketConditions,
                      value: _condition,
                      onChanged: (v) => setState(() => _condition = v),
                    ),
                    LabeledField(controller: _reference, label: 'Reference level or value area'),
                    ChoiceRow(
                      label: 'Direction of exploration',
                      options: explorationDirections,
                      value: _direction,
                      onChanged: (v) => setState(() => _direction = v),
                    ),
                    LabeledField(controller: _tags, label: 'Tags', hint: 'Separate with commas'),
                  ],
                ),
                SectionCard(
                  title: 'Hypothesis (written before the outcome)',
                  children: [
                    if (_locked)
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.lock_outline),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text('This hypothesis is locked and cannot be changed. '
                                  'Add observations and addenda on the case page instead.'),
                            ),
                          ],
                        ),
                      ),
                    LabeledField(
                        controller: _hypothesis, label: 'Hypothesis', minLines: 2, maxLines: 8, enabled: !_locked),
                    LabeledField(
                        controller: _evidenceFor,
                        label: 'Evidence supporting it',
                        minLines: 2,
                        maxLines: 8,
                        enabled: !_locked),
                    LabeledField(
                        controller: _evidenceAgainst,
                        label: 'Evidence contradicting it',
                        minLines: 2,
                        maxLines: 8,
                        enabled: !_locked),
                    LabeledField(
                        controller: _acceptance,
                        label: 'Acceptance / rejection observations',
                        minLines: 2,
                        maxLines: 8,
                        enabled: !_locked),
                    LabeledField(
                        controller: _alternatives,
                        label: 'Alternative scenarios',
                        minLines: 2,
                        maxLines: 8,
                        enabled: !_locked),
                    LabeledField(
                        controller: _invalidation,
                        label: 'What would invalidate it',
                        minLines: 2,
                        maxLines: 8,
                        enabled: !_locked),
                    ChoiceRow(
                      label: 'Confidence (1 low - 5 high)',
                      options: const ['1', '2', '3', '4', '5'],
                      value: _confidence?.toString(),
                      enabled: !_locked,
                      onChanged: (v) => setState(() => _confidence = v == null ? null : int.tryParse(v)),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => _save(),
                        child: Text(_locked ? 'Save changes' : 'Save draft'),
                      ),
                    ),
                    if (!_locked) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving ? null : () => _save(lock: true),
                          icon: const Icon(Icons.lock_outline),
                          label: const Text('Save and lock'),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
