import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/sync/sync_service.dart';
import '../../widgets/common.dart';
import 'account_screen.dart';

class SyncStatusScreen extends ConsumerStatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  ConsumerState<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends ConsumerState<SyncStatusScreen> {
  int _reload = 0;

  void _refresh() => setState(() => _reload++);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(syncStateProvider).valueOrNull ?? ref.read(syncServiceProvider).state;
    final sync = ref.watch(syncServiceProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Sync status')),
      body: ListView(
        key: ValueKey(_reload),
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: state.label,
            children: [
              if (state.message.isNotEmpty) Text(state.message),
              const SizedBox(height: 6),
              Text('Waiting to send: ${state.pending}    Failed: ${state.failed}'),
              Text('Last successful sync: ${formatLocalDateTime(state.lastSuccessIso)}'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  if (!sync.isSignedIn)
                    FilledButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
                      ),
                      child: const Text('Sign in'),
                    ),
                  if (sync.isSignedIn)
                    FilledButton.icon(
                      onPressed: () {
                        sync.requestSync(pull: true, immediate: true);
                        snack(context, 'Syncing...');
                      },
                      icon: const Icon(Icons.sync),
                      label: const Text('Sync now'),
                    ),
                  OutlinedButton(onPressed: _refresh, child: const Text('Refresh')),
                ],
              ),
            ],
          ),
          FutureBuilder<List<Rec>>(
            future: sync.failedItems(),
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <Rec>[];
              if (items.isEmpty) return const SizedBox.shrink();
              return SectionCard(
                title: 'Items that could not be sent',
                trailing: TextButton(
                  onPressed: () async {
                    await sync.retryFailed();
                    _refresh();
                  },
                  child: const Text('Retry all'),
                ),
                children: [
                  for (final q in items)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
                      title: Text('${pretty(q.s('entity_type').replaceAll('_', ' '))} (${q.s('op')})'),
                      subtitle: Text(q.s('last_error', 'Unknown error')),
                    ),
                ],
              );
            },
          ),
          FutureBuilder<List<Rec>>(
            future: sync.conflicts(),
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <Rec>[];
              if (items.isEmpty) return const SizedBox.shrink();
              return SectionCard(
                title: 'Edits that were replaced during sync',
                children: [
                  const Text('The same record was changed on two devices. The newer edit won; '
                      'the other version is kept here so nothing is lost silently.'),
                  for (final c in items)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.merge_type),
                      title: Text(pretty(c.s('entity_type').replaceAll('_', ' '))),
                      subtitle: Text(formatLocalDateTime(c.sn('detected_at'))),
                      trailing: TextButton(
                        onPressed: () async {
                          await sync.dismissConflict(c.i('id'));
                          _refresh();
                        },
                        child: const Text('Dismiss'),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A small helper so other screens can show the phase colour consistently.
Color syncPhaseColor(BuildContext context, SyncPhase phase) {
  final scheme = Theme.of(context).colorScheme;
  switch (phase) {
    case SyncPhase.attention:
      return scheme.error;
    case SyncPhase.synced:
      return Colors.green;
    default:
      return scheme.outline;
  }
}
