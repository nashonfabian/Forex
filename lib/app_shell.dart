import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'data/sync/sync_service.dart';
import 'features/learn/learn_screen.dart';
import 'features/research/research_screen.dart';
import 'features/reviews/reviews_screen.dart';
import 'features/search/search_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/sync_status_screen.dart';
import 'features/today/today_screen.dart';
import 'features/trades/trades_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _titles = ['Today', 'Learn', 'Research', 'Trades', 'Reviews'];

  static const _tabs = <Widget>[
    TodayScreen(),
    LearnScreen(),
    ResearchScreen(),
    TradesScreen(),
    ReviewsScreen(),
  ];

  void _go(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: ColoredBox(
                color: Colors.black,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Image.asset(
                    'assets/images/brand_logo.png',
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(_titles[_index]),
          ],
        ),
        actions: [
          const _SyncStatusChip(),
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => _go(const SearchScreen()),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _go(const SettingsScreen()),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: 'Learn',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Research',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            label: 'Trades',
          ),
          NavigationDestination(
            icon: Icon(Icons.rate_review_outlined),
            selectedIcon: Icon(Icons.rate_review),
            label: 'Reviews',
          ),
        ],
      ),
    );
  }
}

/// Shows the real sync state: local only, offline, syncing, waiting, synced or needs attention.
class _SyncStatusChip extends ConsumerWidget {
  const _SyncStatusChip();

  IconData _icon(SyncPhase phase) {
    switch (phase) {
      case SyncPhase.localOnly:
        return Icons.phone_android;
      case SyncPhase.offline:
        return Icons.cloud_off;
      case SyncPhase.syncing:
        return Icons.sync;
      case SyncPhase.pending:
        return Icons.cloud_queue;
      case SyncPhase.synced:
        return Icons.cloud_done_outlined;
      case SyncPhase.attention:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncStateProvider).valueOrNull ??
        const SyncState(phase: SyncPhase.localOnly);
    return Tooltip(
      message: state.message.isEmpty ? state.label : state.message,
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: ActionChip(
          avatar: Icon(_icon(state.phase),
              size: 16, color: syncPhaseColor(context, state.phase)),
          label: Text(state.label),
          visualDensity: VisualDensity.compact,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SyncStatusScreen()),
          ),
        ),
      ),
    );
  }
}
