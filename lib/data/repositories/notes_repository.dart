import '../../core/db/table_changes.dart';
import '../../core/rows.dart';
import 'base_repository.dart';
import 'meta_repository.dart';

/// Value object so a filtered note list can be cached by Riverpod.
class NoteFilter {
  const NoteFilter({
    this.query = '',
    this.kind,
    this.bookmarkedOnly = false,
    this.openQuestionsOnly = false,
    this.lessonId,
  });

  final String query;
  final String? kind;
  final bool bookmarkedOnly;
  final bool openQuestionsOnly;
  final String? lessonId;

  @override
  bool operator ==(Object other) =>
      other is NoteFilter &&
      other.query == query &&
      other.kind == kind &&
      other.bookmarkedOnly == bookmarkedOnly &&
      other.openQuestionsOnly == openQuestionsOnly &&
      other.lessonId == lessonId;

  @override
  int get hashCode => Object.hash(query, kind, bookmarkedOnly, openQuestionsOnly, lessonId);
}

class NotesRepository extends BaseRepository {
  NotesRepository(super.app, super.changes, super.clock);

  Future<List<Rec>> list(NoteFilter f, {int limit = 300}) async {
    final where = <String>['n.deleted_at IS NULL'];
    final args = <Object?>[];
    if (f.kind != null) {
      where.add('n.kind = ?');
      args.add(f.kind);
    }
    if (f.bookmarkedOnly) where.add('n.is_bookmarked = 1');
    if (f.openQuestionsOnly) {
      where.add("n.kind = 'question' AND COALESCE(n.question_status, 'open') = 'open'");
    }
    if (f.lessonId != null) {
      where.add('n.lesson_id = ?');
      args.add(f.lessonId);
    }
    final q = f.query.trim();
    if (q.isNotEmpty) {
      where.add('(n.title LIKE ? OR n.body_md LIKE ? OR n.book LIKE ? OR EXISTS ('
          "SELECT 1 FROM entity_tags et JOIN tags t ON t.id = et.tag_id "
          "WHERE et.entity_type = 'notes' AND et.entity_id = n.id "
          'AND et.deleted_at IS NULL AND t.deleted_at IS NULL AND t.name LIKE ?))');
      final like = '%$q%';
      args.addAll([like, like, like, like]);
    }
    return rawQuery(
      'SELECT n.*, (SELECT group_concat(t.name, \', \') FROM entity_tags et JOIN tags t ON t.id = et.tag_id '
      "WHERE et.entity_type = 'notes' AND et.entity_id = n.id AND et.deleted_at IS NULL AND t.deleted_at IS NULL) AS tag_names "
      'FROM notes n WHERE ${where.join(' AND ')} ORDER BY n.created_at DESC LIMIT $limit',
      args,
    );
  }

  Stream<List<Rec>> watch(NoteFilter f) =>
      watchQuery(changes, {'notes', 'entity_tags', 'tags'}, () => list(f));

  Future<Rec?> byId(String id) => getById('notes', id);

  /// Creates (id == null) or updates a note, including its tags, in one transaction.
  Future<String> save({
    String? id,
    required Map<String, Object?> values,
    required List<String> tags,
  }) =>
      write(['notes', 'tags', 'entity_tags'], (txn, now) async {
        String noteId;
        if (id == null) {
          noteId = await insertIn(txn, 'notes', values, now);
        } else {
          await updateIn(txn, 'notes', id, values, now);
          noteId = id;
        }
        await setTagsIn(txn, now, 'notes', noteId, tags);
        return noteId;
      });

  Future<void> delete(String id) =>
      write(['notes'], (txn, now) => softDeleteIn(txn, 'notes', id, now));

  Future<void> setBookmarked(String id, bool value) => write(
      ['notes'], (txn, now) => updateIn(txn, 'notes', id, {'is_bookmarked': value ? 1 : 0}, now));

  Future<void> setQuestionStatus(String id, String status) => write(
      ['notes'], (txn, now) => updateIn(txn, 'notes', id, {'question_status': status}, now));
}
