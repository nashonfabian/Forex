import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migration.dart';
import 'migrations.dart';

class AppDatabase {
  AppDatabase({this.fileName = 'my_market_lab.db', List<Migration>? migrations})
      : migrations = migrations ?? appMigrations;

  final String fileName;
  final List<Migration> migrations;
  Future<Database>? _opening;

  Future<Database> get db => _opening ??= _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openAt(p.join(dir, fileName), migrations);
  }

  /// Opens (and creates / upgrades) a database file with the given migrations.
  /// Exposed so diagnostics can test an upgrade on a throw-away file.
  static Future<Database> openAt(String path, List<Migration> migrations) {
    final latest = migrations.last.version;
    return openDatabase(
      path,
      version: latest,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        for (final m in migrations.where((m) => m.version <= version)) {
          await m.apply(db);
        }
      },
      onUpgrade: (db, from, to) async {
        for (final m in migrations.where((m) => m.version > from && m.version <= to)) {
          await m.apply(db);
        }
      },
      // Deliberately no onDowngrade: opening a database that is newer than
      // this build must fail loudly, never wipe the user's data.
    );
  }

  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening == null) return;
    try {
      await (await opening).close();
    } catch (_) {}
  }
}
