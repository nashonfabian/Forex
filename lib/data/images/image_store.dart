import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';
import '../../core/db/app_database.dart';
import '../../core/db/table_changes.dart';
import '../../core/ids.dart';
import '../../core/rows.dart';
import '../repositories/base_repository.dart';
import '../sync/outbox.dart';

class ImportResult {
  const ImportResult({
    required this.imported,
    required this.duplicates,
    required this.failed,
    required this.ids,
    this.firstError,
  });

  final int imported;
  final int duplicates;
  final int failed;
  final List<String> ids;
  final String? firstError;
}

/// Keeps chart screenshots as real files inside the app's private storage
/// (never inside SQLite rows). The database stores only a relative path.
class ImageStore {
  ImageStore(this._app, this._changes, this._clock);

  final AppDatabase _app;
  final TableChanges _changes;
  final Clock _clock;
  String _base = '';

  /// Must be called once at startup so paths can be resolved synchronously.
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _base = dir.path;
    await Directory(p.join(_base, 'chartlab')).create(recursive: true);
  }

  String absolutePath(String relative) => p.join(_base, relative);

  static String extensionOf(String name) {
    final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
    return ext.isEmpty ? 'jpg' : ext;
  }

  static String mimeFor(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  /// Copies each picked file into app storage and records it, atomically:
  /// the image row, its local-file row and its upload job are saved together.
  Future<ImportResult> importFiles(
    List<XFile> files, {
    String? caseId,
    String? tradeId,
    String? phase,
  }) async {
    final database = await _app.db;
    var imported = 0;
    var duplicates = 0;
    var failed = 0;
    String? firstError;
    final ids = <String>[];

    for (final file in files) {
      File? copied;
      try {
        final bytes = await file.readAsBytes();
        final id = newId();
        final ext = extensionOf(file.name);
        final relative = p.join('chartlab', '$id.$ext');
        final dest = File(absolutePath(relative));
        await dest.writeAsBytes(bytes, flush: true);
        copied = dest;

        final sha = sha256.convert(bytes).toString();
        final dup = await database.query('images',
            columns: ['id'], where: 'sha256 = ? AND deleted_at IS NULL', whereArgs: [sha], limit: 1);
        final size = await _dimensions(bytes);
        DateTime captured;
        try {
          captured = await file.lastModified();
        } catch (_) {
          captured = DateTime.now();
        }

        final now = _clock.nowIso();
        await database.transaction((txn) async {
          await insertIn(txn, 'images', {
            'case_id': caseId,
            'trade_id': tradeId,
            'phase': phase,
            'captured_at': captured.toUtc().toIso8601String(),
            'mime': mimeFor(ext),
            'width': size[0],
            'height': size[1],
            'bytes': bytes.length,
            'sha256': sha,
          }, now, id: id);
          await txn.insert('image_files', {
            'image_id': id,
            'local_path': relative,
            'upload_state': 'local',
            'created_at': now,
          });
          await Outbox.enqueue(txn, 'images', id, nowIso: now, op: 'blob_upload');
        });

        if (dup.isNotEmpty) duplicates++;
        ids.add(id);
        imported++;
        copied = null;
      } catch (e) {
        failed++;
        firstError ??= '$e';
        if (copied != null) {
          try {
            await copied.delete();
          } catch (_) {}
        }
      }
    }
    if (imported > 0) _changes.notify(const ['images']);
    return ImportResult(
      imported: imported,
      duplicates: duplicates,
      failed: failed,
      ids: ids,
      firstError: firstError,
    );
  }

  Future<List<int>> _dimensions(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        final result = [descriptor.width, descriptor.height];
        descriptor.dispose();
        return result;
      } finally {
        buffer.dispose();
      }
    } catch (_) {
      return [0, 0];
    }
  }

  /// The file on this phone for an image, or null if it is not here
  /// (for example a screenshot that arrived from the cloud and is not downloaded yet).
  Future<File?> localFile(String imageId) async {
    final rows = await (await _app.db)
        .query('image_files', where: 'image_id = ?', whereArgs: [imageId], limit: 1);
    if (rows.isEmpty) return null;
    final file = File(absolutePath(rows.first.s('local_path')));
    return await file.exists() ? file : null;
  }

  /// Writes a downloaded screenshot into app storage and records it as uploaded.
  Future<void> restoreFile(String imageId, String ext, List<int> bytes) async {
    final relative = p.join('chartlab', '$imageId.$ext');
    await File(absolutePath(relative)).writeAsBytes(bytes, flush: true);
    await (await _app.db).insert(
      'image_files',
      {
        'image_id': imageId,
        'local_path': relative,
        'upload_state': 'uploaded',
        'created_at': _clock.nowIso(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _changes.notify(const ['images'], fromSync: true);
  }

  Future<void> removeLocal(String imageId) async {
    final database = await _app.db;
    final rows = await database.query('image_files', where: 'image_id = ?', whereArgs: [imageId]);
    for (final r in rows) {
      try {
        await File(absolutePath(r.s('local_path'))).delete();
      } catch (_) {}
    }
    await database.delete('image_files', where: 'image_id = ?', whereArgs: [imageId]);
  }

  /// Deletes files in the screenshot folder that no database row refers to
  /// (left behind if the app was killed in the middle of an import).
  Future<int> sweepOrphans() async {
    try {
      final database = await _app.db;
      final rows = await database.query('image_files', columns: ['local_path']);
      final known = rows.map((r) => p.basename(r.s('local_path'))).toSet();
      final dir = Directory(p.join(_base, 'chartlab'));
      if (!await dir.exists()) return 0;
      var removed = 0;
      await for (final entity in dir.list()) {
        if (entity is File && !known.contains(p.basename(entity.path))) {
          await entity.delete();
          removed++;
        }
      }
      return removed;
    } catch (_) {
      return 0;
    }
  }
}
