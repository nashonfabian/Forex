import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/repositories/notes_repository.dart';
import '../../widgets/common.dart';
import '../notes/note_editor_screen.dart';
import '../notes/notes_tab.dart';
import '../shared/link_navigation.dart';

class LessonDetailScreen extends ConsumerWidget {
  const LessonDetailScreen({super.key, required this.lessonId});

  final String lessonId;

  Future<void> _logTime(BuildContext context, WidgetRef ref) async {
    final minutes = TextEditingController();
    final focus = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log study time'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LabeledField(controller: minutes, label: 'Minutes', keyboardType: TextInputType.number),
            LabeledField(controller: focus, label: 'What did you focus on? (optional)'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    final value = int.tryParse(minutes.text.trim());
    if (ok == true && value != null && value > 0) {
      await ref
          .read(learningRepositoryProvider)
          .logSession(lessonId: lessonId, minutes: value, focus: emptyToNull(focus.text));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lessonProvider(lessonId));
    final minutes = ref.watch(lessonMinutesProvider(lessonId)).valueOrNull ?? 0;
    final notes = ref.watch(notesProvider(NoteFilter(lessonId: lessonId))).valueOrNull ?? const <Rec>[];

    return async.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(), body: EmptyState('$e')),
      data: (l) {
        if (l == null) return Scaffold(appBar: AppBar(), body: const EmptyState('This lesson no longer exists.'));
        final status = l.s('status', 'not_started');
        final dayNo = l.iN('day_no');
        return Scaffold(
          appBar: AppBar(title: Text(dayNo == null ? 'Lesson' : 'Day $dayNo')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(l.s('title'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text([
                if (l.sn('phase_title') != null) l.s('phase_title'),
                if (l.sn('scheduled_date') != null) formatYmd(l.sn('scheduled_date')),
              ].join('  |  ')),
              const SizedBox(height: 12),
              SectionCard(
                title: 'Objective',
                children: [
                  Text(l.s('objective', 'No objective written yet.')),
                  if (l.sn('assignment') != null) ...[
                    const SizedBox(height: 10),
                    InfoLine('Assignment', l.sn('assignment')),
                  ],
                ],
              ),
              SectionCard(
                title: 'Progress',
                children: [
                  ChoiceRow(
                    label: 'Status',
                    options: const ['not_started', 'in_progress', 'completed'],
                    value: status,
                    allowClear: false,
                    onChanged: (v) {
                      if (v != null) ref.read(learningRepositoryProvider).setLessonStatus(lessonId, v);
                    },
                  ),
                  Row(
                    children: [
                      Expanded(child: Text('Time logged: $minutes min')),
                      OutlinedButton.icon(
                        onPressed: () => _logTime(context, ref),
                        icon: const Icon(Icons.timer_outlined, size: 18),
                        label: const Text('Log time'),
                      ),
                    ],
                  ),
                ],
              ),
              SectionCard(
                title: 'Notes for this lesson',
                trailing: TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(lessonId: lessonId)),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
                children: [
                  if (notes.isEmpty) const Text('No notes yet.'),
                  for (final n in notes)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(noteKindIcon(n.s('kind', 'note'))),
                      title: Text(n.sn('title') ?? n.s('body_md'), maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(noteId: n.s('id'))),
                      ),
                    ),
                ],
              ),
              LinkedItemsCard(
                entityType: 'lessons',
                entityId: lessonId,
                actions: [
                  OutlinedButton.icon(
                    onPressed: () => linkToCase(context, ref, 'lessons', lessonId),
                    icon: const Icon(Icons.insights_outlined, size: 18),
                    label: const Text('Chart case'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}
