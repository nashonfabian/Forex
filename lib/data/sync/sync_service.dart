import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../core/clock.dart';
import '../../core/db/app_database.dart';
import '../../core/db/table_changes.dart';
import '../../core/rows.dart';
import '../images/image_store.dart';
import 'outbox.dart';

enum SyncPhase { localOnly, offline, syncing, pending, synced, attention }

class SyncState {
  const SyncState({
    required this.phase,
    this.pending = 0,
    this.failed = 0,
    this.message = '',
    this.lastSuccessIso,
  });

  final SyncPhase phase;
  final int pending;
  final int failed;
  final String message;
  final String? lastSuccessIso;

  String get label {
    switch (phase) {
      case SyncPhase.localOnly:
        return 'Local only';
      case SyncPhase.offline:
        return 'Offline';
      case SyncPhase.syncing:
        return 'Syncing...';
      case SyncPhase.pending:
        return 'Waiting ($pending)';
      case SyncPhase.synced:
        return 'Synced';
      case SyncPhase.attention:
        return 'Needs attention';
    }
  }
}

enum _Step { ok, offline, auth }

enum _Kind { network, auth, retryable, permanent }

/// Pushes local changes to Supabase and pulls remote changes, safely:
///  * local database first - nothing here is needed for the app to work;
///  * the outbox (sync_queue) is the only thing that decides what is sent;
///  * uploads are idempotent (client UUIDs + upsert), so retries never duplicate;
///  * a failed request is never treated as a success;
///  * online status is judged by real request results, not by "was online before".
class SyncService with WidgetsBindingObserver {
  SyncService(this._app, this._changes, this._clock, this._images);

  final AppDatabase _app;
  final TableChanges _changes;
  final Clock _clock;
  final ImageStore _images;

  static const bucket = 'case-images';

  /// Dependency order: a parent is always pushed and pulled before its children.
  static const syncTables = <String>[
    'study_plans',
    'lessons',
    'daily_tasks',
    'notes',
    'study_sessions',
    'research_cases',
    'trades',
    'images',
    'case_entries',
    'reviews',
    'tags',
    'entity_tags',
    'links',
  ];

  final StreamController<SyncState> _controller = StreamController<SyncState>.broadcast();
  SyncState _state = const SyncState(
    phase: SyncPhase.localOnly,
    message: 'Cloud sync is not set up yet.',
  );
  SyncState get state => _state;
  Stream<SyncState> get stream => _controller.stream;

  StreamSubscription<TableChange>? _changeSub;
  StreamSubscription<AuthState>? _authSub;
  Timer? _debounce;
  Timer? _periodic;
  bool _started = false;
  bool _running = false;
  bool _again = false;
  bool _forcePull = false;
  DateTime? _lastPull;
  final Set<String> _skipDownloads = {};

  // ------------------------------------------------------------ account
  SupabaseClient? get _client {
    if (!SupabaseConfig.isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  bool get isConfigured => _client != null;
  bool get isSignedIn => _client?.auth.currentUser != null;
  String? get userEmail => _client?.auth.currentUser?.email;

  /// Returns an error message, or null on success.
  Future<String?> signIn(String email, String password) async {
    final client = _client;
    if (client == null) return 'Cloud sync is not set up yet.';
    try {
      await client.auth.signInWithPassword(email: email.trim(), password: password);
      return null;
    } on AuthRetryableFetchException {
      return 'No internet connection.';
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'No internet connection.';
    }
  }

  /// Returns a message to show, or null if the account was created and signed in.
  Future<String?> signUp(String email, String password) async {
    final client = _client;
    if (client == null) return 'Cloud sync is not set up yet.';
    try {
      final res = await client.auth.signUp(email: email.trim(), password: password);
      if (res.session == null) {
        return 'Account created. Confirm it from the email Supabase sent, then sign in.';
      }
      return null;
    } on AuthRetryableFetchException {
      return 'No internet connection.';
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'No internet connection.';
    }
  }

  Future<void> signOut() async {
    try {
      await _client?.auth.signOut();
    } catch (_) {}
    _emit(const SyncState(
      phase: SyncPhase.localOnly,
      message: 'Signed out. Your data stays on this phone.',
    ));
  }

  // ------------------------------------------------------------ lifecycle
  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (!SupabaseConfig.isConfigured) {
      _emit(const SyncState(
        phase: SyncPhase.localOnly,
        message: 'Cloud sync is not set up. Add your Supabase details in lib/config/supabase_config.dart.',
      ));
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _changeSub = _changes.stream.where((c) => !c.fromSync).listen((_) => requestSync());
    final client = _client;
    if (client != null) {
      _authSub = client.auth.onAuthStateChange.listen((_) {
        requestSync(pull: true, immediate: true);
      });
    }
    _periodic = Timer.periodic(const Duration(seconds: 60), (_) => requestSync());
    requestSync(pull: true, immediate: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      requestSync(pull: true, immediate: true);
    }
  }

  Future<void> dispose() async {
    _debounce?.cancel();
    _periodic?.cancel();
    await _changeSub?.cancel();
    await _authSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    await _controller.close();
  }

  void requestSync({bool pull = false, bool immediate = false}) {
    if (!_started) return;
    if (pull) _forcePull = true;
    _debounce?.cancel();
    _debounce = Timer(
      immediate ? Duration.zero : const Duration(seconds: 2),
      () => unawaited(syncNow()),
    );
  }

  Future<void> syncNow() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _pass();
      } while (_again);
    } finally {
      _running = false;
    }
  }

  void _emit(SyncState s) {
    _state = s;
    if (!_controller.isClosed) _controller.add(s);
  }

  // ------------------------------------------------------------ one pass
  Future<void> _pass() async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      _emit(SyncState(
        phase: SyncPhase.localOnly,
        pending: await _count('pending'),
        message: client == null
            ? 'Cloud sync is not set up yet.'
            : 'Sign in to back up and sync your data.',
      ));
      return;
    }

    _emit(SyncState(
      phase: SyncPhase.syncing,
      pending: _state.pending,
      failed: _state.failed,
      lastSuccessIso: _state.lastSuccessIso,
    ));

    var step = _Step.ok;
    String? problem;
    try {
      await _adoptLocalRows(user.id);
      step = await _push(client, user.id);
      final pullDue = _forcePull ||
          _lastPull == null ||
          DateTime.now().difference(_lastPull!) > const Duration(minutes: 5);
      if (step == _Step.ok && pullDue) {
        step = await _pull(client);
        if (step == _Step.ok) {
          _forcePull = false;
          _lastPull = DateTime.now();
        }
      }
      if (step == _Step.ok) step = await _downloadMissingImages(client);
    } catch (e) {
      final kind = _classify(e);
      if (kind == _Kind.network) {
        step = _Step.offline;
      } else if (kind == _Kind.auth) {
        step = _Step.auth;
      } else {
        problem = _short(e);
      }
    }
    await _publishResult(step, problem);
  }

  Future<void> _publishResult(_Step step, String? problem) async {
    final pending = await _count('pending');
    final failed = await _count('failed');
    final last = _state.lastSuccessIso ?? await _getMeta('last_sync_at');

    if (step == _Step.auth) {
      _emit(SyncState(
        phase: SyncPhase.attention,
        pending: pending,
        failed: failed,
        lastSuccessIso: last,
        message: 'Please sign in again to continue syncing.',
      ));
    } else if (step == _Step.offline) {
      _emit(SyncState(
        phase: SyncPhase.offline,
        pending: pending,
        failed: failed,
        lastSuccessIso: last,
        message: 'No connection. Your work is saved on this phone and will sync later.',
      ));
    } else if (problem != null) {
      _emit(SyncState(
        phase: SyncPhase.attention,
        pending: pending,
        failed: failed,
        lastSuccessIso: last,
        message: problem,
      ));
    } else if (failed > 0) {
      _emit(SyncState(
        phase: SyncPhase.attention,
        pending: pending,
        failed: failed,
        lastSuccessIso: last,
        message: '$failed item(s) could not be synced. Open Sync status for details.',
      ));
    } else if (pending > 0) {
      _emit(SyncState(
        phase: SyncPhase.pending,
        pending: pending,
        lastSuccessIso: last,
        message: '$pending change(s) waiting to be sent.',
      ));
    } else {
      final now = _clock.nowIso();
      await _setMeta('last_sync_at', now);
      _emit(SyncState(
        phase: SyncPhase.synced,
        lastSuccessIso: now,
        message: 'Everything is backed up.',
      ));
    }
  }

  // ------------------------------------------------------------ adopt existing data
  /// The first time an account signs in, everything already on the phone is queued.
  Future<void> _adoptLocalRows(String uid) async {
    if (await _getMeta('adopted_uid') == uid) return;
    final database = await _app.db;
    final now = _clock.nowIso();
    await database.transaction((txn) async {
      for (final t in syncTables) {
        await txn.rawInsert(
          "INSERT OR IGNORE INTO sync_queue (entity_type, entity_id, op, status, attempts, created_at, updated_at) "
          "SELECT ?, id, 'upsert', 'pending', 0, ?, ? FROM $t WHERE owner_id IS NULL",
          [t, now, now],
        );
        await txn.rawUpdate('UPDATE $t SET owner_id = ? WHERE owner_id IS NULL', [uid]);
      }
      await txn.rawInsert(
        "INSERT OR IGNORE INTO sync_queue (entity_type, entity_id, op, status, attempts, created_at, updated_at) "
        "SELECT 'images', image_id, 'blob_upload', 'pending', 0, ?, ? FROM image_files WHERE upload_state != 'uploaded'",
        [now, now],
      );
      await txn.insert(
        'app_meta',
        {'key': 'adopted_uid', 'value': uid},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  // ------------------------------------------------------------ push
  Future<_Step> _push(SupabaseClient client, String uid) async {
    final database = await _app.db;
    final nowIso = _clock.nowIso();

    final blobs = await database.query(
      'sync_queue',
      where: "op = 'blob_upload' AND status = 'pending' AND (next_attempt_at IS NULL OR next_attempt_at <= ?)",
      whereArgs: [nowIso],
      orderBy: 'id ASC',
      limit: 25,
    );
    for (final q in blobs) {
      final step = await _uploadBlob(client, uid, q);
      if (step != _Step.ok) return step;
    }

    for (final table in syncTables) {
      final due = await database.query(
        'sync_queue',
        where: "entity_type = ? AND op = 'upsert' AND status = 'pending' AND (next_attempt_at IS NULL OR next_attempt_at <= ?)",
        whereArgs: [table, nowIso],
        orderBy: 'id ASC',
        limit: 400,
      );
      if (due.length == 400) _again = true;
      for (var i = 0; i < due.length; i += 50) {
        final end = i + 50 > due.length ? due.length : i + 50;
        final step = await _pushBatch(client, uid, table, due.sublist(i, end));
        if (step != _Step.ok) return step;
      }
    }
    return _Step.ok;
  }

  Map<String, Object?> _payload(Rec row, String uid) {
    final m = Map<String, Object?>.from(row);
    m.remove('server_updated_at'); // the server sets this itself
    m['owner_id'] = uid;
    return m;
  }

  Future<_Step> _pushBatch(
    SupabaseClient client,
    String uid,
    String table,
    List<Rec> queueRows,
  ) async {
    final database = await _app.db;
    final ids = queueRows.map((q) => q.s('entity_id')).toList();
    final marks = List.filled(ids.length, '?').join(',');
    final rows = await database.rawQuery('SELECT * FROM $table WHERE id IN ($marks)', ids);
    final byId = <String, Rec>{for (final r in rows) r.s('id'): r};

    final sendRows = <Rec>[];
    final sendQueue = <Rec>[];
    for (final q in queueRows) {
      final row = byId[q.s('entity_id')];
      if (row == null) {
        await _dropQueue(q);
        continue;
      }
      // A screenshot's details wait until its file has been uploaded.
      if (table == 'images' && row.sn('deleted_at') == null && row.sn('storage_path') == null) {
        await _defer(q, 30);
        continue;
      }
      sendRows.add(row);
      sendQueue.add(q);
    }
    if (sendRows.isEmpty) return _Step.ok;

    try {
      await client.from(table).upsert(sendRows.map((r) => _payload(r, uid)).toList(), onConflict: 'id');
    } catch (e) {
      final kind = _classify(e);
      if (kind == _Kind.network) return _Step.offline;
      if (kind == _Kind.auth) return _Step.auth;
      if (sendRows.length == 1) {
        await _failQueue(sendQueue.first, e);
        return _Step.ok;
      }
      return _pushEach(client, uid, table, sendRows, sendQueue);
    }
    await _acknowledge(client, table, sendRows, sendQueue);
    return _Step.ok;
  }

  /// One bad row must not block the others: retry the batch row by row.
  Future<_Step> _pushEach(
    SupabaseClient client,
    String uid,
    String table,
    List<Rec> rows,
    List<Rec> queue,
  ) async {
    for (var i = 0; i < rows.length; i++) {
      try {
        await client.from(table).upsert(_payload(rows[i], uid), onConflict: 'id');
      } catch (e) {
        final kind = _classify(e);
        if (kind == _Kind.network) return _Step.offline;
        if (kind == _Kind.auth) return _Step.auth;
        await _failQueue(queue[i], e);
        continue;
      }
      await _acknowledge(client, table, [rows[i]], [queue[i]]);
    }
    return _Step.ok;
  }

  /// Clears queue entries that were sent - but only if the record has not been
  /// edited again since (an edit refreshes the queue entry's updated_at).
  Future<void> _acknowledge(
    SupabaseClient client,
    String table,
    List<Rec> rows,
    List<Rec> queue,
  ) async {
    final database = await _app.db;
    await database.transaction((txn) async {
      for (final q in queue) {
        await txn.delete(
          'sync_queue',
          where: 'id = ? AND updated_at = ?',
          whereArgs: [q['id'], q['updated_at']],
        );
      }
    });
    if (table == 'images') {
      for (final r in rows) {
        if (r.sn('deleted_at') != null) {
          final path = r.sn('storage_path');
          if (path != null) {
            try {
              await client.storage.from(bucket).remove([path]);
            } catch (_) {}
          }
          await _images.removeLocal(r.s('id'));
        }
      }
    }
  }

  Future<_Step> _uploadBlob(SupabaseClient client, String uid, Rec q) async {
    final database = await _app.db;
    final imageId = q.s('entity_id');
    final images = await database.query('images', where: 'id = ?', whereArgs: [imageId], limit: 1);
    final files = await database.query('image_files', where: 'image_id = ?', whereArgs: [imageId], limit: 1);
    if (images.isEmpty || files.isEmpty || images.first.sn('deleted_at') != null) {
      await _dropQueue(q);
      return _Step.ok;
    }
    final image = images.first;
    final file = File(_images.absolutePath(files.first.s('local_path')));
    if (!await file.exists()) {
      await _failQueue(q, StateError('The screenshot file is missing on this phone.'));
      return _Step.ok;
    }

    final ext = ImageStore.extensionOf(file.path);
    final path = '$uid/$imageId.$ext';
    try {
      final bytes = await file.readAsBytes();
      await client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: image.sn('mime') ?? ImageStore.mimeFor(ext),
            ),
          );
    } catch (e) {
      final kind = _classify(e);
      if (kind == _Kind.network) return _Step.offline;
      if (kind == _Kind.auth) return _Step.auth;
      await _failQueue(q, e);
      return _Step.ok;
    }

    final now = _clock.nowIso();
    await database.transaction((txn) async {
      await txn.update(
        'images',
        {'storage_path': path, 'uploaded_at': now, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [imageId],
      );
      await txn.update('image_files', {'upload_state': 'uploaded'},
          where: 'image_id = ?', whereArgs: [imageId]);
      await txn.delete('sync_queue',
          where: 'id = ? AND updated_at = ?', whereArgs: [q['id'], q['updated_at']]);
      await Outbox.enqueue(txn, 'images', imageId, nowIso: now);
    });
    _changes.notify(const ['images'], fromSync: true);
    return _Step.ok;
  }

  // ------------------------------------------------------------ pull
  Future<_Step> _pull(SupabaseClient client) async {
    final database = await _app.db;
    for (final table in syncTables) {
      final stored = await database.query('sync_state',
          where: 'table_name = ?', whereArgs: [table], limit: 1);
      String? cursorTs = stored.isEmpty ? null : stored.first['cursor_server_updated_at'] as String?;
      String? cursorId = stored.isEmpty ? null : stored.first['cursor_id'] as String?;

      while (true) {
        List<Map<String, dynamic>> rows;
        try {
          var query = client.from(table).select();
          if (cursorTs != null && cursorId != null) {
            query = query.or(
                'server_updated_at.gt.$cursorTs,and(server_updated_at.eq.$cursorTs,id.gt.$cursorId)');
          }
          rows = await query
              .order('server_updated_at', ascending: true)
              .order('id', ascending: true)
              .limit(500);
        } catch (e) {
          final kind = _classify(e);
          if (kind == _Kind.network) return _Step.offline;
          if (kind == _Kind.auth) return _Step.auth;
          rethrow;
        }
        if (rows.isEmpty) break;

        final applied = await _applyRows(table, rows);
        final last = rows.last;
        cursorTs = _normTs('${last['server_updated_at']}');
        cursorId = '${last['id']}';
        await database.insert(
          'sync_state',
          {
            'table_name': table,
            'cursor_server_updated_at': cursorTs,
            'cursor_id': cursorId,
            'last_pull_at': _clock.nowIso(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (applied > 0) _changes.notify([table], fromSync: true);
        if (rows.length < 500) break;
      }
    }
    return _Step.ok;
  }

  String _normTs(String s) {
    final d = DateTime.tryParse(s);
    return d == null ? s : d.toUtc().toIso8601String();
  }

  Future<int> _applyRows(String table, List<Map<String, dynamic>> rows) async {
    final database = await _app.db;
    final cols = (await database.rawQuery('PRAGMA table_info($table)'))
        .map((r) => r['name'] as String)
        .toSet();
    final removeFiles = <String>[];
    var applied = 0;

    await database.transaction((txn) async {
      for (final raw in rows) {
        final remote = <String, Object?>{};
        raw.forEach((key, value) {
          if (!cols.contains(key)) return;
          if (value is bool) {
            remote[key] = value ? 1 : 0;
          } else if (key == 'server_updated_at' && value is String) {
            remote[key] = _normTs(value);
          } else {
            remote[key] = value;
          }
        });
        final id = remote['id'];
        if (id is! String) continue;

        final localRows = await txn.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
        final pending = await txn.query(
          'sync_queue',
          where: "entity_type = ? AND entity_id = ? AND op = 'upsert'",
          whereArgs: [table, id],
          limit: 1,
        );

        if (localRows.isNotEmpty && pending.isNotEmpty) {
          // Both sides changed. The newer edit wins; the losing local version is kept in the conflict log.
          final remoteUpdated = (remote['updated_at'] as String?) ?? '';
          if (remoteUpdated.compareTo(localRows.first.s('updated_at')) <= 0) continue;
          await txn.insert('sync_conflicts', {
            'entity_type': table,
            'entity_id': id,
            'local_json': jsonEncode(localRows.first),
            'remote_json': jsonEncode(remote),
            'detected_at': _clock.nowIso(),
          });
          await txn.delete('sync_queue', where: 'id = ?', whereArgs: [pending.first['id']]);
        }

        try {
          if (localRows.isEmpty) {
            await txn.insert(table, remote);
          } else {
            final update = Map<String, Object?>.from(remote)..remove('id');
            await txn.update(table, update, where: 'id = ?', whereArgs: [id]);
          }
          applied++;
          if (table == 'images' && remote['deleted_at'] != null) removeFiles.add(id);
        } on DatabaseException catch (e) {
          if ('$e'.contains('hypothesis_locked')) {
            // A locked hypothesis is never overwritten, by either side.
            await txn.insert('sync_conflicts', {
              'entity_type': table,
              'entity_id': id,
              'local_json': jsonEncode(localRows.isEmpty ? null : localRows.first),
              'remote_json': jsonEncode(remote),
              'detected_at': _clock.nowIso(),
            });
            continue;
          }
          rethrow;
        }
      }
    });

    for (final id in removeFiles) {
      await _images.removeLocal(id);
    }
    return applied;
  }

  // ------------------------------------------------------------ screenshots from the cloud
  Future<_Step> _downloadMissingImages(SupabaseClient client) async {
    final database = await _app.db;
    final missing = await database.rawQuery(
      'SELECT i.id AS id, i.storage_path AS path FROM images i '
      'LEFT JOIN image_files f ON f.image_id = i.id '
      'WHERE i.deleted_at IS NULL AND i.storage_path IS NOT NULL AND f.image_id IS NULL LIMIT 12',
    );
    var downloaded = 0;
    for (final m in missing) {
      final id = m.s('id');
      if (_skipDownloads.contains(id)) continue;
      final step = await _downloadOne(client, id, m.s('path'));
      if (step != _Step.ok) return step;
      downloaded++;
    }
    if (downloaded > 0 && missing.length == 12) _again = true;
    return _Step.ok;
  }

  Future<_Step> _downloadOne(SupabaseClient client, String id, String path) async {
    try {
      final bytes = await client.storage.from(bucket).download(path);
      await _images.restoreFile(id, ImageStore.extensionOf(path), bytes);
      return _Step.ok;
    } catch (e) {
      final kind = _classify(e);
      if (kind == _Kind.network) return _Step.offline;
      if (kind == _Kind.auth) return _Step.auth;
      _skipDownloads.add(id);
      debugPrint('Screenshot download failed ($id): $e');
      return _Step.ok;
    }
  }

  /// Used when you tap a screenshot that has not been downloaded yet.
  Future<bool> downloadImageNow(String imageId) async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) return false;
    final rows = await (await _app.db)
        .query('images', columns: ['storage_path'], where: 'id = ?', whereArgs: [imageId], limit: 1);
    final path = rows.isEmpty ? null : rows.first.sn('storage_path');
    if (path == null) return false;
    _skipDownloads.remove(imageId);
    final step = await _downloadOne(client, imageId, path);
    return step == _Step.ok && await _images.localFile(imageId) != null;
  }

  // ------------------------------------------------------------ queue helpers
  Future<void> _dropQueue(Rec q) async {
    await (await _app.db).delete('sync_queue', where: 'id = ?', whereArgs: [q['id']]);
  }

  Future<void> _defer(Rec q, int seconds) async {
    await (await _app.db).update(
      'sync_queue',
      {'next_attempt_at': _clock.nowUtc().add(Duration(seconds: seconds)).toIso8601String()},
      where: 'id = ?',
      whereArgs: [q['id']],
    );
  }

  Future<void> _failQueue(Rec q, Object error) async {
    const backoff = [30, 120, 600, 3600, 21600];
    final attempts = q.i('attempts') + 1;
    final delay = backoff[(attempts - 1) < backoff.length ? attempts - 1 : backoff.length - 1];
    await (await _app.db).update(
      'sync_queue',
      {
        'attempts': attempts,
        'status': attempts >= 8 ? 'failed' : 'pending',
        'next_attempt_at': _clock.nowUtc().add(Duration(seconds: delay)).toIso8601String(),
        'last_error': _short(error),
      },
      where: 'id = ?',
      whereArgs: [q['id']],
    );
  }

  Future<int> _count(String status) async =>
      Sqflite.firstIntValue(await (await _app.db)
          .rawQuery('SELECT COUNT(*) FROM sync_queue WHERE status = ?', [status])) ??
      0;

  Future<String?> _getMeta(String key) async {
    final rows = await (await _app.db)
        .query('app_meta', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> _setMeta(String key, String value) async {
    await (await _app.db).insert(
      'app_meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ------------------------------------------------------------ for the Sync status screen
  Future<List<Rec>> failedItems() async => (await _app.db).query(
        'sync_queue',
        where: "status = 'failed'",
        orderBy: 'updated_at DESC',
        limit: 100,
      );

  Future<List<Rec>> conflicts() async => (await _app.db).query(
        'sync_conflicts',
        where: 'resolved = 0',
        orderBy: 'detected_at DESC',
        limit: 100,
      );

  Future<void> dismissConflict(int id) async {
    await (await _app.db)
        .update('sync_conflicts', {'resolved': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> retryFailed() async {
    await (await _app.db).update(
      'sync_queue',
      {'status': 'pending', 'attempts': 0, 'next_attempt_at': null, 'last_error': null},
      where: "status = 'failed'",
    );
    requestSync(pull: true, immediate: true);
  }

  // ------------------------------------------------------------ error handling
  _Kind _classify(Object e) {
    if (e is AuthRetryableFetchException) return _Kind.network;
    if (e is AuthException) return _Kind.auth;
    if (e is DatabaseException) return _Kind.permanent;
    if (e is PostgrestException) {
      final code = e.code ?? '';
      final message = e.message.toLowerCase();
      if (code == 'PGRST301' || code == '401' || message.contains('jwt')) return _Kind.auth;
      if (code == '23503' || code.startsWith('5')) return _Kind.retryable;
      return _Kind.permanent;
    }
    if (e is StorageException) {
      final status = int.tryParse(e.statusCode ?? '') ?? 0;
      if (status == 401) return _Kind.auth;
      if (status >= 500) return _Kind.retryable;
      return _Kind.permanent;
    }
    if (e is StateError || e is FormatException || e is FileSystemException) {
      return _Kind.permanent;
    }
    return _Kind.network; // socket errors, timeouts, DNS failures, ...
  }

  String _short(Object e) {
    var text = '$e';
    if (e is PostgrestException) text = '${e.message} (${e.code ?? 'no code'})';
    if (e is StorageException) text = e.message;
    if (e is AuthException) text = e.message;
    return text.length > 300 ? text.substring(0, 300) : text;
  }
}
