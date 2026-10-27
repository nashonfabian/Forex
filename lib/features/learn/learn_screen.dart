import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clock.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../widgets/common.dart';
import '../notes/notes_tab.dart';
import 'lesson_detail_screen.dart';

class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(tabs: [Tab(text: 'Path'), Tab(text: 'Notes')]),
          Expanded(child: TabBarView(children: [_PathTab(), NotesTab()])),
        ],
      ),
    );
  }
}

class _PathTab extends ConsumerWidget {
  const _PathTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(activePlanProvider);
    return plan.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState('$e'),
      data: (p) => p == null ? const StartProgrammeCard() : _PlanView(planId: p.s('id'), title: p.s('title')),
    );
  }
}

/// Shown on the Learn and Today screens until a programme exists.
class StartProgrammeCard extends ConsumerWidget {
  const StartProgrammeCard({super.key});

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final today = ref.read(clockProvider).nowUtc().toLocal();
    final start = await pickDate(context, today);
    if (start == null) return;
    await ref.read(learningRepositoryProvider).createDefaultPlan(start);
    if (context.mounted) snack(context, 'Programme created. Edit it any time under Settings > Curriculum.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.school_outlined, size: 48),
            const SizedBox(height: 12),
            Text('Start your 90-day programme', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'A starter outline of auction-theory and research lessons, one per day. '
              'It is only a starting point: you can edit every lesson.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _start(context, ref),
              child: const Text('Choose a start date'),
            ),
          ],
        ),
      ),
    );
  }
}

IconData lessonStatusIcon(String status) {
  switch (status) {
    case 'completed':
      return Icons.check_circle;
    case 'in_progress':
      return Icons.timelapse;
  }
  return Icons.radio_button_unchecked;
}

class _PlanView extends ConsumerWidget {
  const _PlanView({required this.planId, required this.title});

  final String planId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lessonsAsync = ref.watch(lessonsProvider(planId));
    final today = ref.watch(clockProvider).todayLocal();
    return lessonsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState('$e'),
      data: (lessons) {
        if (lessons.isEmpty) return const EmptyState('This programme has no lessons yet.');

        final phases = <int, List<Rec>>{};
        for (final l in lessons) {
          phases.putIfAbsent(l.iN('phase_no') ?? 0, () => []).add(l);
        }

        final children = <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ];
        phases.forEach((phaseNo, list) {
          final done = list.where((l) => l.s('status') == 'completed').length;
          final phaseTitle = list.first.sn('phase_title') ?? 'Other lessons';
          final weeks = <int, List<Rec>>{};
          for (final l in list) {
            weeks.putIfAbsent(l.iN('week_no') ?? 0, () => []).add(l);
          }
          final tiles = <Widget>[];
          weeks.forEach((weekNo, weekLessons) {
            if (weekNo != 0) {
              tiles.add(Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                child: Text('Week $weekNo', style: Theme.of(context).textTheme.labelLarge),
              ));
            }
            for (final l in weekLessons) {
              final isToday = l.s('scheduled_date') == today;
              final dayNo = l.iN('day_no');
              tiles.add(ListTile(
                dense: true,
                tileColor: isToday ? Theme.of(context).colorScheme.primaryContainer : null,
                leading: Icon(
                  lessonStatusIcon(l.s('status', 'not_started')),
                  color: l.s('status') == 'completed' ? Colors.green : null,
                ),
                title: Text('${dayNo == null ? '' : 'Day $dayNo - '}${l.s('title')}'),
                subtitle: Text(formatYmd(l.sn('scheduled_date'))),
                trailing: l.b('is_milestone') ? const Icon(Icons.flag_outlined) : null,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => LessonDetailScreen(lessonId: l.s('id'))),
                ),
              ));
            }
          });
          children.add(ExpansionTile(
            initiallyExpanded: list.any((l) => l.s('scheduled_date') == today),
            title: Text(phaseNo == 0 ? phaseTitle : 'Phase $phaseNo: $phaseTitle'),
            subtitle: Text('$done / ${list.length} done'),
            children: tiles,
          ));
        });
        children.add(const SizedBox(height: 24));
        return ListView(children: children);
      },
    );
  }
}
