import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/repositories/research_repository.dart';
import '../../data/repositories/visual_backtesting_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/image_thumb.dart';
import 'image_import.dart';

class VisualTestScreen extends ConsumerStatefulWidget {
  const VisualTestScreen({
    super.key,
    required this.strategyId,
    this.testId,
  });

  final String strategyId;
  final String? testId;

  @override
  ConsumerState<VisualTestScreen> createState() => _VisualTestScreenState();
}

class _VisualTestScreenState extends ConsumerState<VisualTestScreen> {
  final _notes = TextEditingController();
  final _rMultiple = TextEditingController();
  final Set<String> _imageIds = {};
  final Map<String, List<Rec>> _annotations = {};
  String _outcome = 'pending';
  DateTime _testedAt = DateTime.now();
  String? _annotationKind;
  bool _loading = false;
  bool _saving = false;
  String? _strategyName;
  Map<String, Object?>? _strategySnapshot;

  @override
  void initState() {
    super.initState();
    if (widget.testId != null) {
      _loading = true;
      _load();
    } else {
      _loadStrategy();
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    _rMultiple.dispose();
    super.dispose();
  }

  Future<void> _loadStrategy() async {
    try {
      final strategy = await ref
          .read(visualBacktestingRepositoryProvider)
          .strategyById(widget.strategyId);
      if (strategy == null) throw StateError('Strategy not found.');
      if (mounted) {
        setState(() {
          _strategyName = strategy.s('name');
          _strategySnapshot = strategy;
        });
      }
    } catch (e) {
      if (mounted) snack(context, 'Could not load strategy: $e');
    }
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(visualBacktestingRepositoryProvider);
      final test = await repo.testById(widget.testId!);
      if (test == null) throw StateError('Visual test not found.');
      final decodedSnapshot = jsonDecode(test.s('strategy_snapshot_json'));
      if (decodedSnapshot is! Map ||
          decodedSnapshot.keys.any((key) => key is! String)) {
        throw const FormatException('Saved test strategy details are invalid.');
      }
      _strategySnapshot = decodedSnapshot.map(
        (key, value) => MapEntry('$key', value),
      );
      _strategyName = test.s('strategy_name_snapshot');
      _notes.text = test.s('notes');
      _outcome = test.s('outcome', 'pending');
      final resultR = test['result_r'];
      _rMultiple.text = resultR is num ? numToText(resultR.toDouble()) : '';
      final testedAt = DateTime.tryParse(test.s('tested_at'));
      if (testedAt != null) _testedAt = testedAt.toLocal();
      final images = await repo.imagesForTest(widget.testId!);
      _imageIds.addAll(images.map((image) => image.s('id')));
      final annotations = await repo.annotationsForTest(widget.testId!);
      for (final annotation in annotations) {
        if (!_imageIds.contains(annotation.s('image_id'))) continue;
        _annotations
            .putIfAbsent(annotation.s('image_id'), () => [])
            .add(annotation);
      }
    } catch (e) {
      if (mounted) snack(context, 'Could not load visual test: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _importScreenshots() async {
    await pickAndImport(context, ref);
  }

  void _setImageSelected(String id, bool selected) {
    setState(() {
      if (selected) {
        _imageIds.add(id);
      } else {
        _imageIds.remove(id);
        _annotations.remove(id);
      }
    });
  }

  Future<void> _addAnnotation(String imageId, double x, double y) async {
    final kind = _annotationKind;
    if (kind == null) {
      snack(context, 'Choose a chart mark before tapping the chart.');
      return;
    }
    final label = TextEditingController(
      text: kind == 'observation' ? '' : pretty(kind),
    );
    final price = TextEditingController();
    final values = await showDialog<({String label, double? price})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Add ${pretty(kind).toLowerCase()} mark'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LabeledField(
              controller: label,
              label: kind == 'observation' ? 'Observation' : 'Label',
            ),
            LabeledField(
              controller: price,
              label: 'Price (optional)',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsedPrice = parseDouble(price.text);
              if (price.text.trim().isNotEmpty && parsedPrice == null) {
                snack(dialogContext, 'Enter a valid finite price.');
                return;
              }
              if (kind == 'observation' && label.text.trim().isEmpty) {
                snack(dialogContext, 'Enter an observation.');
                return;
              }
              Navigator.pop(
                dialogContext,
                (label: label.text.trim(), price: parsedPrice),
              );
            },
            child: const Text('Add mark'),
          ),
        ],
      ),
    );
    label.dispose();
    price.dispose();
    if (values == null || !mounted) return;
    setState(() {
      _annotations.putIfAbsent(imageId, () => []).add({
        'kind': kind,
        'x': x,
        'y': y,
        'price': values.price,
        'label': values.label,
      });
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final resultR =
        _rMultiple.text.trim().isEmpty ? null : parseDouble(_rMultiple.text);
    if (_rMultiple.text.trim().isNotEmpty && resultR == null) {
      snack(context, 'R-multiple must be a valid finite number.');
      return;
    }
    final outcomeError = validateVisualOutcome(_outcome, resultR);
    if (outcomeError != null) {
      snack(context, outcomeError);
      return;
    }
    if (_imageIds.isEmpty) {
      snack(context, 'Select at least one chart screenshot to test.');
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(visualBacktestingRepositoryProvider);
      final id = await repo.saveTest(
        id: widget.testId,
        strategyId: widget.strategyId,
        testedAt: _testedAt.toUtc().toIso8601String(),
        outcome: _outcome,
        resultR: resultR,
        notes: _notes.text,
        imageIds: _imageIds.toList(),
        annotationsByImage: _annotations,
      );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) snack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.testId;
    if (id == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Delete this visual test?',
      message:
          'Its result and chart marks will be removed from visual test history.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(visualBacktestingRepositoryProvider).deleteTest(id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) snack(context, friendlyError(e));
    }
  }

  String _dateText() =>
      '${_testedAt.toLocal().year.toString().padLeft(4, '0')}-'
      '${_testedAt.toLocal().month.toString().padLeft(2, '0')}-'
      '${_testedAt.toLocal().day.toString().padLeft(2, '0')}';

  List<String> _snapshotOptions(String key) {
    final encoded = _strategySnapshot?[key];
    if (encoded is! String) return const [];
    final decoded = jsonDecode(encoded);
    if (decoded is! List || decoded.any((value) => value is! String)) {
      throw const FormatException('Saved test market selections are invalid.');
    }
    return decoded.cast<String>();
  }

  @override
  Widget build(BuildContext context) {
    final gallery = ref.watch(galleryProvider(const GalleryFilter()));
    final selectedImages = gallery.valueOrNull
            ?.where((image) => _imageIds.contains(image.s('id')))
            .toList() ??
        const <Rec>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.testId == null ? 'Test setup' : 'Visual test'),
        actions: [
          if (widget.testId != null)
            IconButton(
              tooltip: 'Delete visual test',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionCard(
                  title: 'Strategy',
                  children: [
                    Text(_strategyName ?? 'Strategy unavailable'),
                    if (_strategySnapshot != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Entry: ${_strategySnapshot!['entry_conditions'] ?? ''}',
                      ),
                      Text(
                        'Exit: ${_strategySnapshot!['exit_conditions'] ?? ''}',
                      ),
                      Text(
                        'Stop loss: ${_strategySnapshot!['stop_loss_rules'] ?? ''}',
                      ),
                      Text(
                        'Take profit: ${_strategySnapshot!['take_profit_rules'] ?? ''}',
                      ),
                      Text(
                        'Stay out: ${_strategySnapshot!['stay_out_conditions'] ?? ''}',
                      ),
                      Text(
                        'Sessions: ${_snapshotOptions('sessions_json').join(', ')} · '
                        'Timeframes: ${_snapshotOptions('timeframes_json').join(', ')}',
                      ),
                    ],
                    const SizedBox(height: 8),
                    PickerField(
                      label: 'Test date',
                      text: _dateText(),
                      onTap: () async {
                        final value = await pickDate(context, _testedAt);
                        if (value != null) setState(() => _testedAt = value);
                      },
                    ),
                  ],
                ),
                SectionCard(
                  title: 'Chart screenshots',
                  trailing: TextButton.icon(
                    onPressed: _importScreenshots,
                    icon: const Icon(Icons.add_photo_alternate_outlined,
                        size: 18),
                    label: const Text('Import'),
                  ),
                  children: [
                    const Text(
                      'Select saved screenshots from Research. Images are visual evidence only; no OHLC data or automatic outcomes are inferred.',
                    ),
                    const SizedBox(height: 10),
                    gallery.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (error, _) =>
                          Text('Could not load screenshots: $error'),
                      data: (images) {
                        if (images.isEmpty) {
                          return const EmptyState(
                            'No screenshots yet. Import charts to the Research gallery first.',
                          );
                        }
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: images.length,
                          itemBuilder: (_, index) {
                            final image = images[index];
                            final id = image.s('id');
                            final selected = _imageIds.contains(id);
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                ImageThumb(
                                  image: image,
                                  onTap: () => _setImageSelected(id, !selected),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: Checkbox(
                                    value: selected,
                                    onChanged: (value) =>
                                        _setImageSelected(id, value == true),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text('${_imageIds.length} screenshot(s) selected'),
                  ],
                ),
                if (selectedImages.isNotEmpty)
                  SectionCard(
                    title: 'Mark chart observations',
                    children: [
                      const Text(
                        'Choose a mark, then tap the chart. Zoom and pan with pinch and drag. Screenshot position is saved; price is only recorded when you enter it.',
                      ),
                      const SizedBox(height: 8),
                      ChoiceRow(
                        label: 'Mark type',
                        options: visualAnnotationKinds,
                        value: _annotationKind,
                        onChanged: (value) =>
                            setState(() => _annotationKind = value),
                      ),
                      for (final image in selectedImages) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: Text(
                            image.sn('caption') ??
                                image.sn('instrument') ??
                                'Chart screenshot',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        _AnnotatedChart(
                          image: image,
                          annotations:
                              _annotations[image.s('id')] ?? const <Rec>[],
                          onTapAt: (x, y) => _addAnnotation(
                            image.s('id'),
                            x,
                            y,
                          ),
                        ),
                        if ((_annotations[image.s('id')] ?? []).isNotEmpty)
                          for (var index = 0;
                              index < _annotations[image.s('id')]!.length;
                              index++)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                _annotationIcon(
                                    _annotations[image.s('id')]![index]
                                        .s('kind')),
                              ),
                              title: Text(_annotationTitle(
                                  _annotations[image.s('id')]![index])),
                              trailing: IconButton(
                                tooltip: 'Remove mark',
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(
                                  () => _annotations[image.s('id')]!
                                      .removeAt(index),
                                ),
                              ),
                            ),
                      ],
                    ],
                  ),
                SectionCard(
                  title: 'Manual outcome',
                  children: [
                    const Text(
                      'Record only what you observed while testing. A pending or inconclusive test is excluded from wins/losses and R statistics.',
                    ),
                    ChoiceRow(
                      label: 'Outcome',
                      options: visualOutcomes,
                      value: _outcome,
                      allowClear: false,
                      onChanged: (value) =>
                          setState(() => _outcome = value ?? _outcome),
                    ),
                    LabeledField(
                      controller: _rMultiple,
                      label: 'Result in R (optional)',
                      hint: 'For example, 1.5 or -1',
                      helperText:
                          'Enter a manually determined result; leave blank when unknown.',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                    ),
                    LabeledField(
                      controller: _notes,
                      label: 'Test notes',
                      minLines: 2,
                      maxLines: 8,
                    ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving...' : 'Save visual test'),
                ),
              ],
            ),
    );
  }
}

String _annotationTitle(Rec annotation) {
  final label = annotation.sn('label') ?? pretty(annotation.sn('kind'));
  final price = annotation['price'];
  return price is num ? '$label · ${numToText(price.toDouble())}' : label;
}

IconData _annotationIcon(String kind) {
  switch (kind) {
    case 'entry':
      return Icons.login;
    case 'stop_loss':
      return Icons.stop_circle_outlined;
    case 'take_profit':
      return Icons.flag_outlined;
    case 'exit':
      return Icons.logout;
    default:
      return Icons.notes_outlined;
  }
}

class _AnnotatedChart extends ConsumerWidget {
  const _AnnotatedChart({
    required this.image,
    required this.annotations,
    required this.onTapAt,
  });

  final Rec image;
  final List<Rec> annotations;
  final ValueChanged2<double, double> onTapAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relativePath = image.sn('local_path');
    if (relativePath == null) {
      return const SizedBox(
        height: 220,
        child: EmptyState('This screenshot is not stored on this device.'),
      );
    }
    final file = File(ref.read(imageStoreProvider).absolutePath(relativePath));
    final sourceWidth = image.d('width') ?? 0;
    final sourceHeight = image.d('height') ?? 0;
    final aspectRatio = sourceWidth > 0 && sourceHeight > 0
        ? sourceWidth / sourceHeight
        : 16 / 9;

    return LayoutBuilder(
      builder: (context, constraints) {
        const viewportHeight = 360.0;
        final displayScale = math.min(
          constraints.maxWidth / 1000,
          viewportHeight / (1000 / aspectRatio),
        );
        final width = 1000 * displayScale;
        final height = width / aspectRatio;
        return Center(
          child: SizedBox(
            height: viewportHeight,
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 6,
              boundaryMargin: const EdgeInsets.all(60),
              constrained: false,
              child: SizedBox(
                width: width,
                height: height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) => onTapAt(
                    (details.localPosition.dx / width).clamp(0.0, 1.0),
                    (details.localPosition.dy / height).clamp(0.0, 1.0),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        file,
                        fit: BoxFit.fill,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: Colors.black12,
                          child: Center(
                              child: Text('Screenshot file is unavailable.')),
                        ),
                      ),
                      CustomPaint(
                        painter: _AnnotationPainter(annotations),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

typedef ValueChanged2<T, U> = void Function(T first, U second);

class _AnnotationPainter extends CustomPainter {
  const _AnnotationPainter(this.annotations);

  final List<Rec> annotations;

  @override
  void paint(Canvas canvas, Size size) {
    for (final annotation in annotations) {
      final kind = annotation.s('kind');
      final x = (annotation['x'] as num?)?.toDouble() ?? 0;
      final y = (annotation['y'] as num?)?.toDouble() ?? 0;
      final color = switch (kind) {
        'entry' => const Color(0xFF22C55E),
        'stop_loss' => const Color(0xFFEF4444),
        'take_profit' => const Color(0xFF3B82F6),
        'exit' => const Color(0xFFF59E0B),
        _ => const Color(0xFFFFFFFF),
      };
      final position = Offset(x * size.width, y * size.height);
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      if (kind == 'observation') {
        canvas.drawCircle(position, 8, paint);
        canvas.drawLine(
          position - const Offset(5, 5),
          position + const Offset(5, 5),
          paint,
        );
        canvas.drawLine(
          position + const Offset(-5, 5),
          position + const Offset(5, -5),
          paint,
        );
      } else {
        canvas.drawLine(
          Offset(0, position.dy),
          Offset(size.width, position.dy),
          paint,
        );
      }
      final rawLabel = annotation.sn('label') ?? pretty(kind);
      final price = annotation['price'];
      final label =
          price is num ? '$rawLabel ${numToText(price.toDouble())}' : rawLabel;
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white,
            backgroundColor: color.withAlpha(210),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      painter.paint(
        canvas,
        Offset(
          kind == 'observation' ? position.dx + 10 : 4,
          (position.dy - painter.height - 2)
              .clamp(0, size.height - painter.height),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) =>
      oldDelegate.annotations != annotations;
}
