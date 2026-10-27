import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/repositories/research_repository.dart';
import '../../data/repositories/trades_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/image_thumb.dart';
import '../shared/link_navigation.dart';
import '../trades/trade_form_screen.dart';
import 'case_form_screen.dart';
import 'image_import.dart';
import 'image_viewer_screen.dart';

class CaseDetailScreen extends ConsumerWidget {
  const CaseDetailScreen({super.key, required this.caseId});

  final String caseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(caseProvider(caseId));
    return async.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(), body: EmptyState('$e')),
      data: (c) => c == null
          ? Scaffold(appBar: AppBar(), body: const EmptyState('This case no longer exists.'))
          : _CaseView(c: c),
    );
  }
}

class _CaseView extends ConsumerWidget {
  const _CaseView({required this.c});

  final Rec c;

  String get id => c.s('id');
  bool get locked => c.sn('hypothesis_locked_at') != null;
  bool get draft => c.s('status', 'draft') == 'draft';

  Future<void> _lock(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Lock this hypothesis?',
      message: 'Locking is permanent. The text is kept exactly as written so you can compare it '
          'honestly with what happens. Later thoughts go in as addenda.',
      confirmLabel: 'Lock it',
    );
    if (!ok) return;
    try {
      await ref.read(researchRepositoryProvider).lockHypothesis(id);
    } catch (e) {
      if (context.mounted) snack(context, friendlyError(e));
    }
  }

  Future<void> _addEntry(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    var phase = 'during';
    final kind = locked ? 'addendum' : 'observation';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(locked ? 'Add an addendum' : 'Add an observation'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ChoiceRow(
                  label: 'Phase',
                  options: imagePhases,
                  value: phase,
                  allowClear: false,
                  onChanged: (v) => setDialog(() => phase = v ?? phase),
                ),
                LabeledField(controller: controller, label: 'Text', minLines: 3, maxLines: 8),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      await ref
          .read(researchRepositoryProvider)
          .addEntry(id, phase: phase, kind: kind, body: controller.text.trim());
    }
  }

  Future<void> _recordOutcome(BuildContext context, WidgetRef ref) async {
    String? outcome = c.sn('outcome');
    String? verdict = c.sn('hypothesis_verdict');
    final summary = TextEditingController(text: c.s('outcome_summary'));
    final lessons = TextEditingController(text: c.s('final_lessons'));

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Record the outcome', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text('Your original hypothesis stays exactly as you locked it.'),
                const SizedBox(height: 12),
                ChoiceRow(
                  label: 'What happened',
                  options: caseOutcomes,
                  value: outcome,
                  allowClear: false,
                  onChanged: (v) => setSheet(() => outcome = v),
                ),
                ChoiceRow(
                  label: 'Was the hypothesis supported?',
                  options: hypothesisVerdicts,
                  value: verdict,
                  onChanged: (v) => setSheet(() => verdict = v),
                ),
                LabeledField(controller: summary, label: 'Summary of the outcome', minLines: 2, maxLines: 6),
                LabeledField(controller: lessons, label: 'Final lessons', minLines: 2, maxLines: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save outcome')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final chosen = outcome;
    if (ok != true) return;
    if (chosen == null) {
      if (context.mounted) snack(context, 'Choose what happened.');
      return;
    }
    try {
      await ref.read(researchRepositoryProvider).recordOutcome(
            id,
            outcome: chosen,
            verdict: verdict,
            summary: emptyToNull(summary.text),
            lessons: emptyToNull(lessons.text),
          );
    } catch (e) {
      if (context.mounted) snack(context, friendlyError(e));
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    snack(context, 'Building the PDF...');
    try {
      final file = await ref.read(caseReportProvider).build(id);
      await Share.shareXFiles([XFile(file.path)], text: c.s('title'));
    } catch (e) {
      if (context.mounted) snack(context, 'Could not build the PDF: ${friendlyError(e)}');
    }
  }

  Future<void> _deleteDraft(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete this draft?',
      message: 'Only drafts can be deleted. Locked cases are kept as evidence.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(researchRepositoryProvider).deleteDraft(id);
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) snack(context, friendlyError(e));
    }
  }

  void _openViewer(BuildContext context, List<Rec> images, int index) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ImageViewerScreen(
          imageIds: images.map((i) => i.s('id')).toList(),
          initialIndex: index,
        ),
      ),
    );
  }

  Widget _phaseImages(BuildContext context, WidgetRef ref, String phase, List<Rec> all) {
    final mine = all.where((i) => (phase == 'other' ? !imagePhases.contains(i.sn('phase')) : i.sn('phase') == phase)).toList();
    if (phase == 'other' && mine.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(pretty(phase == 'other' ? 'unsorted' : phase),
                    style: Theme.of(context).textTheme.labelLarge)),
            if (phase != 'other')
              TextButton.icon(
                onPressed: () => pickAndImport(context, ref, caseId: id, phase: phase),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('Add'),
              ),
          ],
        ),
        if (mine.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('No screenshots yet.', style: Theme.of(context).textTheme.bodySmall),
          )
        else
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: mine.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ImageThumb(
                image: mine[i],
                size: 92,
                onTap: () => _openViewer(context, all, all.indexWhere((x) => x.s('id') == mine[i].s('id'))),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final images = ref.watch(caseImagesProvider(id)).valueOrNull ?? const <Rec>[];
    final entries = ref.watch(caseEntriesProvider(id)).valueOrNull ?? const <Rec>[];
    final tags = ref.watch(tagNamesProvider('research_cases|$id')).valueOrNull ?? const <String>[];
    final allTrades = ref.watch(tradesProvider(const TradeFilter())).valueOrNull ?? const <Rec>[];
    final trades = allTrades.where((t) => t.s('case_id') == id).toList();
    final outcome = c.sn('outcome');

    return Scaffold(
      appBar: AppBar(
        title: Text(c.s('title', 'Case'), overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => CaseFormScreen(caseId: id)),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') _export(context, ref);
              if (v == 'delete') _deleteDraft(context, ref);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'pdf', child: Text('Export as PDF')),
              if (draft) const PopupMenuItem(value: 'delete', child: Text('Delete draft')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (c.sn('instrument') != null) Chip(label: Text(c.s('instrument'))),
              if (c.sn('timeframe') != null) Chip(label: Text(c.s('timeframe'))),
              if (c.sn('market_condition') != null) Chip(label: Text(pretty(c.s('market_condition')))),
              Chip(
                avatar: Icon(locked ? Icons.lock : Icons.edit_note, size: 16),
                label: Text(outcome != null ? pretty(outcome) : (locked ? 'Awaiting outcome' : 'Draft')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Setup',
            children: [
              InfoLine('Observed', formatLocalDateTime(c.sn('observed_at'))),
              InfoLine('Reference level / value area', c.sn('reference_level')),
              InfoLine('Direction of exploration', pretty(c.sn('exploration_direction'))),
              InfoLine('Tags', tags.isEmpty ? null : tags.join(', ')),
            ],
          ),
          SectionCard(
            title: 'Hypothesis',
            trailing: locked ? const Icon(Icons.lock_outline, size: 18) : null,
            children: [
              if (locked)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Locked ${formatLocalDateTime(c.sn('hypothesis_locked_at'))}. '
                    'This is your original reasoning, kept exactly as written.',
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Draft. You can still edit it.')),
                      FilledButton.icon(
                        onPressed: () => _lock(context, ref),
                        icon: const Icon(Icons.lock_outline, size: 18),
                        label: const Text('Lock'),
                      ),
                    ],
                  ),
                ),
              InfoLine('Hypothesis', c.sn('hypothesis')),
              InfoLine('Evidence supporting', c.sn('evidence_for')),
              InfoLine('Evidence contradicting', c.sn('evidence_against')),
              InfoLine('Acceptance / rejection', c.sn('acceptance_rejection')),
              InfoLine('Alternative scenarios', c.sn('alternatives')),
              InfoLine('Invalidation', c.sn('invalidation')),
              InfoLine('Confidence', c.iN('confidence') == null ? null : '${c.i('confidence')} / 5'),
            ],
          ),
          SectionCard(
            title: 'Screenshots',
            children: [
              for (final phase in imagePhases) _phaseImages(context, ref, phase, images),
              _phaseImages(context, ref, 'other', images),
            ],
          ),
          SectionCard(
            title: 'Observations and addenda',
            trailing: TextButton.icon(
              onPressed: () => _addEntry(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: Text(locked ? 'Addendum' : 'Observation'),
            ),
            children: [
              if (entries.isEmpty) const Text('Nothing added yet.'),
              for (final e in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${pretty(e.s('kind'))} | ${e.s('phase')} | ${formatLocalDateTime(e.sn('created_at'))}',
                        style: theme.textTheme.labelSmall,
                      ),
                      Text(e.s('body')),
                    ],
                  ),
                ),
            ],
          ),
          SectionCard(
            title: 'Outcome',
            children: [
              if (!locked)
                const Text('Lock the hypothesis first, then record what happened.')
              else if (outcome == null)
                FilledButton(
                  onPressed: () => _recordOutcome(context, ref),
                  child: const Text('Record outcome'),
                )
              else ...[
                InfoLine('What happened', pretty(outcome)),
                InfoLine('Hypothesis verdict', pretty(c.sn('hypothesis_verdict'))),
                InfoLine('Recorded', formatLocalDateTime(c.sn('outcome_at'))),
                InfoLine('Summary', c.sn('outcome_summary')),
                InfoLine('Final lessons', c.sn('final_lessons')),
                OutlinedButton(
                  onPressed: () => _recordOutcome(context, ref),
                  child: const Text('Edit outcome'),
                ),
              ],
            ],
          ),
          if (trades.isNotEmpty)
            SectionCard(
              title: 'Trades from this case',
              children: [
                for (final t in trades)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.show_chart),
                    title: Text('${t.s('instrument')} ${t.s('direction')}'),
                    subtitle: Text('${pretty(t.s('account_type'))} | ${pretty(t.s('status'))}'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => TradeFormScreen(tradeId: t.s('id'))),
                    ),
                  ),
              ],
            ),
          LinkedItemsCard(
            entityType: 'research_cases',
            entityId: id,
            actions: [
              OutlinedButton.icon(
                onPressed: () => linkToLesson(context, ref, 'research_cases', id),
                icon: const Icon(Icons.school_outlined, size: 18),
                label: const Text('Lesson'),
              ),
              OutlinedButton.icon(
                onPressed: () => linkToNote(context, ref, 'research_cases', id),
                icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
                label: const Text('Note'),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
