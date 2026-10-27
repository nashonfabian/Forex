import 'package:sqflite/sqflite.dart';

/// One numbered, append-only schema change. `version` becomes SQLite's
/// `PRAGMA user_version`. Never edit a migration after it has shipped.
class Migration {
  const Migration(this.version, this.name, this.statements);

  final int version;
  final String name;

  /// One SQL statement per entry (Android's execSQL runs a single statement).
  final List<String> statements;

  Future<void> apply(DatabaseExecutor db) async {
    for (final sql in statements) {
      await db.execute(sql);
    }
  }
}
