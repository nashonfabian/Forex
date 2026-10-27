import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../widgets/common.dart';

/// Lets the user choose several screenshots from the gallery and stores them.
/// With no case or trade they go to the "Inbox" and can be filed later.
Future<void> pickAndImport(
  BuildContext context,
  WidgetRef ref, {
  String? caseId,
  String? tradeId,
  String? phase,
}) async {
  try {
    final files = await ImagePicker().pickMultiImage();
    if (files.isEmpty) return;
    final result = await ref
        .read(imageStoreProvider)
        .importFiles(files, caseId: caseId, tradeId: tradeId, phase: phase);
    if (!context.mounted) return;
    final parts = <String>['${result.imported} added'];
    if (result.duplicates > 0) parts.add('${result.duplicates} already in your library');
    if (result.failed > 0) parts.add('${result.failed} failed (${result.firstError ?? 'unknown error'})');
    snack(context, parts.join(', '));
  } catch (e) {
    if (context.mounted) snack(context, 'Could not import screenshots: $e');
  }
}
