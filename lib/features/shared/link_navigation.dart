import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/repositories/meta_repository.dart';
import '../../data/repositories/notes_repository.dart';
import '../../data/repositories/research_repository.dart';
import '../../data/repositories/trades_repository.dart';
import '../../widgets/common.dart';
import '../learn/lesson_detail_screen.dart';
import '../notes/note_editor_screen.dart';
import '../research/case_detail_screen.dart';
import '../research/image_viewer_screen.dart';
import '../trades/trade_form_screen.dart';

IconData linkIcon(String type) {
  switch (type) {
    case 'research_cases':
      return Icons.insights_outlined;
    case 'lessons':
      return Icons.school_outlined;
    case 'notes':
      return Icons.sticky_note_2_outlined;
    case 'trades':
      return Icons.show_chart;
    case 'images':
      return Icons.image_outlined;
  }
  return Icons.link;
}

String linkTypeLabel(String type) {
  switch (type) {
    case 'research_cases':
      return 'Case';
    case 'lessons':
      return 'Lesson';
    case 'notes':
      return 'Note';
    case 'trades':
      return 'Trade';
    case 'images':
      return 'Screenshot';
  }
  return type;
}

void openLinked(BuildContext context, LinkedItem item) {
  Widget? page;
  switch (item.type) {
    case 'research_cases':
      page = CaseDetailScreen(caseId: item.id);
      break;
    case 'lessons':
      page = LessonDetailScreen(lessonId: item.id);
      break;
    case 'notes':
      page = NoteEditorScreen(noteId: item.id);
      break;
    case 'trades':
      page = TradeFormScreen(tradeId: item.id);
      break;
    case 'images':
      page = ImageViewerScreen(imageIds: [item.id], initialIndex: 0);
      break;
  }
  if (page != null) {
    final target = page;
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => target));
  }
}

Future<void> linkToCase(BuildContext context, WidgetRef ref, String type, String id) async {
  final cases = await ref.read(researchRepositoryProvider).listCases(const CaseFilter());
  if (!context.mounted) return;
  final chosen = await pickRec(
    context,
    title: 'Link a research case',
    items: cases,
    label: (c) => c.s('title', 'Untitled'),
    subtitle: (c) => [c.sn('instrument'), c.sn('timeframe')].whereType<String>().join(' | '),
  );
  if (chosen == null) return;
  await ref.read(linksRepositoryProvider).link(type, id, 'research_cases', chosen.s('id'));
}

Future<void> linkToLesson(BuildContext context, WidgetRef ref, String type, String id) async {
  final plan = await ref.read(learningRepositoryProvider).activePlan();
  if (plan == null) {
    if (context.mounted) snack(context, 'Start the programme first (Learn tab).');
    return;
  }
  final lessons = await ref.read(learningRepositoryProvider).lessonsForPlan(plan.s('id'));
  if (!context.mounted) return;
  final chosen = await pickRec(
    context,
    title: 'Link a lesson',
    items: lessons,
    label: (l) => '${l.iN('day_no') == null ? '' : 'Day ${l.i('day_no')} - '}${l.s('title')}',
  );
  if (chosen == null) return;
  await ref.read(linksRepositoryProvider).link(type, id, 'lessons', chosen.s('id'));
}

Future<void> linkToNote(BuildContext context, WidgetRef ref, String type, String id) async {
  final notes = await ref.read(notesRepositoryProvider).list(const NoteFilter());
  if (!context.mounted) return;
  final chosen = await pickRec(
    context,
    title: 'Link a note',
    items: notes,
    label: (n) => n.sn('title') ?? n.s('body_md', 'Note'),
    subtitle: (n) => pretty(n.s('kind')),
  );
  if (chosen == null) return;
  await ref.read(linksRepositoryProvider).link(type, id, 'notes', chosen.s('id'));
}

Future<void> linkToTrade(BuildContext context, WidgetRef ref, String type, String id) async {
  final trades = await ref.read(tradesRepositoryProvider).list(const TradeFilter());
  if (!context.mounted) return;
  final chosen = await pickRec(
    context,
    title: 'Link a trade',
    items: trades,
    label: (t) => '${t.s('instrument')} ${t.s('direction')}',
    subtitle: (t) => '${pretty(t.s('account_type'))} account',
  );
  if (chosen == null) return;
  await ref.read(linksRepositoryProvider).link(type, id, 'trades', chosen.s('id'));
}

/// "Linked records" card with remove buttons and the given "Link ..." actions.
class LinkedItemsCard extends ConsumerWidget {
  const LinkedItemsCard({super.key, required this.entityType, required this.entityId, required this.actions});

  final String entityType;
  final String entityId;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(linkedProvider('$entityType|$entityId')).valueOrNull ?? const <LinkedItem>[];
    return SectionCard(
      title: 'Linked records',
      children: [
        if (items.isEmpty) const Text('Nothing linked yet.'),
        for (final item in items)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(linkIcon(item.type)),
            title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(linkTypeLabel(item.type)),
            onTap: () => openLinked(context, item),
            trailing: IconButton(
              tooltip: 'Remove link',
              icon: const Icon(Icons.link_off),
              onPressed: () => ref.read(linksRepositoryProvider).unlink(item.linkId),
            ),
          ),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 4, children: actions),
      ],
    );
  }
}
