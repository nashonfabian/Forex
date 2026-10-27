import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/repositories/reviews_repository.dart';
import '../../widgets/common.dart';

/// Five short prompts at the end of the day. The "next action" becomes a task for tomorrow.
class DailyReviewScreen extends ConsumerStatefulWidget {
  const DailyReviewScreen({super.key, required this.ymd});

  final String ymd;

  @override
  ConsumerState<DailyReviewScreen> createState() => _DailyReviewScreenState();
}

class _DailyReviewScreenState extends ConsumerState<DailyReviewScreen> {
  final _studied = TextEditingController();
  final _learned = TextEditingController();
  final _evidence = TextEditingController();
  final _unclear = TextEditingController();
  final _next = TextEditingController();
  Map<String, int> _facts = const {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_studied, _learned, _evidence, _unclear, _next]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(reviewsRepositoryProvider);
    final review = await repo.reviewFor('daily', widget.ymd);
    final answers = ReviewsRepository.answersOf(review);
    final facts = await repo.dailyFacts(widget.ymd);
    if (!mounted) return;
    _studied.text = answers['studied'] ?? '';
    _learned.text = answers['learned'] ?? '';
    _evidence.text = answers['evidence'] ?? '';
    _unclear.text = answers['unclear'] ?? '';
    _next.text = review?.s('next_actions') ?? '';
    setState(() {
      _facts = facts;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(reviewsRepositoryProvider).saveDaily(
        ymd: widget.ymd,
        answers: {
          'studied': _studied.text.trim(),
          'learned': _learned.text.trim(),
          'evidence': _evidence.text.trim(),
          'unclear': _unclear.text.trim(),
        },
        nextAction: _next.text,
      );
      if (mounted) {
        snack(context, _next.text.trim().isEmpty
            ? 'Review saved.'
            : 'Review saved. Tomorrow\'s next action is on your Today screen.');
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
    return Scaffold(
      appBar: AppBar(title: Text('Daily review - ${formatYmd(widget.ymd)}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionCard(
                  title: 'Recorded automatically today',
                  children: [
                    Text('Lessons completed: ${_facts['lessons'] ?? 0}'),
                    Text('Notes written: ${_facts['notes'] ?? 0}'),
                    Text('Research cases started: ${_facts['cases'] ?? 0}'),
                    Text('Study time logged: ${_facts['minutes'] ?? 0} min'),
                  ],
                ),
                LabeledField(controller: _studied, label: 'What did I study?', minLines: 2, maxLines: 6),
                LabeledField(controller: _learned, label: 'What did I learn?', minLines: 2, maxLines: 6),
                LabeledField(controller: _evidence, label: 'What evidence did I record?', minLines: 2, maxLines: 6),
                LabeledField(controller: _unclear, label: 'What remains unclear?', minLines: 2, maxLines: 6),
                LabeledField(
                  controller: _next,
                  label: 'Tomorrow\'s next action',
                  hint: 'One clear thing to start with',
                  minLines: 1,
                  maxLines: 3,
                ),
                FilledButton(onPressed: _saving ? null : _save, child: const Text('Save review')),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
