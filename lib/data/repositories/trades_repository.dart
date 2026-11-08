import '../../core/db/table_changes.dart';
import '../../core/format.dart';
import '../../core/rows.dart';
import 'base_repository.dart';

class TradeFilter {
  const TradeFilter({this.account, this.instrument});

  /// 'demo', 'live' or null for both.
  final String? account;
  final String? instrument;

  @override
  bool operator ==(Object other) =>
      other is TradeFilter &&
      other.account == account &&
      other.instrument == instrument;

  @override
  int get hashCode => Object.hash(account, instrument);
}

const accountTypes = ['demo', 'live'];
const tradeDirections = ['long', 'short'];
const ruleAdherenceOptions = ['followed', 'partial', 'broken'];
const tradeVolumeUnits = ['lots', 'contracts', 'units'];

String? validateTradeValues(
  Map<String, Object?> values, {
  bool allowMissingCurrency = false,
  bool allowMissingSizeUnit = false,
}) {
  final status = values['status'];
  if (status != 'open' && status != 'closed') {
    return 'Choose whether the trade is open or closed.';
  }
  if (values['account_type'] != 'demo' && values['account_type'] != 'live') {
    return 'Choose a valid account type.';
  }
  if (values['direction'] != 'long' && values['direction'] != 'short') {
    return 'Choose the trade direction.';
  }
  final instrument = values['instrument'];
  if (instrument is! String || instrument.trim().isEmpty) {
    return 'Enter the instrument.';
  }
  final currency = values['currency_code'];
  if ((!allowMissingCurrency || currency != null) &&
      (currency is! String || !RegExp(r'^[A-Z]{3}$').hasMatch(currency))) {
    return 'Select the account currency.';
  }
  if ((!allowMissingSizeUnit || values['size_unit'] != null) &&
      !tradeVolumeUnits.contains(values['size_unit'])) {
    return 'Select the position volume unit.';
  }

  bool positiveNumber(String key, {bool required = false}) {
    final value = values[key];
    if (value == null) return !required;
    return value is num && value.isFinite && value > 0;
  }

  if (!positiveNumber('entry_price', required: true)) {
    return 'Enter a valid actual entry price greater than zero.';
  }
  if (!positiveNumber('exit_price', required: status == 'closed')) {
    return 'A closed trade needs a valid actual exit price greater than zero.';
  }
  if (!positiveNumber('stop_price')) {
    return 'Original stop-loss price must be greater than zero.';
  }
  if (!positiveNumber('target_price')) {
    return 'Original take-profit price must be greater than zero.';
  }
  if (!positiveNumber('size', required: true)) {
    return 'Enter a valid position volume greater than zero.';
  }

  final risk = values['initial_risk_minor'];
  if (risk != null && (risk is! int || risk < 0)) {
    return 'Initial monetary risk cannot be negative.';
  }
  final costs = values['costs_minor'];
  if (costs is! int || costs < 0) {
    return 'Trading costs must be zero or a positive amount.';
  }
  final gross = values['gross_pnl_minor'];
  if (gross != null && gross is! int) return 'Enter a valid gross P/L amount.';

  final openedAt = values['opened_at'];
  if (openedAt is! String || DateTime.tryParse(openedAt) == null) {
    return 'Enter the trade opening date and time.';
  }
  if (status == 'closed') {
    final closedAt = values['closed_at'];
    final closed = closedAt is String ? DateTime.tryParse(closedAt) : null;
    if (closed == null) return 'A closed trade needs a closing date and time.';
    if (closed.isBefore(DateTime.parse(openedAt))) {
      return 'Closing date and time cannot be before opening.';
    }
    if (gross == null) {
      return 'A closed trade needs an explicitly recorded gross P/L.';
    }
  }
  return null;
}

/// Net result in minor units: gross minus costs. Computed, never stored,
/// so it can never disagree with its parts.
int? netMinor(Rec trade) {
  if (trade.s('status', 'open') != 'closed' ||
      trade.sn('closed_at') == null ||
      (trade.d('entry_price') ?? 0) <= 0 ||
      (trade.d('exit_price') ?? 0) <= 0 ||
      (trade.d('size') ?? 0) <= 0 ||
      trade.i('costs_minor', -1) < 0) {
    return null;
  }
  final gross = trade.iN('gross_pnl_minor');
  if (gross == null) return null;
  return gross - trade.i('costs_minor');
}

String formatTradeMoney(String? currencyCode, int? minor) =>
    '${currencyCode ?? 'Unknown currency'} '
    '${formatMinor(minor, fractionDigits: currencyFractionDigits(currencyCode))}';

class TradesRepository extends BaseRepository {
  TradesRepository(super.app, super.changes, super.clock);

  Future<List<Rec>> list(TradeFilter f, {int limit = 300}) async {
    final where = <String>['t.deleted_at IS NULL'];
    final args = <Object?>[];
    if (f.account != null) {
      where.add('t.account_type = ?');
      args.add(f.account);
    }
    if (f.instrument != null) {
      where.add('t.instrument = ?');
      args.add(f.instrument);
    }
    return rawQuery(
      'SELECT t.*, (SELECT c.title FROM research_cases c WHERE c.id = t.case_id) AS case_title '
      'FROM trades t WHERE ${where.join(' AND ')} '
      'ORDER BY COALESCE(t.opened_at, t.created_at) DESC LIMIT $limit',
      args,
    );
  }

  Stream<List<Rec>> watch(TradeFilter f) =>
      watchQuery(changes, {'trades', 'research_cases'}, () => list(f));

  Future<Rec?> byId(String id) => getById('trades', id);

  Future<String> save(
      {String? id, required Map<String, Object?> values}) async {
    final existing = id == null ? null : await byId(id);
    final error = validateTradeValues(
      values,
      allowMissingCurrency:
          existing != null && existing.sn('currency_code') == null,
      allowMissingSizeUnit:
          existing != null && existing.sn('size_unit') == null,
    );
    if (error != null) throw StateError(error);
    return write(['trades'], (txn, now) async {
      if (id == null) {
        return insertIn(txn, 'trades', values, now);
      }
      await updateIn(txn, 'trades', id, values, now);
      return id;
    });
  }

  Future<void> delete(String id) =>
      write(['trades'], (txn, now) => softDeleteIn(txn, 'trades', id, now));

  /// Results are grouped by account type and recorded currency; unknown legacy
  /// currencies remain separate rather than being combined with known amounts.
  Future<List<Rec>> summary() => rawQuery(
        'SELECT account_type, currency_code, COUNT(*) AS trade_count, '
        "SUM(CASE WHEN status = 'closed' AND closed_at IS NOT NULL AND "
        'entry_price > 0 AND exit_price > 0 AND size > 0 AND costs_minor >= 0 AND gross_pnl_minor IS NOT NULL '
        'THEN 1 ELSE 0 END) AS closed_count, '
        "CASE WHEN currency_code IS NULL THEN NULL ELSE COALESCE(SUM(CASE WHEN status = 'closed' AND closed_at IS NOT NULL AND "
        'entry_price > 0 AND exit_price > 0 AND size > 0 AND costs_minor >= 0 AND gross_pnl_minor IS NOT NULL '
        'THEN gross_pnl_minor - costs_minor ELSE 0 END), 0) END AS net_minor '
        'FROM trades WHERE deleted_at IS NULL GROUP BY account_type, currency_code '
        'ORDER BY account_type, currency_code',
      );

  Stream<List<Rec>> watchSummary() => watchQuery(changes, {'trades'}, summary);
}
