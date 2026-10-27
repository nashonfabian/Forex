import 'migration.dart';
import 'migrations/migration_001.dart';
import 'migrations/migration_002.dart';

/// Every schema change ever shipped, in order. Append only.
const List<Migration> appMigrations = <Migration>[migration001, migration002];
