import '../../core/db/table_changes.dart';
import '../../core/rows.dart';
import 'base_repository.dart';

class TradeFilter {
  const TradeFilter({this.account, this.instrument});

  /// 'demo', 'live' or null for both.
  final String? account;
  final String? instrument;

  @override
  bool operator ==(Object other) =>
      other is TradeFilter && other.account == account && other.instrument == instrument;

  @override
  int get hashCode => Object.hash(account, instrument);
}

const accountTypes = ['demo', 'live'];
const tradeDirections = ['long', 'short'];
const ruleAdherenceOptions = ['followed', 'partial', 'broken'];

/// Net result in minor units: gross minus costs. Computed, never stored,
/// so it can never disagree with its parts.
int? netMinor(Rec trade) {
  final gross = trade.iN('gross_pnl_minor');
  if (gross == null) return null;
  return gross - trade.i('costs_minor');
}

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

  Future<String> save({String? id, required Map<String, Object?> values}) =>
      write(['trades'], (txn, now) async {
        if (id == null) {
          return insertIn(txn, 'trades', values, now);
        }
        await updateIn(txn, 'trades', id, values, now);
        return id;
      });

  Future<void> delete(String id) =>
      write(['trades'], (txn, now) => softDeleteIn(txn, 'trades', id, now));

  /// One row per account type (demo and live are always reported separately).
  Future<List<Rec>> summary() => rawQuery(
        'SELECT account_type, COUNT(*) AS trade_count, '
        "SUM(CASE WHEN status = 'closed' THEN 1 ELSE 0 END) AS closed_count, "
        "COALESCE(SUM(CASE WHEN status = 'closed' THEN COALESCE(gross_pnl_minor, 0) - COALESCE(costs_minor, 0) ELSE 0 END), 0) AS net_minor "
        'FROM trades WHERE deleted_at IS NULL GROUP BY account_type',
      );

  Stream<List<Rec>> watchSummary() => watchQuery(changes, {'trades'}, summary);
}
