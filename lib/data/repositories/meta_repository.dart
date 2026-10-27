import 'package:sqflite/sqflite.dart';

import '../../core/db/table_changes.dart';
import '../../core/rows.dart';
import 'base_repository.dart';

/// Replaces the tags of one record with [names] (creates tags as needed).
/// Runs inside the caller's transaction.
Future<void> setTagsIn(
  Transaction txn,
  String now,
  String entityType,
  String entityId,
  List<String> names,
) async {
  final wanted = <String>{};
  for (final name in names) {
    final t = name.trim();
    if (t.isNotEmpty) wanted.add(t);
  }

  final tagIds = <String>{};
  for (final name in wanted) {
    final existing = await txn.query(
      'tags',
      where: 'LOWER(name) = LOWER(?) AND deleted_at IS NULL',
      whereArgs: [name],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      tagIds.add(existing.first['id'] as String);
    } else {
      tagIds.add(await insertIn(txn, 'tags', {'name': name}, now));
    }
  }

  final current = await txn.query(
    'entity_tags',
    where: 'entity_type = ? AND entity_id = ? AND deleted_at IS NULL',
    whereArgs: [entityType, entityId],
  );
  final have = <String>{};
  for (final row in current) {
    final tagId = row['tag_id'] as String;
    if (tagIds.contains(tagId)) {
      have.add(tagId);
    } else {
      await softDeleteIn(txn, 'entity_tags', row['id'] as String, now);
    }
  }
  for (final tagId in tagIds) {
    if (!have.contains(tagId)) {
      await insertIn(
        txn,
        'entity_tags',
        {'tag_id': tagId, 'entity_type': entityType, 'entity_id': entityId},
        now,
      );
    }
  }
}

class TagsRepository extends BaseRepository {
  TagsRepository(super.app, super.changes, super.clock);

  Future<List<String>> namesFor(String entityType, String entityId) async {
    final rows = await rawQuery(
      'SELECT t.name AS name FROM entity_tags et JOIN tags t ON t.id = et.tag_id '
      'WHERE et.entity_type = ? AND et.entity_id = ? AND et.deleted_at IS NULL AND t.deleted_at IS NULL '
      'ORDER BY t.name',
      [entityType, entityId],
    );
    return rows.map((r) => r.s('name')).toList();
  }

  Stream<List<String>> watchNamesFor(String entityType, String entityId) =>
      watchQuery(changes, {'tags', 'entity_tags'}, () => namesFor(entityType, entityId));

  Future<List<String>> allNames() async {
    final rows = await rawQuery(
        'SELECT name FROM tags WHERE deleted_at IS NULL ORDER BY name');
    return rows.map((r) => r.s('name')).toList();
  }
}

class LinkedItem {
  const LinkedItem({
    required this.linkId,
    required this.type,
    required this.id,
    required this.title,
  });

  final String linkId;

  /// A table name: research_cases, lessons, notes, trades or images.
  final String type;
  final String id;
  final String title;
}

class LinksRepository extends BaseRepository {
  LinksRepository(super.app, super.changes, super.clock);

  Future<void> link(String fromType, String fromId, String toType, String toId) async {
    final existing = await (await db).query(
      'links',
      where: 'deleted_at IS NULL AND ('
          '(from_type = ? AND from_id = ? AND to_type = ? AND to_id = ?) OR '
          '(from_type = ? AND from_id = ? AND to_type = ? AND to_id = ?))',
      whereArgs: [fromType, fromId, toType, toId, toType, toId, fromType, fromId],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    await write(['links'], (txn, now) => insertIn(
          txn,
          'links',
          {'from_type': fromType, 'from_id': fromId, 'to_type': toType, 'to_id': toId},
          now,
        ));
  }

  Future<void> unlink(String linkId) =>
      write(['links'], (txn, now) => softDeleteIn(txn, 'links', linkId, now));

  Future<List<LinkedItem>> linkedTo(String type, String id) async {
    final rows = await (await db).query(
      'links',
      where: 'deleted_at IS NULL AND ((from_type = ? AND from_id = ?) OR (to_type = ? AND to_id = ?))',
      whereArgs: [type, id, type, id],
      orderBy: 'created_at ASC',
    );
    final items = <LinkedItem>[];
    for (final r in rows) {
      final fromSide = r.s('from_type') == type && r.s('from_id') == id;
      final otherType = fromSide ? r.s('to_type') : r.s('from_type');
      final otherId = fromSide ? r.s('to_id') : r.s('from_id');
      final title = await _titleOf(otherType, otherId);
      if (title != null) {
        items.add(LinkedItem(linkId: r.s('id'), type: otherType, id: otherId, title: title));
      }
    }
    return items;
  }

  Stream<List<LinkedItem>> watchLinked(String type, String id) => watchQuery(
        changes,
        {'links', 'notes', 'lessons', 'research_cases', 'trades', 'images'},
        () => linkedTo(type, id),
      );

  Future<String?> _titleOf(String type, String id) async {
    final database = await db;
    final rows = await database.query(type, where: 'id = ? AND deleted_at IS NULL', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    switch (type) {
      case 'research_cases':
      case 'lessons':
        return r.s('title', 'Untitled');
      case 'notes':
        final t = r.sn('title');
        if (t != null) return t;
        final body = r.s('body_md');
        return body.length > 40 ? '${body.substring(0, 40)}...' : (body.isEmpty ? 'Note' : body);
      case 'trades':
        return '${r.s('instrument')} ${r.s('direction')}';
      case 'images':
        return r.sn('caption') ?? 'Screenshot';
    }
    return null;
  }
}
