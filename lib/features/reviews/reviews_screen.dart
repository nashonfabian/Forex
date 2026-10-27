import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clock.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../widgets/common.dart';
import 'daily_review_screen.dart';
import 'weekly_review_screen.dart';

class ReviewsScreen extends ConsumerWidget {
  const ReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock = ref.watch(clockProvider);
    final now = clock.nowUtc().toLocal();
    final today = clock.todayLocal();
    final thisWeek = weekStartYmd(now);
    final weekly = ref.watch(reviewListProvider('weekly')).valueOrNull ?? const <Rec>[];
    final daily = ref.watch(reviewListProvider('daily')).valueOrNull ?? const <Rec>[];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => DailyReviewScreen(ymd: today)),
                ),
                icon: const Icon(Icons.today_outlined),
                label: const Text('Review today'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => WeeklyReviewScreen(weekStart: thisWeek)),
                ),
                icon: const Icon(Icons.date_range_outlined),
                label: const Text('Review this week'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Weekly reviews',
          children: [
            if (weekly.isEmpty) const Text('None yet.'),
            for (final r in weekly)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.date_range_outlined),
                title: Text('Week of ${formatYmd(r.sn('period_start'))}'),
                subtitle: r.sn('next_actions') == null
                    ? null
                    : Text('Next: ${r.s('next_actions')}', maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => WeeklyReviewScreen(weekStart: r.s('period_start'))),
                ),
              ),
          ],
        ),
        SectionCard(
          title: 'Daily reviews',
          children: [
            if (daily.isEmpty) const Text('None yet.'),
            for (final r in daily)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.today_outlined),
                title: Text(formatYmd(r.sn('period_start'))),
                subtitle: r.sn('next_actions') == null
                    ? null
                    : Text('Next: ${r.s('next_actions')}', maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => DailyReviewScreen(ymd: r.s('period_start'))),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
