import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/supabase_config.dart';
import 'core/clock.dart';
import 'core/db/app_database.dart';
import 'core/db/table_changes.dart';
import 'core/providers.dart';
import 'data/images/image_store.dart';
import 'data/sync/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const clock = SystemClock();
  final database = AppDatabase();
  final changes = TableChanges();
  final images = ImageStore(database, changes, clock);

  try {
    // Open and migrate before the first frame so a failure is visible,
    // not a silent blank screen.
    await database.db;
    await images.init();
  } catch (error, stack) {
    debugPrint('Startup failed: $error\n$stack');
    runApp(StartupErrorApp(message: '$error'));
    return;
  }

  if (SupabaseConfig.isConfigured) {
    try {
      await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.anonKey);
    } catch (e) {
      debugPrint('Supabase could not start (the app still works offline): $e');
    }
  }

  // Remove screenshot files left behind by an interrupted import, then start syncing.
  await images.sweepOrphans();
  final sync = SyncService(database, changes, clock, images);
  unawaited(sync.start());

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        tableChangesProvider.overrideWithValue(changes),
        imageStoreProvider.overrideWithValue(images),
        syncServiceProvider.overrideWithValue(sync),
      ],
      child: const MyMarketLabApp(),
    ),
  );
}
