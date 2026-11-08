import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/repositories/research_repository.dart';
import '../../data/repositories/trades_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/image_thumb.dart';
import '../research/case_detail_screen.dart';
import '../research/case_form_screen.dart';
import '../research/image_import.dart';
import '../research/image_viewer_screen.dart';

/// Record or review one executed trade. Demo and live trades are kept apart.
class TradeFormScreen extends ConsumerStatefulWidget {
  const TradeFormScreen({super.key, this.tradeId, this.caseId});

  final String? tradeId;

  /// Pre-selects a research case when the trade is created from that case.
  final String? caseId;

  @override
  ConsumerState<TradeFormScreen> createState() => _TradeFormScreenState();
}

class _TradeFormScreenState extends ConsumerState<TradeFormScreen> {
  final _instrument = TextEditingController();
  final _currency = TextEditingController();
  final _entry = TextEditingController();
  final _exit = TextEditingController();
  final _stop = TextEditingController();
  final _target = TextEditingController();
  final _size = TextEditingController();
  final _risk = TextEditingController();
  final _gross = TextEditingController();
  final _costs = TextEditingController();
  final _rationale = TextEditingController();
  final _ruleNotes = TextEditingController();
  final _process = TextEditingController();
  final _review = TextEditingController();

  String _account = 'demo';
  String? _direction;
  String? _currencyCode;
  String? _sizeUnit;
  String _status = 'open';
  String? _adherence;
  String? _caseId;
  String? _caseTitle;
  DateTime? _openedAt;
  DateTime? _closedAt;
  String? _id;
  bool _loading = false;
  bool _saving = false;
  bool _legacyCurrencyMissing = false;
  bool _legacySizeUnitMissing = false;

  @override
  void initState() {
    super.initState();
    _id = widget.tradeId;
    _caseId = widget.caseId;
    _openedAt = ref.read(clockProvider).nowUtc().toLocal();
    if (_id != null) {
      _loading = true;
      _load();
    } else if (_caseId != null) {
      _loadCaseTitle();
    }
  }

  @override
  void dispose() {
    for (final c in [
      _instrument,
      _currency,
      _entry,
      _exit,
      _stop,
      _target,
      _size,
      _risk,
      _gross,
      _costs,
      _rationale,
      _ruleNotes,
      _process,
      _review,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCaseTitle() async {
    if (_caseId == null) return;
    final c = await ref.read(researchRepositoryProvider).caseById(_caseId!);
    if (!mounted) return;
    setState(() {
      _caseTitle = c?.sn('title');
      if (_instrument.text.isEmpty && c != null) {
        _instrument.text = c.s('instrument');
      }
    });
  }

  Future<void> _load() async {
    final t = await ref.read(tradesRepositoryProvider).byId(_id!);
    if (!mounted) return;
    if (t != null) {
      _instrument.text = t.s('instrument');
      _account = t.s('account_type', 'demo');
      _direction = t.sn('direction');
      _currencyCode = t.sn('currency_code')?.toUpperCase();
      _currency.text = _currencyCode ?? '';
      _sizeUnit = t.sn('size_unit');
      _legacyCurrencyMissing = _currencyCode == null;
      _legacySizeUnitMissing = _sizeUnit == null;
      _status = t.s('status', 'open');
      _entry.text = numToText(t.d('entry_price'));
      _exit.text = numToText(t.d('exit_price'));
      _stop.text = numToText(t.d('stop_price'));
      _target.text = numToText(t.d('target_price'));
      _size.text = numToText(t.d('size'));
      _risk.text = minorToText(
        t.iN('initial_risk_minor'),
        fractionDigits: _moneyFractionDigits,
      );
      _gross.text = minorToText(
        t.iN('gross_pnl_minor'),
        fractionDigits: _moneyFractionDigits,
      );
      _costs.text = minorToText(
        t.iN('costs_minor'),
        fractionDigits: _moneyFractionDigits,
      );
      _rationale.text = t.s('setup_rationale');
      _adherence = t.sn('rule_adherence');
      _ruleNotes.text = t.s('rule_notes');
      _process.text = t.s('process_notes');
      _review.text = t.s('review_text');
      _caseId = t.sn('case_id');
      final opened = DateTime.tryParse(t.s('opened_at'));
      _openedAt = opened?.toLocal();
      final closed = DateTime.tryParse(t.s('closed_at'));
      _closedAt = closed?.toLocal();
    }
    await _loadCaseTitle();
    if (mounted) setState(() => _loading = false);
  }

  int get _moneyFractionDigits => currencyFractionDigits(_currencyCode);
  int? get _riskMinor =>
      parseMinor(_risk.text, fractionDigits: _moneyFractionDigits);
  int? get _grossMinor =>
      parseMinor(_gross.text, fractionDigits: _moneyFractionDigits);
  int? get _costsMinor => _costs.text.trim().isEmpty
      ? 0
      : parseMinor(_costs.text, fractionDigits: _moneyFractionDigits);

  Future<String?> _persist() async {
    if (_instrument.text.trim().isEmpty || _direction == null) {
      snack(context, 'Choose the instrument and the direction.');
      return null;
    }
    for (final field in [
      (_entry, 'Entry price'),
      (_exit, 'Exit price'),
      (_stop, 'Original stop-loss price'),
      (_target, 'Original take-profit price'),
      (_size, 'Position volume'),
    ]) {
      if (field.$1.text.trim().isNotEmpty &&
          parseDouble(field.$1.text) == null) {
        snack(context, '${field.$2} must be a valid finite number.');
        return null;
      }
    }
    for (final field in [
      (_risk, 'Initial monetary risk'),
      (_gross, 'Gross P/L'),
      (_costs, 'Trading costs'),
    ]) {
      if (field.$1.text.trim().isNotEmpty &&
          parseMinor(field.$1.text, fractionDigits: _moneyFractionDigits) ==
              null) {
        snack(
          context,
          '${field.$2} must be a valid amount with at most $_moneyFractionDigits decimal places.',
        );
        return null;
      }
    }
    final values = <String, Object?>{
      'case_id': _caseId,
      'account_type': _account,
      'instrument': _instrument.text.trim().toUpperCase(),
      'direction': _direction,
      'currency_code': _currencyCode,
      'size_unit': _sizeUnit,
      'opened_at': _openedAt?.toUtc().toIso8601String(),
      'closed_at': _closedAt?.toUtc().toIso8601String(),
      'entry_price': parseDouble(_entry.text),
      'exit_price': parseDouble(_exit.text),
      'stop_price': parseDouble(_stop.text),
      'target_price': parseDouble(_target.text),
      'size': parseDouble(_size.text),
      'initial_risk_minor': _riskMinor,
      'gross_pnl_minor': _grossMinor,
      'costs_minor': _costsMinor,
      'setup_rationale': emptyToNull(_rationale.text),
      'rule_adherence': _adherence,
      'rule_notes': emptyToNull(_ruleNotes.text),
      'process_notes': emptyToNull(_process.text),
      'review_text': emptyToNull(_review.text),
      'status': _status,
    };
    final validationError = validateTradeValues(
      values,
      allowMissingCurrency: _legacyCurrencyMissing,
      allowMissingSizeUnit: _legacySizeUnitMissing,
    );
    if (validationError != null) {
      snack(context, validationError);
      return null;
    }
    _id =
        await ref.read(tradesRepositoryProvider).save(id: _id, values: values);
    return _id;
  }

  Future<void> _save({required bool stay}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final id = await _persist();
      if (id != null && mounted) {
        if (stay) {
          snack(context, 'Saved. You can add screenshots now.');
        } else {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) snack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete this trade record?',
      message: 'This removes it from your journal.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || _id == null) return;
    await ref.read(tradesRepositoryProvider).delete(_id!);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickCase() async {
    final cases = await ref
        .read(researchRepositoryProvider)
        .listCases(const CaseFilter());
    if (!mounted) return;
    final chosen = await pickRec(
      context,
      title: 'Link a research case',
      items: cases,
      label: (c) => c.s('title', 'Untitled'),
      subtitle: (c) => [c.sn('instrument'), c.sn('timeframe')]
          .whereType<String>()
          .join(' | '),
    );
    if (chosen == null) return;
    setState(() {
      _caseId = chosen.s('id');
      _caseTitle = chosen.sn('title');
      if (_instrument.text.trim().isEmpty) {
        _instrument.text = chosen.s('instrument');
      }
    });
  }

  Future<void> _addScreenshots() async {
    if (_id == null) {
      String? id;
      try {
        id = await _persist();
      } catch (e) {
        if (mounted) snack(context, friendlyError(e));
      }
      if (id == null) return;
    }
    if (!mounted) return;
    await pickAndImport(context, ref, tradeId: _id, caseId: _caseId);
  }

  String _dateText(DateTime? d) =>
      d == null ? '' : formatLocalDateTime(d.toUtc().toIso8601String());

  @override
  Widget build(BuildContext context) {
    final gross = _grossMinor;
    final costs = _costsMinor;
    final net = _status != 'closed' || gross == null || costs == null
        ? null
        : gross - costs;
    final risk = _riskMinor;
    final r = (net != null && risk != null && risk > 0) ? (net / risk) : null;
    final images = _id == null
        ? const <Rec>[]
        : (ref.watch(tradeImagesProvider(_id!)).valueOrNull ?? const <Rec>[]);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tradeId == null ? 'New trade' : 'Trade'),
        actions: [
          if (_id != null)
            IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionCard(
                  title: 'Trade',
                  children: [
                    ChoiceRow(
                      label: 'Account',
                      options: accountTypes,
                      value: _account,
                      allowClear: false,
                      onChanged: (v) =>
                          setState(() => _account = v ?? _account),
                    ),
                    SuggestField(
                      controller: _instrument,
                      label: 'Instrument',
                      suggestions: kInstrumentSuggestions,
                    ),
                    ChoiceRow(
                      label: 'Direction',
                      options: tradeDirections,
                      value: _direction,
                      onChanged: (v) => setState(() => _direction = v),
                    ),
                    ChoiceRow(
                      label: 'Status',
                      options: const ['open', 'closed'],
                      value: _status,
                      allowClear: false,
                      onChanged: (v) => setState(() => _status = v ?? _status),
                    ),
                    TextField(
                      controller: _currency,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 3,
                      onChanged: (value) => setState(() {
                        final code = value.trim().toUpperCase();
                        _currencyCode = code.isEmpty ? null : code;
                      }),
                      decoration: const InputDecoration(
                        labelText: 'Account currency code',
                        helperText:
                            'Enter the account’s 3-letter code. Amount precision follows the currency; adjust amounts if needed.',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_legacyCurrencyMissing && _id != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 4, bottom: 8),
                        child: Text(
                            'Legacy trade: leave blank if its currency is unknown.'),
                      ),
                    const SizedBox(height: 12),
                    PickerField(
                      label: 'Opened',
                      text: _dateText(_openedAt),
                      onTap: () async {
                        final picked = await pickDateTime(
                            context, _openedAt ?? DateTime.now());
                        if (picked != null) setState(() => _openedAt = picked);
                      },
                    ),
                    PickerField(
                      label:
                          'Closed${_status == 'closed' ? '' : ' (only when closed)'}',
                      text: _dateText(_closedAt),
                      onTap: () async {
                        final picked = await pickDateTime(
                            context, _closedAt ?? DateTime.now());
                        if (picked != null) setState(() => _closedAt = picked);
                      },
                    ),
                  ],
                ),
                SectionCard(
                  title: 'Prices and size',
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: LabeledField(
                            controller: _entry,
                            label: 'Entry Price',
                            hint: 'Executed entry',
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: LabeledField(
                            controller: _exit,
                            label: 'Exit Price',
                            hint: 'Executed exit',
                            helperText: _status == 'closed'
                                ? 'Required for a closed trade.'
                                : 'Leave blank while open.',
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: LabeledField(
                            controller: _stop,
                            label: 'Original Stop-Loss Price',
                            helperText:
                                'Record the initial level; do not replace it with later adjustments.',
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: LabeledField(
                            controller: _target,
                            label: 'Original Take-Profit Price',
                            helperText:
                                'Record the initial target; do not replace it with later adjustments.',
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                          ),
                        ),
                      ],
                    ),
                    LabeledField(
                      controller: _size,
                      label: 'Position Volume',
                      helperText:
                          'Actual traded volume; choose its unit below.',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                    ChoiceRow(
                      label: 'Volume Unit',
                      options: tradeVolumeUnits,
                      value: _sizeUnit,
                      onChanged: (v) => setState(() => _sizeUnit = v),
                    ),
                    if (_legacySizeUnitMissing && _id != null)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                            'Legacy trade: leave blank if its original volume unit is unknown.'),
                      ),
                  ],
                ),
                SectionCard(
                  title:
                      'Risk and result (${_currencyCode ?? 'select account currency'})',
                  children: [
                    LabeledField(
                      controller: _risk,
                      label: 'Initial Monetary Risk',
                      helperText:
                          'Planned loss at the original stop, in the selected account currency.',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: LabeledField(
                            controller: _gross,
                            label: 'Gross P/L',
                            helperText:
                                'Realised profit or loss before trading costs.',
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: LabeledField(
                            controller: _costs,
                            label: 'Trading Costs',
                            helperText:
                                'Commissions, swaps, and charges; enter positive amounts, or 0 if none.',
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    Text(
                        'Net P/L: ${net == null ? '-' : formatTradeMoney(_currencyCode, net)}'
                        '${r == null ? '' : '   Net R: ${r.toStringAsFixed(2)}'}'),
                  ],
                ),
                SectionCard(
                  title: 'Setup and review',
                  children: [
                    LabeledField(
                        controller: _rationale,
                        label: 'Setup rationale',
                        minLines: 2,
                        maxLines: 8),
                    ChoiceRow(
                      label: 'Did you follow your rules?',
                      options: ruleAdherenceOptions,
                      value: _adherence,
                      onChanged: (v) => setState(() => _adherence = v),
                    ),
                    LabeledField(
                        controller: _ruleNotes,
                        label: 'Rule notes',
                        minLines: 1,
                        maxLines: 6),
                    LabeledField(
                        controller: _process,
                        label: 'Emotions and process observations',
                        minLines: 2,
                        maxLines: 8),
                    LabeledField(
                        controller: _review,
                        label: 'Post-trade review',
                        minLines: 2,
                        maxLines: 8),
                  ],
                ),
                SectionCard(
                  title: 'Research case',
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: Text(_caseTitle ??
                                'Not linked (a trade does not need a case)')),
                        if (_caseId != null)
                          IconButton(
                            tooltip: 'Open case',
                            icon: const Icon(Icons.open_in_new),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                  builder: (_) =>
                                      CaseDetailScreen(caseId: _caseId!)),
                            ),
                          ),
                        if (_caseId != null)
                          IconButton(
                            tooltip: 'Unlink',
                            icon: const Icon(Icons.link_off),
                            onPressed: () => setState(() {
                              _caseId = null;
                              _caseTitle = null;
                            }),
                          ),
                      ],
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickCase,
                      icon: const Icon(Icons.link),
                      label: const Text('Link a case'),
                    ),
                  ],
                ),
                SectionCard(
                  title: 'Screenshots',
                  trailing: TextButton.icon(
                    onPressed: _addScreenshots,
                    icon: const Icon(Icons.add_photo_alternate_outlined,
                        size: 18),
                    label: const Text('Add'),
                  ),
                  children: [
                    if (images.isEmpty)
                      const Text(
                          'No screenshots yet. Adding one saves the trade first.')
                    else
                      SizedBox(
                        height: 92,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: images.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) => ImageThumb(
                            image: images[i],
                            size: 92,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => ImageViewerScreen(
                                  imageIds:
                                      images.map((x) => x.s('id')).toList(),
                                  initialIndex: i,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => _save(stay: true),
                        child: const Text('Save and stay'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : () => _save(stay: false),
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
