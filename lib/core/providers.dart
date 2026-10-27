import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/export/backup_service.dart';
import '../data/export/case_report.dart';
import '../data/images/image_store.dart';
import '../data/repositories/learning_repository.dart';
import '../data/repositories/meta_repository.dart';
import '../data/repositories/notes_repository.dart';
import '../data/repositories/research_repository.dart';
import '../data/repositories/reviews_repository.dart';
import '../data/repositories/search_repository.dart';
import '../data/repositories/trades_repository.dart';
import '../data/sync/sync_service.dart';
import 'clock.dart';
import 'db/app_database.dart';
import 'db/table_changes.dart';
import 'rows.dart';

// ---------------------------------------------------------------- infrastructure
final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// The next four are created in main() and passed in as overrides.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('appDatabaseProvider must be overridden in main()'),
);
final tableChangesProvider = Provider<TableChanges>(
  (ref) => throw UnimplementedError('tableChangesProvider must be overridden in main()'),
);
final imageStoreProvider = Provider<ImageStore>(
  (ref) => throw UnimplementedError('imageStoreProvider must be overridden in main()'),
);
final syncServiceProvider = Provider<SyncService>(
  (ref) => throw UnimplementedError('syncServiceProvider must be overridden in main()'),
);

final syncStateProvider = StreamProvider<SyncState>((ref) async* {
  final service = ref.watch(syncServiceProvider);
  yield service.state;
  yield* service.stream;
});

// ---------------------------------------------------------------- repositories
final learningRepositoryProvider = Provider<LearningRepository>((ref) => LearningRepository(
    ref.watch(appDatabaseProvider), ref.watch(tableChangesProvider), ref.watch(clockProvider)));

final notesRepositoryProvider = Provider<NotesRepository>((ref) => NotesRepository(
    ref.watch(appDatabaseProvider), ref.watch(tableChangesProvider), ref.watch(clockProvider)));

final tagsRepositoryProvider = Provider<TagsRepository>((ref) => TagsRepository(
    ref.watch(appDatabaseProvider), ref.watch(tableChangesProvider), ref.watch(clockProvider)));

final linksRepositoryProvider = Provider<LinksRepository>((ref) => LinksRepository(
    ref.watch(appDatabaseProvider), ref.watch(tableChangesProvider), ref.watch(clockProvider)));

final researchRepositoryProvider = Provider<ResearchRepository>((ref) => ResearchRepository(
    ref.watch(appDatabaseProvider), ref.watch(tableChangesProvider), ref.watch(clockProvider)));

final tradesRepositoryProvider = Provider<TradesRepository>((ref) => TradesRepository(
    ref.watch(appDatabaseProvider), ref.watch(tableChangesProvider), ref.watch(clockProvider)));

final reviewsRepositoryProvider = Provider<ReviewsRepository>((ref) => ReviewsRepository(
    ref.watch(appDatabaseProvider), ref.watch(tableChangesProvider), ref.watch(clockProvider)));

final searchRepositoryProvider = Provider<SearchRepository>((ref) => SearchRepository(
    ref.watch(appDatabaseProvider), ref.watch(tableChangesProvider), ref.watch(clockProvider)));

final caseReportProvider = Provider<CaseReport>((ref) => CaseReport(
    ref.watch(researchRepositoryProvider),
    ref.watch(linksRepositoryProvider),
    ref.watch(tagsRepositoryProvider),
    ref.watch(imageStoreProvider)));

final backupServiceProvider = Provider<BackupService>((ref) => BackupService(
    ref.watch(appDatabaseProvider),
    ref.watch(tableChangesProvider),
    ref.watch(clockProvider),
    ref.watch(imageStoreProvider)));

// ---------------------------------------------------------------- live data
final todayProvider = StreamProvider.autoDispose<TodayData>((ref) {
  final repo = ref.watch(learningRepositoryProvider);
  final ymd = ref.watch(clockProvider).todayLocal();
  return repo.watchToday(ymd);
});

final activePlanProvider = StreamProvider.autoDispose<Rec?>(
    (ref) => ref.watch(learningRepositoryProvider).watchActivePlan());

final lessonsProvider = StreamProvider.autoDispose.family<List<Rec>, String>(
    (ref, planId) => ref.watch(learningRepositoryProvider).watchLessons(planId));

final lessonProvider = StreamProvider.autoDispose.family<Rec?, String>(
    (ref, id) => ref.watch(learningRepositoryProvider).watchLesson(id));

final lessonMinutesProvider = StreamProvider.autoDispose.family<int, String>(
    (ref, id) => ref.watch(learningRepositoryProvider).watchMinutesForLesson(id));

final notesProvider = StreamProvider.autoDispose.family<List<Rec>, NoteFilter>(
    (ref, filter) => ref.watch(notesRepositoryProvider).watch(filter));

final casesProvider = StreamProvider.autoDispose.family<List<Rec>, CaseFilter>(
    (ref, filter) => ref.watch(researchRepositoryProvider).watchCases(filter));

final caseProvider = StreamProvider.autoDispose.family<Rec?, String>(
    (ref, id) => ref.watch(researchRepositoryProvider).watchCase(id));

final caseEntriesProvider = StreamProvider.autoDispose.family<List<Rec>, String>(
    (ref, caseId) => ref.watch(researchRepositoryProvider).watchEntries(caseId));

final caseImagesProvider = StreamProvider.autoDispose.family<List<Rec>, String>(
    (ref, caseId) => ref.watch(researchRepositoryProvider).watchImagesFor(caseId: caseId));

final tradeImagesProvider = StreamProvider.autoDispose.family<List<Rec>, String>(
    (ref, tradeId) => ref.watch(researchRepositoryProvider).watchImagesFor(tradeId: tradeId));

final imageProvider = StreamProvider.autoDispose.family<Rec?, String>(
    (ref, id) => ref.watch(researchRepositoryProvider).watchImage(id));

final galleryProvider = StreamProvider.autoDispose.family<List<Rec>, GalleryFilter>(
    (ref, filter) => ref.watch(researchRepositoryProvider).watchGallery(filter));

final tradesProvider = StreamProvider.autoDispose.family<List<Rec>, TradeFilter>(
    (ref, filter) => ref.watch(tradesRepositoryProvider).watch(filter));

final tradesSummaryProvider = StreamProvider.autoDispose<List<Rec>>(
    (ref) => ref.watch(tradesRepositoryProvider).watchSummary());

/// Key format: "<table>|<id>", for example "research_cases|abc".
final linkedProvider = StreamProvider.autoDispose.family<List<LinkedItem>, String>((ref, key) {
  final parts = key.split('|');
  return ref.watch(linksRepositoryProvider).watchLinked(parts[0], parts[1]);
});

final reviewProvider = StreamProvider.autoDispose.family<Rec?, String>((ref, key) {
  final parts = key.split('|'); // "<kind>|<periodStart>"
  return ref.watch(reviewsRepositoryProvider).watchReview(parts[0], parts[1]);
});

final reviewListProvider = StreamProvider.autoDispose.family<List<Rec>, String>(
    (ref, kind) => ref.watch(reviewsRepositoryProvider).watchReviews(kind));

final instrumentsProvider = FutureProvider.autoDispose<List<String>>(
    (ref) => ref.watch(researchRepositoryProvider).instruments());

/// Key format: "<table>|<id>".
final tagNamesProvider = StreamProvider.autoDispose.family<List<String>, String>((ref, key) {
  final parts = key.split('|');
  return ref.watch(tagsRepositoryProvider).watchNamesFor(parts[0], parts[1]);
});
