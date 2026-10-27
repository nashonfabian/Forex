import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/repositories/research_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/image_thumb.dart';
import 'case_detail_screen.dart';
import 'case_form_screen.dart';
import 'image_import.dart';
import 'image_viewer_screen.dart';

class ResearchScreen extends StatelessWidget {
  const ResearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(tabs: [Tab(text: 'Cases'), Tab(text: 'Gallery')]),
          Expanded(child: TabBarView(children: [_CasesTab(), _GalleryTab()])),
        ],
      ),
    );
  }
}

// =====================================================================
class _CasesTab extends ConsumerStatefulWidget {
  const _CasesTab();

  @override
  ConsumerState<_CasesTab> createState() => _CasesTabState();
}

class _CasesTabState extends ConsumerState<_CasesTab> {
  final _search = TextEditingController();
  CaseFilter _f = const CaseFilter();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  CaseFilter get _filter => CaseFilter(
        query: _search.text.trim(),
        instrument: _f.instrument,
        timeframe: _f.timeframe,
        condition: _f.condition,
        outcome: _f.outcome,
      );

  Future<void> _openFilters() async {
    final known = ref.read(instrumentsProvider).valueOrNull ?? const <String>[];
    final instruments = {...kInstrumentSuggestions, ...known}.toList();
    String? instrument = _f.instrument;
    String? timeframe = _f.timeframe;
    String? condition = _f.condition;
    String? outcome = _f.outcome;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filter cases', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                ChoiceRow(
                    label: 'Instrument',
                    options: instruments,
                    value: instrument,
                    onChanged: (v) => setSheet(() => instrument = v)),
                ChoiceRow(
                    label: 'Timeframe',
                    options: kTimeframes,
                    value: timeframe,
                    onChanged: (v) => setSheet(() => timeframe = v)),
                ChoiceRow(
                    label: 'Market condition',
                    options: marketConditions,
                    value: condition,
                    onChanged: (v) => setSheet(() => condition = v)),
                ChoiceRow(
                    label: 'Outcome',
                    options: const ['pending', ...caseOutcomes],
                    value: outcome,
                    onChanged: (v) => setSheet(() => outcome = v)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        instrument = null;
                        timeframe = null;
                        condition = null;
                        outcome = null;
                        Navigator.pop(ctx, true);
                      },
                      child: const Text('Clear'),
                    ),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (applied == true) {
      setState(() => _f = CaseFilter(
            instrument: instrument,
            timeframe: timeframe,
            condition: condition,
            outcome: outcome,
          ));
    }
  }

  String _statusLabel(Rec c) {
    final outcome = c.sn('outcome');
    if (outcome != null) return pretty(outcome);
    return c.sn('hypothesis_locked_at') != null ? 'Awaiting outcome' : 'Draft';
  }

  @override
  Widget build(BuildContext context) {
    final cases = ref.watch(casesProvider(_filter));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search cases',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Filters',
                onPressed: _openFilters,
                icon: Icon(_f.isActive ? Icons.filter_alt : Icons.filter_alt_outlined),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: FilledButton.tonalIcon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const CaseFormScreen()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('New case'),
            ),
          ),
        ),
        Expanded(
          child: cases.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => EmptyState('$e'),
            data: (items) {
              if (items.isEmpty) {
                return EmptyState(_filter.isActive
                    ? 'No cases match these filters.'
                    : 'No research cases yet.\nTap "New case" to record your first hypothesis.');
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final c = items[i];
                  final meta = [
                    c.sn('instrument'),
                    c.sn('timeframe'),
                    c.sn('market_condition') == null ? null : pretty(c.sn('market_condition')),
                    c.sn('observed_at') == null ? null : formatLocalDate(c.sn('observed_at')),
                  ].whereType<String>().join('  |  ');
                  final images = c.i('image_count');
                  return Card(
                    child: ListTile(
                      title: Text(c.s('title', 'Untitled'), maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (meta.isNotEmpty) Text(meta),
                          if (c.sn('tag_names') != null) Text(c.s('tag_names'), style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            children: [
                              Chip(
                                avatar: Icon(c.sn('hypothesis_locked_at') != null ? Icons.lock : Icons.edit_note, size: 14),
                                label: Text(_statusLabel(c)),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ],
                      ),
                      trailing: images > 0
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [const Icon(Icons.photo_outlined, size: 16), const SizedBox(width: 2), Text('$images')],
                            )
                          : null,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(builder: (_) => CaseDetailScreen(caseId: c.s('id'))),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// =====================================================================
class _GalleryTab extends ConsumerStatefulWidget {
  const _GalleryTab();

  @override
  ConsumerState<_GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends ConsumerState<_GalleryTab> {
  GalleryFilter _f = const GalleryFilter();

  @override
  Widget build(BuildContext context) {
    final images = ref.watch(galleryProvider(_f));
    final instruments = ref.watch(instrumentsProvider).valueOrNull ?? const <String>[];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FilterChip(
                    label: const Text('Inbox only'),
                    selected: _f.inboxOnly,
                    onSelected: (v) => setState(() => _f = GalleryFilter(
                        inboxOnly: v, instrument: _f.instrument, timeframe: _f.timeframe, phase: _f.phase)),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: () => pickAndImport(context, ref),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Import'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (instruments.isNotEmpty)
                ChoiceRow(
                  label: 'Instrument',
                  options: instruments,
                  value: _f.instrument,
                  onChanged: (v) => setState(() => _f = GalleryFilter(
                      inboxOnly: _f.inboxOnly, instrument: v, timeframe: _f.timeframe, phase: _f.phase)),
                ),
              ChoiceRow(
                label: 'Phase',
                options: imagePhases,
                value: _f.phase,
                onChanged: (v) => setState(() => _f = GalleryFilter(
                    inboxOnly: _f.inboxOnly, instrument: _f.instrument, timeframe: _f.timeframe, phase: v)),
              ),
            ],
          ),
        ),
        Expanded(
          child: images.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => EmptyState('$e'),
            data: (items) {
              if (items.isEmpty) {
                return const EmptyState(
                    'No screenshots here.\nImport screenshots from your gallery; file them into a case whenever you are ready.');
              }
              final ids = items.map((i) => i.s('id')).toList();
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) => ImageThumb(
                  image: items[i],
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => ImageViewerScreen(imageIds: ids, initialIndex: i)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
