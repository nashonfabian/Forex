import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clock.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../widgets/common.dart';
import '../learn/learn_screen.dart';

/// Edit the programme: change, add or remove lessons, or move the start date.
class CurriculumEditorScreen extends ConsumerWidget {
  const CurriculumEditorScreen({super.key});

  Future<void> _editLesson(BuildContext context, WidgetRef ref, String planId, Rec? lesson) async {
    final title = TextEditingController(text: lesson?.s('title') ?? '');
    final objective = TextEditingController(text: lesson?.s('objective') ?? '');
    final assignment = TextEditingController(text: lesson?.s('assignment') ?? '');
    final phaseNo = TextEditingController(text: lesson?.iN('phase_no')?.toString() ?? '');
    final phaseTitle = TextEditingController(text: lesson?.s('phase_title') ?? '');
    final weekNo = TextEditingController(text: lesson?.iN('week_no')?.toString() ?? '');
    final dayNo = TextEditingController(text: lesson?.iN('day_no')?.toString() ?? '');
    String? scheduled = lesson?.sn('scheduled_date');

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
                Text(lesson == null ? 'Add a lesson' : 'Edit lesson', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                LabeledField(controller: title, label: 'Title'),
                LabeledField(controller: objective, label: 'Objective', minLines: 2, maxLines: 5),
                LabeledField(controller: assignment, label: 'Assignment (optional)', minLines: 1, maxLines: 4),
                Row(
                  children: [
                    Expanded(child: LabeledField(controller: phaseNo, label: 'Phase no.', keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: LabeledField(controller: phaseTitle, label: 'Phase title')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: LabeledField(controller: weekNo, label: 'Week no.', keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: LabeledField(controller: dayNo, label: 'Day no.', keyboardType: TextInputType.number)),
                  ],
                ),
                PickerField(
                  label: 'Scheduled date',
                  text: scheduled == null ? '' : formatYmd(scheduled),
                  onTap: () async {
                    final picked = await pickDate(ctx, parseYmd(scheduled) ?? DateTime.now());
                    if (picked != null) setSheet(() => scheduled = formatDate(picked));
                  },
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

    if (saved != true) return;
    if (title.text.trim().isEmpty) {
      if (context.mounted) snack(context, 'A lesson needs a title.');
      return;
    }
    final values = <String, Object?>{
      'title': title.text.trim(),
      'objective': emptyToNull(objective.text),
      'assignment': emptyToNull(assignment.text),
      'phase_no': int.tryParse(phaseNo.text.trim()),
      'phase_title': emptyToNull(phaseTitle.text),
      'week_no': int.tryParse(weekNo.text.trim()),
      'day_no': int.tryParse(dayNo.text.trim()),
      'scheduled_date': scheduled,
    };
    final repo = ref.read(learningRepositoryProvider);
    if (lesson == null) {
      await repo.addLesson(planId, values);
    } else {
      await repo.updateLesson(lesson.s('id'), values);
    }
  }

  Future<void> _deleteLesson(BuildContext context, WidgetRef ref, Rec lesson) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete this lesson?',
      message: '"${lesson.s('title')}" will be removed from the programme.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) await ref.read(learningRepositoryProvider).deleteLesson(lesson.s('id'));
  }

  Future<void> _reschedule(BuildContext context, WidgetRef ref, String planId) async {
    final today = ref.read(clockProvider).nowUtc().toLocal();
    final start = await pickDate(context, today);
    if (start == null || !context.mounted) return;
    final ok = await confirmDialog(
      context,
      title: 'Move the schedule?',
      message: 'Day 1 will be ${formatLongDate(start)}. Every lesson with a day number moves with it.',
      confirmLabel: 'Move',
    );
    if (ok) await ref.read(learningRepositoryProvider).rescheduleFrom(planId, start);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(activePlanProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Curriculum')),
      body: plan.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState('$e'),
        data: (p) {
          if (p == null) return const StartProgrammeCard();
          final planId = p.s('id');
          final lessons = ref.watch(lessonsProvider(planId)).valueOrNull ?? const <Rec>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              Text(p.s('title'), style: Theme.of(context).textTheme.titleMedium),
              Text('Starts ${formatYmd(p.sn('start_date'))}  |  ${lessons.length} lessons'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _editLesson(context, ref, planId, null),
                    icon: const Icon(Icons.add),
                    label: const Text('Add lesson'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _reschedule(context, ref, planId),
                    icon: const Icon(Icons.event_repeat),
                    label: const Text('Move start date'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final l in lessons)
                ListTile(
                  dense: true,
                  title: Text('${l.iN('day_no') == null ? '' : 'Day ${l.i('day_no')} - '}${l.s('title')}'),
                  subtitle: Text([
                    if (l.sn('phase_title') != null) l.s('phase_title'),
                    formatYmd(l.sn('scheduled_date')),
                  ].join('  |  ')),
                  onTap: () => _editLesson(context, ref, planId, l),
                  trailing: IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteLesson(context, ref, l),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
