import '../../core/rows.dart';
import 'base_repository.dart';

class SearchResults {
  const SearchResults({
    this.notes = const [],
    this.cases = const [],
    this.trades = const [],
    this.lessons = const [],
  });

  final List<Rec> notes;
  final List<Rec> cases;
  final List<Rec> trades;
  final List<Rec> lessons;

  bool get isEmpty => notes.isEmpty && cases.isEmpty && trades.isEmpty && lessons.isEmpty;
}

class SearchRepository extends BaseRepository {
  SearchRepository(super.app, super.changes, super.clock);

  Future<SearchResults> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const SearchResults();
    final like = '%$q%';

    String tagMatch(String type, String alias) =>
        'EXISTS (SELECT 1 FROM entity_tags et JOIN tags t ON t.id = et.tag_id '
        "WHERE et.entity_type = '$type' AND et.entity_id = $alias.id "
        'AND et.deleted_at IS NULL AND t.deleted_at IS NULL AND t.name LIKE ?)';

    final notes = await rawQuery(
      'SELECT n.* FROM notes n WHERE n.deleted_at IS NULL AND '
      '(n.title LIKE ? OR n.body_md LIKE ? OR n.book LIKE ? OR ${tagMatch('notes', 'n')}) '
      'ORDER BY n.created_at DESC LIMIT 25',
      [like, like, like, like],
    );
    final cases = await rawQuery(
      'SELECT c.* FROM research_cases c WHERE c.deleted_at IS NULL AND '
      '(c.title LIKE ? OR c.hypothesis LIKE ? OR c.final_lessons LIKE ? OR c.reference_level LIKE ? OR ${tagMatch('research_cases', 'c')}) '
      'ORDER BY COALESCE(c.observed_at, c.created_at) DESC LIMIT 25',
      [like, like, like, like, like],
    );
    final trades = await rawQuery(
      'SELECT t.* FROM trades t WHERE t.deleted_at IS NULL AND '
      '(t.instrument LIKE ? OR t.setup_rationale LIKE ? OR t.review_text LIKE ? OR t.process_notes LIKE ?) '
      'ORDER BY COALESCE(t.opened_at, t.created_at) DESC LIMIT 25',
      [like, like, like, like],
    );
    final lessons = await rawQuery(
      'SELECT l.* FROM lessons l WHERE l.deleted_at IS NULL AND '
      '(l.title LIKE ? OR l.objective LIKE ? OR l.assignment LIKE ?) ORDER BY l.order_index ASC LIMIT 25',
      [like, like, like],
    );
    return SearchResults(notes: notes, cases: cases, trades: trades, lessons: lessons);
  }
}
