import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/repositories/research_repository.dart';
import '../../widgets/common.dart';

/// Full-screen viewer: swipe between screenshots, pinch to zoom.
class ImageViewerScreen extends ConsumerStatefulWidget {
  const ImageViewerScreen({super.key, required this.imageIds, required this.initialIndex});

  final List<String> imageIds;
  final int initialIndex;

  @override
  ConsumerState<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends ConsumerState<ImageViewerScreen> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _currentId => widget.imageIds[_index];

  Future<void> _share(Rec image) async {
    final rel = image.sn('local_path');
    if (rel == null) {
      snack(context, 'This screenshot is not on the phone yet.');
      return;
    }
    final path = ref.read(imageStoreProvider).absolutePath(rel);
    if (!await File(path).exists()) {
      if (mounted) snack(context, 'The file is missing.');
      return;
    }
    await Share.shareXFiles([XFile(path)], text: image.sn('caption'));
  }

  Future<void> _delete(Rec image) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete screenshot?',
      message: 'It will be removed from this case and from the cloud copy.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(researchRepositoryProvider).deleteImage(image.s('id'));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _edit(Rec image) async {
    final caption = TextEditingController(text: image.s('caption'));
    final observation = TextEditingController(text: image.s('observation'));
    final instrument = TextEditingController(text: image.s('instrument'));
    final timeframe = TextEditingController(text: image.s('timeframe'));
    String? phase = image.sn('phase');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Screenshot details', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                LabeledField(controller: caption, label: 'Caption'),
                LabeledField(controller: observation, label: 'Observation', minLines: 2, maxLines: 6),
                ChoiceRow(
                  label: 'Phase',
                  options: imagePhases,
                  value: phase,
                  onChanged: (v) => setSheet(() => phase = v),
                ),
                Row(
                  children: [
                    Expanded(child: LabeledField(controller: instrument, label: 'Instrument')),
                    const SizedBox(width: 8),
                    Expanded(child: LabeledField(controller: timeframe, label: 'Timeframe')),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved == true) {
      await ref.read(researchRepositoryProvider).updateImage(image.s('id'), {
        'caption': emptyToNull(caption.text),
        'observation': emptyToNull(observation.text),
        'phase': phase,
        'instrument': emptyToNull(instrument.text),
        'timeframe': emptyToNull(timeframe.text),
      });
    }
  }

  Future<void> _fileIntoCase(Rec image) async {
    final cases = await ref.read(researchRepositoryProvider).listCases(const CaseFilter());
    if (!mounted) return;
    final chosen = await pickRec(
      context,
      title: 'File into which case?',
      items: cases,
      label: (c) => c.s('title', 'Untitled'),
      subtitle: (c) => [c.sn('instrument'), c.sn('timeframe')].whereType<String>().join(' | '),
    );
    if (chosen == null) return;
    await ref.read(researchRepositoryProvider).fileImage(
          image.s('id'),
          caseId: chosen.s('id'),
          phase: image.sn('phase') ?? 'during',
        );
    if (mounted) snack(context, 'Filed into "${chosen.s('title')}".');
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(imageProvider(_currentId)).valueOrNull;
    final unfiled = current != null && current.sn('case_id') == null && current.sn('trade_id') == null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.imageIds.length}'),
        actions: [
          if (current != null && unfiled)
            IconButton(
              tooltip: 'File into a case',
              icon: const Icon(Icons.drive_file_move_outline),
              onPressed: () => _fileIntoCase(current),
            ),
          if (current != null)
            IconButton(
                tooltip: 'Share', icon: const Icon(Icons.share_outlined), onPressed: () => _share(current)),
          if (current != null)
            IconButton(
                tooltip: 'Details', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(current)),
          if (current != null)
            IconButton(
                tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(current)),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.imageIds.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => _ViewerPage(imageId: widget.imageIds[i]),
      ),
    );
  }
}

class _ViewerPage extends ConsumerStatefulWidget {
  const _ViewerPage({required this.imageId});

  final String imageId;

  @override
  ConsumerState<_ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends ConsumerState<_ViewerPage> {
  bool _downloading = false;

  Future<void> _download() async {
    setState(() => _downloading = true);
    final ok = await ref.read(syncServiceProvider).downloadImageNow(widget.imageId);
    if (!mounted) return;
    setState(() => _downloading = false);
    if (!ok) snack(context, 'Could not download it. Check your connection and sign-in.');
  }

  @override
  Widget build(BuildContext context) {
    final image = ref.watch(imageProvider(widget.imageId)).valueOrNull;
    if (image == null) {
      return const Center(child: Text('Not found', style: TextStyle(color: Colors.white)));
    }
    final store = ref.watch(imageStoreProvider);
    final rel = image.sn('local_path');
    final file = rel == null ? null : File(store.absolutePath(rel));

    final info = <String>[
      if (image.sn('phase') != null) pretty(image.sn('phase')),
      if (image.sn('captured_at') != null) formatLocalDateTime(image.sn('captured_at')),
      if (image.sn('caption') != null) image.s('caption'),
    ].join('  |  ');

    return Stack(
      children: [
        Positioned.fill(
          child: file == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_download_outlined, color: Colors.white70, size: 48),
                      const SizedBox(height: 12),
                      const Text('This screenshot is in the cloud, not on this phone yet.',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _downloading ? null : _download,
                        child: Text(_downloading ? 'Downloading...' : 'Download'),
                      ),
                    ],
                  ),
                )
              : InteractiveViewer(
                  minScale: 1,
                  maxScale: 6,
                  child: Center(child: Image.file(file, fit: BoxFit.contain)),
                ),
        ),
        if (info.isNotEmpty || image.sn('observation') != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (info.isNotEmpty) Text(info, style: const TextStyle(color: Colors.white)),
                  if (image.sn('observation') != null)
                    Text(image.s('observation'), style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
