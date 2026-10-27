import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/format.dart';
import '../../core/rows.dart';
import '../images/image_store.dart';
import '../repositories/meta_repository.dart';
import '../repositories/research_repository.dart';

/// Builds a PDF of one research case: setup, the locked hypothesis exactly as
/// written, the observation timeline, the outcome and the screenshots.
class CaseReport {
  CaseReport(this._research, this._links, this._tags, this._images);

  final ResearchRepository _research;
  final LinksRepository _links;
  final TagsRepository _tags;
  final ImageStore _images;

  // The built-in PDF font covers Latin-1 only; anything else becomes '?'.
  String _t(String s) => String.fromCharCodes(s.runes.map((r) => r < 256 ? r : 63));

  pw.Widget _heading(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 4),
        child: pw.Text(_t(text),
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _para(String text) =>
      pw.Text(_t(text), style: const pw.TextStyle(fontSize: 10.5));

  pw.Widget _field(String label, String? value) {
    if (value == null || value.trim().isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(_t(label),
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          _para(value),
        ],
      ),
    );
  }

  Future<File> build(String caseId) async {
    final c = await _research.caseById(caseId);
    if (c == null) throw StateError('Case not found.');
    final entries = await _research.entries(caseId);
    final images = await _research.imagesFor(caseId: caseId);
    final linked = await _links.linkedTo('research_cases', caseId);
    final tags = await _tags.namesFor('research_cases', caseId);

    final w = <pw.Widget>[];
    w.add(pw.Text(_t(c.s('title', 'Research case')),
        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)));
    w.add(pw.SizedBox(height: 4));
    final meta = [
      c.sn('instrument'),
      c.sn('timeframe'),
      c.sn('market_condition') == null ? null : pretty(c.sn('market_condition')),
      c.sn('observed_at') == null ? null : formatLocalDateTime(c.sn('observed_at')),
    ].whereType<String>().join('  |  ');
    if (meta.isNotEmpty) w.add(_para(meta));
    if (tags.isNotEmpty) w.add(_para('Tags: ${tags.join(', ')}'));

    w.add(_heading('Setup'));
    w.add(_field('Reference level / value area', c.sn('reference_level')));
    w.add(_field('Direction of exploration', c.sn('exploration_direction')));

    final lockedAt = c.sn('hypothesis_locked_at');
    w.add(_heading(lockedAt == null
        ? 'Hypothesis (DRAFT - not locked)'
        : 'Hypothesis (locked ${formatLocalDateTime(lockedAt)}, kept exactly as written)'));
    w.add(_field('Hypothesis', c.sn('hypothesis')));
    w.add(_field('Evidence supporting', c.sn('evidence_for')));
    w.add(_field('Evidence contradicting', c.sn('evidence_against')));
    w.add(_field('Acceptance / rejection observations', c.sn('acceptance_rejection')));
    w.add(_field('Alternative scenarios', c.sn('alternatives')));
    w.add(_field('Invalidation conditions', c.sn('invalidation')));
    final conf = c.iN('confidence');
    if (conf != null) w.add(_field('Confidence (before the outcome)', '$conf / 5'));

    if (entries.isNotEmpty) {
      w.add(_heading('Observations and addenda'));
      for (final e in entries) {
        w.add(_field(
          '${pretty(e.s('kind'))} (${e.s('phase')}) - ${formatLocalDateTime(e.sn('created_at'))}',
          e.s('body'),
        ));
      }
    }

    w.add(_heading('Outcome'));
    if (c.sn('outcome') == null) {
      w.add(_para('No outcome recorded yet.'));
    } else {
      w.add(_field('Outcome', pretty(c.sn('outcome'))));
      w.add(_field('Hypothesis verdict', pretty(c.sn('hypothesis_verdict'))));
      w.add(_field('Recorded', formatLocalDateTime(c.sn('outcome_at'))));
      w.add(_field('Summary', c.sn('outcome_summary')));
      w.add(_field('Final lessons', c.sn('final_lessons')));
    }

    if (linked.isNotEmpty) {
      w.add(_heading('Linked records'));
      for (final item in linked) {
        w.add(_para('- ${pretty(item.type.replaceAll('research_cases', 'case'))}: ${item.title}'));
      }
    }

    if (images.isNotEmpty) {
      w.add(_heading('Screenshots'));
      for (final img in images) {
        final label = [
          pretty(img.sn('phase')),
          if (img.sn('captured_at') != null) formatLocalDateTime(img.sn('captured_at')),
        ].where((s) => s.isNotEmpty).join(' - ');
        w.add(_para(label.isEmpty ? 'Screenshot' : label));
        if (img.sn('caption') != null) w.add(_para(img.s('caption')));
        if (img.sn('observation') != null) w.add(_para(img.s('observation')));

        Uint8List? bytes;
        final rel = img.sn('local_path');
        if (rel != null) {
          final file = File(_images.absolutePath(rel));
          if (await file.exists()) bytes = await _pngBytes(file);
        }
        if (bytes == null) {
          w.add(_para('(image is not available on this phone)'));
        } else {
          w.add(pw.Container(
            height: 400,
            alignment: pw.Alignment.center,
            child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
          ));
        }
        w.add(pw.SizedBox(height: 10));
      }
    }

    w.add(pw.SizedBox(height: 16));
    w.add(pw.Text(
      'Generated by MY MARKET LAB on ${formatLongDate(DateTime.now())}.',
      style: const pw.TextStyle(fontSize: 8),
    ));

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => w,
    ));

    final dir = await getTemporaryDirectory();
    final safe = c.s('title', 'case').replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final name = safe.length > 40 ? safe.substring(0, 40) : safe;
    final file = File(p.join(dir.path, 'case_$name.pdf'));
    await file.writeAsBytes(await doc.save(), flush: true);
    return file;
  }

  /// Downscales to at most 1400 px and re-encodes as PNG so the PDF always
  /// accepts it (and stays a reasonable size).
  Future<Uint8List?> _pngBytes(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        final width = descriptor.width;
        final height = descriptor.height;
        final longest = width > height ? width : height;
        final scale = longest > 1400 ? 1400 / longest : 1.0;
        final codec = await descriptor.instantiateCodec(
          targetWidth: (width * scale).round(),
          targetHeight: (height * scale).round(),
        );
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        frame.image.dispose();
        codec.dispose();
        descriptor.dispose();
        return data?.buffer.asUint8List();
      } finally {
        buffer.dispose();
      }
    } catch (_) {
      return null;
    }
  }
}
