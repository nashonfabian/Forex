import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';
import '../../core/db/app_database.dart';
import '../../core/db/migration.dart';
import '../../core/db/migrations.dart';
import '../../core/db/migrations/migration_001.dart';
import '../../core/format.dart';
import '../../core/ids.dart';
import '../../data/sync/outbox.dart';

class CheckResult {
  const CheckResult(this.name, this.ok, [this.detail = '']);
  final String name;
  final bool ok;
  final String detail;
}

class _Rollback implements Exception {
  const _Rollback();
}

/// Runs the Sprint 1 acceptance checks on the real device, against the real
/// database engine. Every data-changing check happens inside a transaction
/// that is rolled back, so your data is never touched.
class Diagnostics {
  Diagnostics(this._app, this._clock);

  final AppDatabase _app;
  final Clock _clock;

  Future<List<CheckResult>> run() async {
    final results = <CheckResult>[];
    void add(String name, bool ok, [String detail = '']) =>
        results.add(CheckResult(name, ok, detail));

    try {
      final db = await _app.db;
      await _structureChecks(db, add);

      try {
        await db.transaction((txn) async {
          await _transactionChecks(txn, add);
          throw const _Rollback(); // undo everything the checks wrote
        });
      } on _Rollback {
        // expected
      } catch (e) {
        add('Rule checks', false, '$e');
      }

      await _upgradeTest(add);
    } catch (e) {
      add('Diagnostics', false, '$e');
    }
    return results;
  }

  Future<void> _structureChecks(
    Database db,
    void Function(String, bool, [String]) add,
  ) async {
    final expectedVersion = appMigrations.last.version;
    final version = Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version'));
    add('Schema version', version == expectedVersion,
        'v$version (expected v$expectedVersion)');

    final fk = Sqflite.firstIntValue(await db.rawQuery('PRAGMA foreign_keys'));
    add('Foreign keys switched on', fk == 1);

    final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name'] as String)
        .toSet();
    final missingTables = migration001TableNames.where((t) => !tables.contains(t)).toList();
    add('All tables exist', missingTables.isEmpty,
        missingTables.isEmpty ? '${migration001TableNames.length} tables' : 'missing: $missingTables');

    final triggers = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'trigger'"))
        .map((r) => r['name'] as String)
        .toSet();
    final missingTriggers =
        migration001TriggerNames.where((t) => !triggers.contains(t)).toList();
    add('Evidence-protection triggers exist', missingTriggers.isEmpty,
        missingTriggers.isEmpty ? '${migration001TriggerNames.length} triggers' : 'missing: $missingTriggers');

    final caseCols = (await db.rawQuery('PRAGMA table_info(research_cases)')).map((r) => r['name']).toList();
    add('Hypothesis verdict column exists', caseCols.contains('hypothesis_verdict'));

    final iso = _clock.nowIso();
    final parsed = DateTime.tryParse(iso);
    add('Timestamps stored in UTC', iso.endsWith('Z') && parsed != null && parsed.isUtc, iso);

    add('Phone time zone', true,
        'UTC${formatOffset(DateTime.now().timeZoneOffset)} (Dar es Salaam should show +03:00)');
  }

  Future<void> _transactionChecks(
    Transaction txn,
    void Function(String, bool, [String]) add,
  ) async {
    final now = _clock.nowIso();

    // Note round trip + outbox
    final noteId = newId();
    await txn.insert('notes', {
      'id': noteId,
      'created_at': now,
      'updated_at': now,
      'body_md': 'diagnostic note',
    });
    final back = await txn.query('notes', where: 'id = ?', whereArgs: [noteId]);
    add('Note saves and reads back', back.length == 1 && back.first['body_md'] == 'diagnostic note');

    await Outbox.enqueue(txn, 'notes', noteId, nowIso: now);
    await Outbox.enqueue(txn, 'notes', noteId, nowIso: now);
    final queued = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM sync_queue WHERE entity_type = ? AND entity_id = ?',
        ['notes', noteId]));
    add('Outbox merges repeated edits', queued == 1, '$queued queue row(s) after 2 edits');

    // Hypothesis lock rules
    final caseId = newId();
    await txn.insert('research_cases', {
      'id': caseId,
      'created_at': now,
      'updated_at': now,
      'title': 'diagnostic case',
      'hypothesis': 'H1',
      'confidence': 3,
    });
    add('Outcome refused before lock',
        await _throws(() => txn.update('research_cases', {'outcome': 'continuation'},
            where: 'id = ?', whereArgs: [caseId])));
    add('Draft hypothesis still editable',
        !await _throws(() => txn.update('research_cases', {'hypothesis': 'H1b'},
            where: 'id = ?', whereArgs: [caseId])));
    await txn.update('research_cases', {'hypothesis_locked_at': now, 'status': 'locked'},
        where: 'id = ?', whereArgs: [caseId]);
    add('Hypothesis edit refused after lock',
        await _throws(() => txn.update('research_cases', {'hypothesis': 'H2'},
            where: 'id = ?', whereArgs: [caseId])));
    add('Confidence edit refused after lock',
        await _throws(() => txn.update('research_cases', {'confidence': 5},
            where: 'id = ?', whereArgs: [caseId])));
    add('Lock cannot be removed',
        await _throws(() => txn.update('research_cases', {'hypothesis_locked_at': null},
            where: 'id = ?', whereArgs: [caseId])));
    add('Outcome allowed after lock',
        !await _throws(() => txn.update('research_cases', {'outcome': 'continuation'},
            where: 'id = ?', whereArgs: [caseId])));

    final emptyId = newId();
    await txn.insert('research_cases', {
      'id': emptyId,
      'created_at': now,
      'updated_at': now,
      'title': 'diagnostic empty',
      'hypothesis': '',
    });
    add('Empty hypothesis cannot be locked',
        await _throws(() => txn.update('research_cases', {'hypothesis_locked_at': now},
            where: 'id = ?', whereArgs: [emptyId])));

    // Foreign keys are defined (deferred, so checked with foreign_key_check)
    await txn.insert('lessons', {
      'id': newId(),
      'created_at': now,
      'updated_at': now,
      'plan_id': 'no-such-plan',
      'title': 'diagnostic lesson',
    });
    final violations = await txn.rawQuery('PRAGMA foreign_key_check(lessons)');
    add('Foreign keys detect a missing parent', violations.isNotEmpty);
  }

  /// Test 1: a real v1 database is opened by this build and upgraded by the real
  /// migrations. Test 2: one more hypothetical migration is applied on top.
  Future<void> _upgradeTest(void Function(String, bool, [String]) add) async {
    const name1 = 'Real upgrade from v1 keeps data';
    const name2 = 'Future upgrade keeps data';
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'mml_upgrade_test.db');
    try {
      await deleteDatabase(path);
      var test = await AppDatabase.openAt(path, [appMigrations.first]);
      final now = _clock.nowIso();
      await test.insert('research_cases', {
        'id': 'up-case',
        'created_at': now,
        'updated_at': now,
        'title': 'kept',
        'hypothesis': 'H',
      });
      await test.insert('notes', {
        'id': 'up-note',
        'created_at': now,
        'updated_at': now,
        'body_md': 'kept',
      });
      await test.close();

      test = await AppDatabase.openAt(path, appMigrations);
      final cases = await test.query('research_cases');
      final notes = await test.query('notes');
      final cols = (await test.rawQuery('PRAGMA table_info(research_cases)')).map((r) => r['name']).toList();
      final version = Sqflite.firstIntValue(await test.rawQuery('PRAGMA user_version'));
      await test.close();
      add(
        name1,
        cases.length == 1 &&
            cases.first['title'] == 'kept' &&
            notes.length == 1 &&
            cols.contains('hypothesis_verdict') &&
            version == appMigrations.last.version,
        'v$version, cases: ${cases.length}, notes: ${notes.length}',
      );

      final next = Migration(
        appMigrations.last.version + 1,
        'diagnostic column',
        const ['ALTER TABLE notes ADD COLUMN diag_col TEXT'],
      );
      test = await AppDatabase.openAt(path, [...appMigrations, next]);
      final rows = await test.query('notes');
      final noteCols = (await test.rawQuery('PRAGMA table_info(notes)')).map((r) => r['name']).toList();
      final v2 = Sqflite.firstIntValue(await test.rawQuery('PRAGMA user_version'));
      await test.close();
      add(
        name2,
        rows.length == 1 && noteCols.contains('diag_col') && v2 == next.version,
        'v$v2, notes: ${rows.length}',
      );
    } catch (e) {
      add(name1, false, '$e');
    } finally {
      try {
        await deleteDatabase(path);
      } catch (_) {}
    }
  }

  Future<bool> _throws(Future<Object?> Function() action) async {
    try {
      await action();
      return false;
    } catch (_) {
      return true;
    }
  }
}
