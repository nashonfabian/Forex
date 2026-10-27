import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';
import '../../core/db/app_database.dart';
import '../../core/db/table_changes.dart';
import '../../core/ids.dart';
import '../../core/rows.dart';
import '../sync/outbox.dart';

/// Insert a row and queue it for the cloud, inside the caller's transaction.
Future<String> insertIn(
  Transaction txn,
  String table,
  Map<String, Object?> values,
  String now, {
  String? id,
}) async {
  final rowId = id ?? newId();
  await txn.insert(table, {...values, 'id': rowId, 'created_at': now, 'updated_at': now});
  await Outbox.enqueue(txn, table, rowId, nowIso: now);
  return rowId;
}

Future<void> updateIn(
  Transaction txn,
  String table,
  String id,
  Map<String, Object?> values,
  String now,
) async {
  await txn.update(table, {...values, 'updated_at': now}, where: 'id = ?', whereArgs: [id]);
  await Outbox.enqueue(txn, table, id, nowIso: now);
}

/// Soft delete: the row stays as a tombstone so the deletion can sync.
Future<void> softDeleteIn(Transaction txn, String table, String id, String now) =>
    updateIn(txn, table, id, {'deleted_at': now}, now);

class BaseRepository {
  BaseRepository(this.app, this.changes, this.clock);

  final AppDatabase app;
  final TableChanges changes;
  final Clock clock;

  Future<Database> get db => app.db;

  /// Runs [action] in one transaction, then tells watchers which [tables] changed.
  Future<T> write<T>(
    Iterable<String> tables,
    Future<T> Function(Transaction txn, String now) action,
  ) async {
    final database = await app.db;
    final now = clock.nowIso();
    final result = await database.transaction((txn) => action(txn, now));
    changes.notify(tables);
    return result;
  }

  Future<Rec?> getById(String table, String id) async {
    final rows = await (await db).query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Rec>> rawQuery(String sql, [List<Object?>? args]) async =>
      (await db).rawQuery(sql, args);
}
