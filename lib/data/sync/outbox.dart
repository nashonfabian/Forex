import 'package:sqflite/sqflite.dart';

/// The outbox: every local write queues the changed record for the cloud in
/// the SAME transaction, so a record can never be saved without being queued.
///
/// The queue stores a reference, not a payload: at send time the sync service
/// reads the record's current state, so the latest edit always wins and
/// repeated edits merge into one pending entry.
class Outbox {
  const Outbox._();

  /// op: 'upsert' (row insert/update/soft-delete), 'blob_upload', 'blob_delete'.
  static Future<void> enqueue(
    DatabaseExecutor db,
    String entityType,
    String entityId, {
    required String nowIso,
    String op = 'upsert',
  }) async {
    // Two plain statements instead of UPSERT syntax: old Android versions
    // ship a SQLite that predates ON CONFLICT ... DO UPDATE.
    await db.rawInsert(
      'INSERT OR IGNORE INTO sync_queue '
      '(entity_type, entity_id, op, status, attempts, created_at, updated_at) '
      "VALUES (?, ?, ?, 'pending', 0, ?, ?)",
      [entityType, entityId, op, nowIso, nowIso],
    );
    await db.rawUpdate(
      "UPDATE sync_queue SET status = 'pending', attempts = 0, "
      'next_attempt_at = NULL, last_error = NULL, updated_at = ? '
      'WHERE entity_type = ? AND entity_id = ? AND op = ?',
      [nowIso, entityType, entityId, op],
    );
  }
}
