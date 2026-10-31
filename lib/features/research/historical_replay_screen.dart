import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../widgets/common.dart';
import 'case_form_screen.dart';

class HistoricalReplayScreen extends ConsumerStatefulWidget {
  const HistoricalReplayScreen({super.key});

  @override
  ConsumerState<HistoricalReplayScreen> createState() => _HistoricalReplayScreenState();
}

class _HistoricalReplayScreenState extends ConsumerState<HistoricalReplayScreen> {
  final _instrumentController = TextEditingController(text: 'XAUUSD');
  final _timeframeController = TextEditingController(text: 'M1');
  final _sourceController = TextEditingController(text: 'CSV import');

  List<Rec> _datasets = const [];
  String? _datasetId;
  String? _sessionId;
  List<Rec> _visibleCandles = const [];
  int _selectedIndex = -1;
  bool _playing = false;
  bool _busy = false;
  double _speed = 1;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadDatasets();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _instrumentController.dispose();
    _timeframeController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  Future<void> _loadDatasets() async {
    final repo = ref.read(historicalDataRepositoryProvider);
    final datasets = await repo.datasets();
    if (!mounted) return;
    setState(() {
      _datasets = datasets;
      if (_datasetId == null && datasets.isNotEmpty) {
        _datasetId = datasets.first['id'] as String;
      }
    });
    if (_datasetId != null) {
      await _loadVisibleCandles();
    }
  }

  Future<void> _importCsv() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final picker = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    final path = picker?.files.single.path;
    if (path == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final csv = await File(path).readAsString();
      final repo = ref.read(historicalDataRepositoryProvider);
      final result = await repo.importCsv(
        csv: csv,
        instrument: _instrumentController.text,
        timeframe: _timeframeController.text,
        sourceName: _sourceController.text,
      );
      if (!mounted) return;
      if (result.imported && result.datasetId != null) {
        setState(() {
          _datasetId = result.datasetId;
        });
        await _loadDatasets();
        messenger?.showSnackBar(const SnackBar(content: Text('Imported historical dataset.')));
      } else {
        final message = result.validation.errors.isEmpty
            ? 'CSV import failed.'
            : result.validation.errors.map((e) => e.toString()).join('\n');
        messenger?.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text('Could not import CSV: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createSession() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final datasetId = _datasetId;
    if (datasetId == null) return;

    setState(() => _busy = true);
    try {
      final repo = ref.read(historicalDataRepositoryProvider);
      final selected = _datasets.firstWhere((row) => row['id'] == datasetId);
      final startMs = selected['first_timestamp_ms'] as int? ?? 0;
      final sessionId = await repo.createReplaySession(
        datasetId: datasetId,
        requestedStartTimestampMs: startMs,
        speedCandlesPerSecond: _speed,
      );
      if (!mounted) return;
      setState(() {
        _sessionId = sessionId;
        _playing = false;
      });
      await _loadVisibleCandles();
      messenger?.showSnackBar(const SnackBar(content: Text('Replay session started.')));
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text('Could not start replay: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadVisibleCandles() async {
    final sessionId = _sessionId;
    if (sessionId == null) {
      if (mounted) {
        setState(() {
          _visibleCandles = const [];
          _selectedIndex = -1;
        });
      }
      return;
    }
    final repo = ref.read(historicalDataRepositoryProvider);
    final candles = await repo.visibleCandles(sessionId, limit: 200);
    if (!mounted) return;
    setState(() {
      _visibleCandles = candles;
      _selectedIndex = candles.isEmpty ? -1 : candles.length - 1;
    });
  }

  Future<void> _advanceReplay({required bool forward}) async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    final repo = ref.read(historicalDataRepositoryProvider);
    final candle = await repo.stepReplay(sessionId, forward: forward);
    if (!mounted) return;
    if (candle == null) {
      snack(context, forward ? 'No later candle is available yet.' : 'Replay is already at the start.');
      return;
    }
    await _loadVisibleCandles();
  }

  void _togglePlay() {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    if (_playing) {
      _timer?.cancel();
      setState(() => _playing = false);
      return;
    }

    setState(() => _playing = true);
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: (1000 / _speed).round()), (_) {
      if (!mounted) return;
      unawaited(_advanceReplay(forward: true));
    });
  }

  Future<void> _restartReplay() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    final repo = ref.read(historicalDataRepositoryProvider);
    final session = await repo.replaySession(sessionId);
    final startMs = session == null ? null : session['start_timestamp_ms'] as int?;
    if (startMs == null) return;
    await repo.saveReplayCursor(sessionId, startMs);
    await _loadVisibleCandles();
  }

  Future<void> _setSpeed(double speed) async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    setState(() => _speed = speed);
    final repo = ref.read(historicalDataRepositoryProvider);
    await repo.saveReplaySpeed(sessionId, speed);
    if (_playing) {
      _timer?.cancel();
      _timer = Timer.periodic(Duration(milliseconds: (1000 / speed).round()), (_) {
        if (!mounted) return;
        unawaited(_advanceReplay(forward: true));
      });
    }
  }

  Rec? get _selectedCandle =>
      _selectedIndex >= 0 && _selectedIndex < _visibleCandles.length ? _visibleCandles[_selectedIndex] : null;

  String _formatTimestamp(Object? value) {
    final stamp = value is int ? value : 0;
    final date = DateTime.fromMillisecondsSinceEpoch(stamp, isUtc: true).toLocal();
    return date.toString().replaceFirst(' ', '  ');
  }

  @override
  Widget build(BuildContext context) {
    final dataset = _datasets.firstWhere(
      (row) => row['id'] == _datasetId,
      orElse: () => const <String, Object?>{},
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Historical replay')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Import historical CSV', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _instrumentController,
                          decoration: const InputDecoration(labelText: 'Instrument', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _timeframeController,
                          decoration: const InputDecoration(labelText: 'Timeframe', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _sourceController,
                    decoration: const InputDecoration(labelText: 'Source', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _importCsv,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Import CSV'),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Dataset', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_datasets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('No historical dataset is imported yet.'),
                    )
                  else
                    ..._datasets.map((row) {
                      final id = row['id'] as String;
                      final instrument = row['instrument'] as String? ?? 'UNKNOWN';
                      final timeframe = row['timeframe'] as String? ?? 'N/A';
                      return RadioListTile<String>(
                        value: id,
                        groupValue: _datasetId,
                        onChanged: (value) => setState(() => _datasetId = value),
                        title: Text('$instrument / $timeframe'),
                        subtitle: Text('Candles: ${row['candle_count']}'),
                      );
                    }),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy || _datasetId == null ? null : _createSession,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Create replay session'),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Replay controls', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      IconButton.filled(
                        onPressed: _sessionId == null ? null : () => unawaited(_advanceReplay(forward: false)),
                        icon: const Icon(Icons.skip_previous),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _sessionId == null ? null : _togglePlay,
                        icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _sessionId == null ? null : () => unawaited(_advanceReplay(forward: true)),
                        icon: const Icon(Icons.skip_next),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: _sessionId == null ? null : _restartReplay,
                        child: const Text('Restart'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: _selectedCandle == null
                            ? null
                            : () {
                                final stamp = _selectedCandle!['timestamp_ms'] as int? ?? 0;
                                final observedAt = DateTime.fromMillisecondsSinceEpoch(stamp, isUtc: true).toLocal();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => CaseFormScreen(
                                      initialInstrument: _instrumentController.text.trim().isEmpty
                                          ? 'XAUUSD'
                                          : _instrumentController.text.trim(),
                                      initialTimeframe: _timeframeController.text.trim().isEmpty
                                          ? 'M1'
                                          : _timeframeController.text.trim(),
                                      initialObservedAt: observedAt,
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.note_add_outlined),
                        label: const Text('Research case'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Speed:'),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Slider(
                          min: 1,
                          max: 8,
                          divisions: 7,
                          value: _speed,
                          onChanged: (value) => unawaited(_setSpeed(value)),
                        ),
                      ),
                      Text('${_speed.toStringAsFixed(0)}x'),
                    ],
                  ),
                  if (dataset.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Selected dataset: ${dataset['instrument']} · ${dataset['timeframe']} · ${dataset['candle_count']} candles',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Replay chart', style: TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (_selectedCandle != null)
                        Text(
                          _formatTimestamp(_selectedCandle!['timestamp_ms']),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_visibleCandles.isEmpty)
                    const Text('No candles are visible yet. Create a replay session to begin.')
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final candles = _visibleCandles;
                        final yMin = candles.map((c) => (c['low'] as num?)?.toDouble() ?? 0).reduce((a, b) => a < b ? a : b);
                        final yMax = candles.map((c) => (c['high'] as num?)?.toDouble() ?? 0).reduce((a, b) => a > b ? a : b);
                        final range = (yMax - yMin).abs() < 0.0001 ? 1.0 : (yMax - yMin).abs();
                        final padding = range * 0.12;
                        final minY = yMin - padding;
                        final maxY = yMax + padding;
                        return GestureDetector(
                          onTapDown: (details) {
                            final index = ((details.localPosition.dx / constraints.maxWidth) * candles.length).round();
                            final clamped = index.clamp(0, candles.length - 1);
                            setState(() => _selectedIndex = clamped);
                          },
                          child: SizedBox(
                            height: 280,
                            child: CustomPaint(
                              painter: _HistoricalCandlesPainter(
                                candles: candles,
                                selectedIndex: _selectedIndex,
                                minY: minY,
                                maxY: maxY,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        );
                      },
                    ),
                  if (_selectedCandle != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Selected candle', style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 4),
                          Text(
                            '${_formatTimestamp(_selectedCandle!['timestamp_ms'])}\n'
                            'O ${_selectedCandle!['open']}  H ${_selectedCandle!['high']}\n'
                            'L ${_selectedCandle!['low']}  C ${_selectedCandle!['close']}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoricalCandlesPainter extends CustomPainter {
  const _HistoricalCandlesPainter({
    required this.candles,
    required this.selectedIndex,
    required this.minY,
    required this.maxY,
  });

  final List<Rec> candles;
  final int selectedIndex;
  final double minY;
  final double maxY;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF101820);
    canvas.drawRect(Offset.zero & size, bg);

    final gridPaint = Paint()
      ..color = const Color(0xFF2A3744)
      ..style = PaintingStyle.stroke;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (candles.isEmpty) return;

    const chartLeft = 12.0;
    final chartRight = size.width - 12.0;
    const chartTop = 8.0;
    final chartBottom = size.height - 18.0;
    final chartWidth = chartRight - chartLeft;
    final chartHeight = chartBottom - chartTop;

    final selected = selectedIndex >= 0 && selectedIndex < candles.length ? candles[selectedIndex] : candles.last;
    final selectedTimestamp = selected['timestamp_ms'] as int? ?? 0;
    final selectedX = chartLeft + (candles.indexOf(selected) / candles.length) * chartWidth;
    canvas.drawLine(
      Offset(selectedX, chartTop),
      Offset(selectedX, chartBottom),
      Paint()
        ..color = const Color(0xFF7DD3FC)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );

    final labelPainter = TextPainter(
      text: TextSpan(
        text: DateTime.fromMillisecondsSinceEpoch(selectedTimestamp, isUtc: true).toLocal().toString(),
        style: const TextStyle(color: Colors.white70, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(canvas, Offset(selectedX + 6, chartBottom + 2));

    for (var i = 0; i < candles.length; i++) {
      final candle = candles[i];
      final open = (candle['open'] as num?)?.toDouble() ?? 0;
      final high = (candle['high'] as num?)?.toDouble() ?? 0;
      final low = (candle['low'] as num?)?.toDouble() ?? 0;
      final close = (candle['close'] as num?)?.toDouble() ?? 0;

      final x = chartLeft + ((i / candles.length) * chartWidth) + (chartWidth / candles.length) * 0.33;
      final w = math.max(2.0, (chartWidth / candles.length) * 0.32);
      final bodyTop = chartTop + ((maxY - math.max(open, close)) / (maxY - minY)) * chartHeight;
      final bodyBottom = chartTop + ((maxY - math.min(open, close)) / (maxY - minY)) * chartHeight;
      final wickTop = chartTop + ((maxY - high) / (maxY - minY)) * chartHeight;
      final wickBottom = chartTop + ((maxY - low) / (maxY - minY)) * chartHeight;

      canvas.drawLine(
        Offset(x + w / 2, wickTop),
        Offset(x + w / 2, wickBottom),
        Paint()..color = const Color(0xFFD1FAE5)..strokeWidth = 1,
      );
      final bodyColor = close >= open ? const Color(0xFF4ADE80) : const Color(0xFFF87171);
      canvas.drawRect(
        Rect.fromLTWH(x, bodyTop, w, math.max(2.0, bodyBottom - bodyTop)),
        Paint()..color = bodyColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HistoricalCandlesPainter oldDelegate) {
    return oldDelegate.candles != candles || oldDelegate.selectedIndex != selectedIndex;
  }
}
