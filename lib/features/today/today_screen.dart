import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/repositories/learning_repository.dart';
import '../../widgets/common.dart';
import '../learn/learn_screen.dart';
import '../learn/lesson_detail_screen.dart';
import '../notes/note_editor_screen.dart';
import '../research/case_form_screen.dart';
import '../reviews/daily_review_screen.dart';
import '../trades/trade_form_screen.dart';

/// The Daily Command Centre: what to study today, what is next, and quick ways to record things.
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> with WidgetsBindingObserver {
  final _taskController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _taskController.dispose();
    super.dispose();
  }

  /// If the app was left open past midnight, "today" must roll over.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(todayProvider);
  }

  void _go(Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));

  Future<void> _addTask(String ymd) async {
    final text = _taskController.text.trim();
    if (text.isEmpty) return;
    await ref.read(learningRepositoryProvider).addTask(ymd, text);
    _taskController.clear();
  }

  Widget _lessonCard(String heading, Rec lesson) {
    final theme = Theme.of(context);
    final repo = ref.read(learningRepositoryProvider);
    final id = lesson.s('id');
    final status = lesson.s('status', 'not_started');
    final dayNo = lesson.iN('day_no');
    return SectionCard(
      title: heading,
      children: [
        Text('${dayNo == null ? '' : 'Day $dayNo - '}${lesson.s('title')}', style: theme.textTheme.titleMedium),
        if (lesson.sn('objective') != null) ...[
          const SizedBox(height: 4),
          Text(lesson.s('objective')),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (status == 'not_started')
              FilledButton(onPressed: () => repo.setLessonStatus(id, 'in_progress'), child: const Text('Start')),
            if (status == 'in_progress')
              FilledButton(onPressed: () => repo.setLessonStatus(id, 'completed'), child: const Text('Mark complete')),
            if (status == 'completed')
              const Chip(avatar: Icon(Icons.check_circle, color: Colors.green, size: 18), label: Text('Completed')),
            OutlinedButton(onPressed: () => _go(LessonDetailScreen(lessonId: id)), child: const Text('Open lesson')),
          ],
        ),
      ],
    );
  }

  Widget _progressCard(TodayData d) {
    final overall = d.totalLessons == 0 ? 0.0 : d.completedLessons / d.totalLessons;
    final phase = d.phaseTotal == 0 ? 0.0 : d.phaseCompleted / d.phaseTotal;
    return SectionCard(
      title: 'Progress',
      children: [
        if (d.phaseTitle != null) ...[
          Text('${d.phaseTitle}: ${d.phaseCompleted} of ${d.phaseTotal} lessons'),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: phase),
          const SizedBox(height: 10),
        ],
        Text('Whole programme: ${d.completedLessons} of ${d.totalLessons} lessons'),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: overall),
      ],
    );
  }

  Widget _tasksCard(TodayData d) {
    final repo = ref.read(learningRepositoryProvider);
    return SectionCard(
      title: 'Today\'s tasks',
      children: [
        if (d.tasks.isEmpty) const Text('No tasks yet.'),
        for (final t in d.tasks)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: t.s('status') == 'done',
            onChanged: (v) => repo.setTaskDone(t.s('id'), v ?? false),
            title: Text(
              '${t.s('kind') == 'next_action' ? 'From your review: ' : ''}${t.s('title')}',
              style: TextStyle(decoration: t.s('status') == 'done' ? TextDecoration.lineThrough : null),
            ),
            secondary: IconButton(
              tooltip: 'Delete task',
              icon: const Icon(Icons.close),
              onPressed: () => repo.deleteTask(t.s('id')),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _taskController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Add a task', isDense: true, border: OutlineInputBorder()),
                onSubmitted: (_) => _addTask(d.ymd),
              ),
            ),
            IconButton(onPressed: () => _addTask(d.ymd), icon: const Icon(Icons.add_circle_outline)),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(todayProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState('Could not load Today: $e'),
      data: (d) {
        final theme = Theme.of(context);
        final todayDate = parseYmd(d.ymd) ?? DateTime.now();
        final sameAsToday = d.continueLesson != null && d.continueLesson!.s('id') == d.todayLesson?.s('id');
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(formatLongDate(todayDate), style: theme.textTheme.headlineSmall),
            const SizedBox(height: 12),
            if (d.plan == null)
              const SizedBox(height: 280, child: StartProgrammeCard())
            else ...[
              if (d.todayLesson != null)
                _lessonCard('Today\'s lesson', d.todayLesson!)
              else
                const SectionCard(title: 'Today\'s lesson', children: [Text('No lesson is scheduled for today.')]),
              if (d.continueLesson != null && !sameAsToday) _lessonCard('Continue learning', d.continueLesson!),
              _progressCard(d),
            ],
            _tasksCard(d),
            if (d.tomorrowTasks.isNotEmpty)
              SectionCard(
                title: 'Tomorrow\'s next action',
                children: [for (final t in d.tomorrowTasks) Text('- ${t.s('title')}')],
              ),
            SectionCard(
              title: 'Quick add',
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _go(const NoteEditorScreen()),
                      icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
                      label: const Text('Note'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _go(const CaseFormScreen()),
                      icon: const Icon(Icons.insights_outlined, size: 18),
                      label: const Text('Research case'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _go(const TradeFormScreen()),
                      icon: const Icon(Icons.show_chart, size: 18),
                      label: const Text('Trade'),
                    ),
                  ],
                ),
              ],
            ),
            SectionCard(
              title: 'Daily reflection',
              children: [
                const Text('Take two minutes to close the day and set tomorrow\'s first action.'),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () => _go(DailyReviewScreen(ymd: d.ymd)),
                  child: const Text('Open daily review'),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}
