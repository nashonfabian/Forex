import '../../core/db/table_changes.dart';
import '../../core/rows.dart';
import 'base_repository.dart';
import 'meta_repository.dart';

class CaseFilter {
  const CaseFilter({
    this.query = '',
    this.instrument,
    this.timeframe,
    this.condition,
    this.outcome,
  });

  final String query;
  final String? instrument;
  final String? timeframe;
  final String? condition;

  /// An outcome key, or 'pending' for cases with no outcome yet.
  final String? outcome;

  bool get isActive =>
      query.isNotEmpty || instrument != null || timeframe != null || condition != null || outcome != null;

  @override
  bool operator ==(Object other) =>
      other is CaseFilter &&
      other.query == query &&
      other.instrument == instrument &&
      other.timeframe == timeframe &&
      other.condition == condition &&
      other.outcome == outcome;

  @override
  int get hashCode => Object.hash(query, instrument, timeframe, condition, outcome);
}

class GalleryFilter {
  const GalleryFilter({this.inboxOnly = false, this.instrument, this.timeframe, this.phase});

  final bool inboxOnly;
  final String? instrument;
  final String? timeframe;
  final String? phase;

  @override
  bool operator ==(Object other) =>
      other is GalleryFilter &&
      other.inboxOnly == inboxOnly &&
      other.instrument == instrument &&
      other.timeframe == timeframe &&
      other.phase == phase;

  @override
  int get hashCode => Object.hash(inboxOnly, instrument, timeframe, phase);
}

const marketConditions = ['trend', 'balance', 'transition'];
const explorationDirections = ['up', 'down', 'none'];
const caseOutcomes = [
  'continuation',
  'return_to_previous_value',
  'renewed_balance',
  'reversal',
  'inconclusive',
];
const hypothesisVerdicts = ['supported', 'contradicted', 'inconclusive'];
const imagePhases = ['before', 'during', 'after'];

class ResearchRepository extends BaseRepository {
  ResearchRepository(super.app, super.changes, super.clock);

  // ------------------------------------------------------------ cases
  Future<List<Rec>> listCases(CaseFilter f, {int limit = 300}) async {
    final where = <String>['c.deleted_at IS NULL'];
    final args = <Object?>[];
    if (f.instrument != null) {
      where.add('c.instrument = ?');
      args.add(f.instrument);
    }
    if (f.timeframe != null) {
      where.add('c.timeframe = ?');
      args.add(f.timeframe);
    }
    if (f.condition != null) {
      where.add('c.market_condition = ?');
      args.add(f.condition);
    }
    if (f.outcome == 'pending') {
      where.add('c.outcome IS NULL');
    } else if (f.outcome != null) {
      where.add('c.outcome = ?');
      args.add(f.outcome);
    }
    final q = f.query.trim();
    if (q.isNotEmpty) {
      where.add('(c.title LIKE ? OR c.hypothesis LIKE ? OR c.final_lessons LIKE ? OR c.reference_level LIKE ? OR EXISTS ('
          "SELECT 1 FROM entity_tags et JOIN tags t ON t.id = et.tag_id "
          "WHERE et.entity_type = 'research_cases' AND et.entity_id = c.id "
          'AND et.deleted_at IS NULL AND t.deleted_at IS NULL AND t.name LIKE ?))');
      final like = '%$q%';
      args.addAll([like, like, like, like, like]);
    }
    return rawQuery(
      'SELECT c.*, '
      '(SELECT COUNT(*) FROM images i WHERE i.case_id = c.id AND i.deleted_at IS NULL) AS image_count, '
      "(SELECT group_concat(t.name, ', ') FROM entity_tags et JOIN tags t ON t.id = et.tag_id "
      "WHERE et.entity_type = 'research_cases' AND et.entity_id = c.id AND et.deleted_at IS NULL AND t.deleted_at IS NULL) AS tag_names "
      'FROM research_cases c WHERE ${where.join(' AND ')} '
      'ORDER BY COALESCE(c.observed_at, c.created_at) DESC LIMIT $limit',
      args,
    );
  }

  Stream<List<Rec>> watchCases(CaseFilter f) =>
      watchQuery(changes, {'research_cases', 'images', 'entity_tags', 'tags'}, () => listCases(f));

  Future<Rec?> caseById(String id) => getById('research_cases', id);

  Stream<Rec?> watchCase(String id) =>
      watchQuery(changes, {'research_cases'}, () => caseById(id));

  Future<String> createCase(Map<String, Object?> values, List<String> tags) =>
      write(['research_cases', 'tags', 'entity_tags'], (txn, now) async {
        final id = await insertIn(txn, 'research_cases', {'status': 'draft', ...values}, now);
        await setTagsIn(txn, now, 'research_cases', id, tags);
        return id;
      });

  /// Setup fields can always change. Hypothesis fields are protected by the
  /// database once the hypothesis is locked.
  Future<void> updateCase(String id, Map<String, Object?> values, List<String> tags) =>
      write(['research_cases', 'tags', 'entity_tags'], (txn, now) async {
        await updateIn(txn, 'research_cases', id, values, now);
        await setTagsIn(txn, now, 'research_cases', id, tags);
      });

  Future<void> lockHypothesis(String id) => write(
      ['research_cases'],
      (txn, now) => updateIn(
          txn, 'research_cases', id, {'hypothesis_locked_at': now, 'status': 'locked'}, now));

  Future<void> recordOutcome(
    String id, {
    required String outcome,
    String? verdict,
    String? summary,
    String? lessons,
  }) =>
      write(
          ['research_cases'],
          (txn, now) => updateIn(txn, 'research_cases', id, {
                'outcome': outcome,
                'hypothesis_verdict': verdict,
                'outcome_summary': summary,
                'final_lessons': lessons,
                'outcome_at': now,
                'status': 'closed',
              }, now));

  /// Only drafts can be deleted: locked cases are kept as evidence.
  Future<void> deleteDraft(String id) async {
    final row = await caseById(id);
    if (row == null) return;
    if (row.s('status') != 'draft') {
      throw StateError('Only drafts can be deleted. Locked cases are kept as evidence.');
    }
    await write(['research_cases'], (txn, now) => softDeleteIn(txn, 'research_cases', id, now));
  }

  // ------------------------------------------------------------ timeline entries
  Future<List<Rec>> entries(String caseId) async => (await db).query(
        'case_entries',
        where: 'case_id = ? AND deleted_at IS NULL',
        whereArgs: [caseId],
        orderBy: 'created_at ASC',
      );

  Stream<List<Rec>> watchEntries(String caseId) =>
      watchQuery(changes, {'case_entries'}, () => entries(caseId));

  /// Entries are append-only: observations and addenda are added, never rewritten.
  Future<void> addEntry(
    String caseId, {
    required String phase,
    required String kind,
    required String body,
    String? imageId,
  }) =>
      write(['case_entries'], (txn, now) => insertIn(txn, 'case_entries', {
            'case_id': caseId,
            'phase': phase,
            'kind': kind,
            'body': body,
            'image_id': imageId,
          }, now));

  // ------------------------------------------------------------ images
  static const _imageSelect =
      'SELECT i.*, f.local_path AS local_path, f.upload_state AS upload_state '
      'FROM images i LEFT JOIN image_files f ON f.image_id = i.id '
      'LEFT JOIN research_cases c ON c.id = i.case_id';

  Future<List<Rec>> imagesFor({String? caseId, String? tradeId}) async {
    final where = <String>['i.deleted_at IS NULL'];
    final args = <Object?>[];
    if (caseId != null) {
      where.add('i.case_id = ?');
      args.add(caseId);
    }
    if (tradeId != null) {
      where.add('i.trade_id = ?');
      args.add(tradeId);
    }
    return rawQuery(
      '$_imageSelect WHERE ${where.join(' AND ')} ORDER BY COALESCE(i.captured_at, i.created_at) ASC',
      args,
    );
  }

  Stream<List<Rec>> watchImagesFor({String? caseId, String? tradeId}) =>
      watchQuery(changes, {'images'}, () => imagesFor(caseId: caseId, tradeId: tradeId));

  Future<List<Rec>> listImages(GalleryFilter f, {int limit = 500}) async {
    final where = <String>['i.deleted_at IS NULL'];
    final args = <Object?>[];
    if (f.inboxOnly) where.add('i.case_id IS NULL AND i.trade_id IS NULL');
    if (f.instrument != null) {
      where.add('COALESCE(i.instrument, c.instrument) = ?');
      args.add(f.instrument);
    }
    if (f.timeframe != null) {
      where.add('COALESCE(i.timeframe, c.timeframe) = ?');
      args.add(f.timeframe);
    }
    if (f.phase != null) {
      where.add('i.phase = ?');
      args.add(f.phase);
    }
    return rawQuery(
      '$_imageSelect WHERE ${where.join(' AND ')} '
      'ORDER BY COALESCE(i.captured_at, i.created_at) DESC LIMIT $limit',
      args,
    );
  }

  Stream<List<Rec>> watchGallery(GalleryFilter f) =>
      watchQuery(changes, {'images', 'research_cases'}, () => listImages(f));

  Future<Rec?> imageById(String id) async {
    final rows = await rawQuery('$_imageSelect WHERE i.id = ?', [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Stream<Rec?> watchImage(String id) =>
      watchQuery(changes, {'images'}, () => imageById(id));

  Future<void> updateImage(String id, Map<String, Object?> values) =>
      write(['images'], (txn, now) => updateIn(txn, 'images', id, values, now));

  Future<void> deleteImage(String id) =>
      write(['images'], (txn, now) => softDeleteIn(txn, 'images', id, now));

  Future<void> fileImage(String id, {required String caseId, String? phase}) =>
      updateImage(id, {'case_id': caseId, 'phase': phase});

  // ------------------------------------------------------------ filters
  Future<List<String>> instruments() async {
    final rows = await rawQuery(
      'SELECT instrument FROM research_cases WHERE instrument IS NOT NULL AND instrument != \'\' AND deleted_at IS NULL '
      'UNION SELECT instrument FROM trades WHERE instrument IS NOT NULL AND instrument != \'\' AND deleted_at IS NULL '
      'ORDER BY instrument',
    );
    return rows.map((r) => r.s('instrument')).toList();
  }
}
