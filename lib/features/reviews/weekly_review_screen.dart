import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/repositories/reviews_repository.dart';
import '../../widgets/common.dart';

/// Weekly review: facts are gathered automatically, you add the reflection.
/// Progress is described by learning and evidence, not by money or hours alone.
class WeeklyReviewScreen extends ConsumerStatefulWidget {
  const WeeklyReviewScreen({super.key, required this.weekStart});

  final String weekStart;

  @override
  ConsumerState<WeeklyReviewScreen> createState() => _WeeklyReviewScreenState();
}

class _WeeklyReviewScreenState extends ConsumerState<WeeklyReviewScreen> {
  final _reflection = TextEditingController();
  final _mistakes = TextEditingController();
  final _unclear = TextEditingController();
  final _priorities = TextEditingController();
  late String _week = widget.weekStart;
  WeeklyStats? _stats;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_reflection, _mistakes, _unclear, _priorities]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = ref.read(reviewsRepositoryProvider);
    final stats = await repo.weeklyStats(_week);
    final review = await repo.reviewFor('weekly', _week);
    final answers = ReviewsRepository.answersOf(review);
    if (!mounted) return;
    _reflection.text = answers['reflection'] ?? '';
    _mistakes.text = answers['mistakes'] ?? '';
    _unclear.text = answers['unclear'] ?? '';
    _priorities.text = review?.s('next_actions') ?? '';
    setState(() {
      _stats = stats;
      _loading = false;
    });
  }

  void _shift(int weeks) {
    _week = addDaysYmd(_week, weeks * 7);
    _load();
  }

  Future<void> _save() async {
    final stats = _stats;
    if (stats == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(reviewsRepositoryProvider).saveWeekly(
            weekStart: _week,
            answers: {
              'reflection': _reflection.text.trim(),
              'mistakes': _mistakes.text.trim(),
              'unclear': _unclear.text.trim(),
            },
            stats: stats,
            priorities: _priorities.text,
          );
      if (mounted) {
        snack(context, 'Weekly review saved.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        snack(context, friendlyError(e));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly review')),
      body: _loading || s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
                    Expanded(
                      child: Text(
                        'Week of ${formatYmd(_week)} to ${formatYmd(addDaysYmd(_week, 6))}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
                  ],
                ),
                SectionCard(
                  title: 'This week in numbers (automatic)',
                  children: [
                    Text('Lessons completed: ${s.lessonsCompleted}'),
                    Text('Days with study activity: ${s.studyDays} of 7'),
                    Text('Study time logged: ${s.minutes} min'),
                    const Divider(),
                    Text('Research cases started: ${s.casesCreated}'),
                    Text('Research cases closed: ${s.casesClosed}'),
                    Text('Hypotheses supported: ${s.supported}, contradicted: ${s.contradicted}, inconclusive: ${s.inconclusive}'),
                    const Divider(),
                    Text('Trades opened: demo ${s.demoTrades}, live ${s.liveTrades}'),
                    Text('Trades where a rule was broken: ${s.brokenRules}'),
                    const SizedBox(height: 6),
                    Text(
                      'Progress is learning and honest evidence, not profit or hours alone.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                if (s.openQuestions.isNotEmpty)
                  SectionCard(
                    title: 'Open questions',
                    children: [for (final q in s.openQuestions) Text('- $q')],
                  ),
                LabeledField(controller: _reflection, label: 'What went well, and what did not?', minLines: 2, maxLines: 8),
                LabeledField(controller: _mistakes, label: 'Recurring mistakes', minLines: 2, maxLines: 8),
                LabeledField(controller: _unclear, label: 'Unanswered questions to work on', minLines: 2, maxLines: 8),
                LabeledField(controller: _priorities, label: 'Next week\'s learning priorities', minLines: 2, maxLines: 8),
                FilledButton(onPressed: _saving ? null : _save, child: const Text('Save review')),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
