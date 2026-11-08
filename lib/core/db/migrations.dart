import 'migration.dart';
import 'migrations/migration_001.dart';
import 'migrations/migration_002.dart';
import 'migrations/migration_003.dart';
import 'migrations/migration_004.dart';
import 'migrations/migration_005.dart';
import 'migrations/migration_006.dart';

/// Every schema change ever shipped, in order. Append only.
const List<Migration> appMigrations = <Migration>[
  migration001,
  migration002,
  migration003,
  migration004,
  migration005,
  migration006,
];
