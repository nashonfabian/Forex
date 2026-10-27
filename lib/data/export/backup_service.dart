import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';
import '../../core/db/app_database.dart';
import '../../core/db/table_changes.dart';
import '../../core/rows.dart';
import '../images/image_store.dart';
import '../sync/outbox.dart';
import '../sync/sync_service.dart';

class BackupSummary {
  const BackupSummary({required this.rows, required this.images});
  final int rows;
  final int images;
}

/// Local backup as one ZIP: data.json (every table) plus the screenshot files.
/// Importing only ADDS records that are missing; it never overwrites or deletes
/// anything already on the phone (so a locked hypothesis can never be altered).
class BackupService {
  BackupService(this._app, this._changes, this._clock, this._images);

  final AppDatabase _app;
  final TableChanges _changes;
  final Clock _clock;
  final ImageStore _images;

  Future<File> exportZip() async {
    final database = await _app.db;
    final tables = <String, Object?>{};
    for (final table in SyncService.syncTables) {
      tables[table] = await database.query(table);
    }
    final files = await database.rawQuery(
      'SELECT f.local_path AS local_path FROM image_files f '
      'JOIN images i ON i.id = f.image_id WHERE i.deleted_at IS NULL',
    );

    final tmp = await getTemporaryDirectory();
    final dataFile = File(p.join(tmp.path, 'mml_data.json'));
    await dataFile.writeAsString(jsonEncode({
      'format': 'mml-backup',
      'version': 1,
      'exported_at': _clock.nowIso(),
      'tables': tables,
    }));

    final stamp = _clock.nowUtc().toLocal().toIso8601String().substring(0, 10);
    final zipPath = p.join(tmp.path, 'my_market_lab_backup_$stamp.zip');
    final encoder = ZipFileEncoder();
    // Called through `dynamic` so this works whether the installed archive
    // version makes these calls synchronous or asynchronous.
    final dynamic enc = encoder;
    enc.create(zipPath);
    await enc.addFile(dataFile, 'data.json');
    for (final f in files) {
      final file = File(_images.absolutePath(f.s('local_path')));
      if (await file.exists()) {
        await enc.addFile(file, 'images/${p.basename(file.path)}');
      }
    }
    await enc.close();
    await dataFile.delete();
    return File(zipPath);
  }

  Future<BackupSummary> importZip(String path) async {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeBuffer(input);
      ArchiveFile? dataEntry;
      for (final f in archive.files) {
        if (f.isFile && f.name == 'data.json') dataEntry = f;
      }
      if (dataEntry == null) {
        throw const FormatException('This file is not a MY MARKET LAB backup.');
      }
      final decoded = jsonDecode(utf8.decode(dataEntry.content as List<int>));
      if (decoded is! Map || decoded['format'] != 'mml-backup') {
        throw const FormatException('This file is not a MY MARKET LAB backup.');
      }
      final tables = decoded['tables'];
      if (tables is! Map) {
        throw const FormatException('The backup has no data.');
      }

      final database = await _app.db;
      final now = _clock.nowIso();
      var inserted = 0;
      await database.transaction((txn) async {
        for (final table in SyncService.syncTables) {
          final rows = tables[table];
          if (rows is! List) continue;
          final cols = (await txn.rawQuery('PRAGMA table_info($table)'))
              .map((r) => r['name'] as String)
              .toSet();
          for (final raw in rows) {
            if (raw is! Map) continue;
            final row = <String, Object?>{};
            raw.forEach((key, value) {
              if (cols.contains(key)) row['$key'] = value;
            });
            final id = row['id'];
            if (id is! String) continue;
            final result = await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.ignore);
            if (result > 0) {
              inserted++;
              await Outbox.enqueue(txn, table, id, nowIso: now);
            }
          }
        }
      });

      var restoredImages = 0;
      for (final f in archive.files) {
        if (!f.isFile || !f.name.startsWith('images/')) continue;
        final name = p.basename(f.name);
        final imageId = p.basenameWithoutExtension(name);
        final relative = p.join('chartlab', name);
        final dest = File(_images.absolutePath(relative));
        if (!await dest.exists()) {
          await dest.writeAsBytes(f.content as List<int>, flush: true);
        }
        final image = await database.query('images',
            columns: ['id', 'storage_path'], where: 'id = ?', whereArgs: [imageId], limit: 1);
        if (image.isEmpty) continue;
        final have = await database.query('image_files',
            where: 'image_id = ?', whereArgs: [imageId], limit: 1);
        if (have.isNotEmpty) continue;
        final uploaded = image.first.sn('storage_path') != null;
        await database.insert('image_files', {
          'image_id': imageId,
          'local_path': relative,
          'upload_state': uploaded ? 'uploaded' : 'local',
          'created_at': now,
        });
        if (!uploaded) {
          await Outbox.enqueue(database, 'images', imageId, nowIso: now, op: 'blob_upload');
        }
        restoredImages++;
      }

      _changes.notify(SyncService.syncTables);
      return BackupSummary(rows: inserted, images: restoredImages);
    } finally {
      try {
        final dynamic stream = input;
        await stream.close();
      } catch (_) {}
    }
  }
}
