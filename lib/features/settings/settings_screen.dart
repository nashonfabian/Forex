import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../widgets/common.dart';
import 'account_screen.dart';
import 'curriculum_editor_screen.dart';
import 'diagnostics.dart';
import 'sync_status_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  List<CheckResult>? _results;
  bool _running = false;
  bool _busy = false;

  void _go(Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));

  Future<void> _exportBackup() async {
    setState(() => _busy = true);
    try {
      final file = await ref.read(backupServiceProvider).exportZip();
      await Share.shareXFiles([XFile(file.path)], text: 'MY MARKET LAB backup');
    } catch (e) {
      if (mounted) snack(context, 'Could not create the backup: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    final ok = await confirmDialog(
      context,
      title: 'Import this backup?',
      message: 'Records that are missing on this phone will be added. Nothing already here is changed or deleted.',
      confirmLabel: 'Import',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final summary = await ref.read(backupServiceProvider).importZip(path);
      if (mounted) snack(context, 'Imported ${summary.rows} records and ${summary.images} screenshots.');
    } catch (e) {
      if (mounted) snack(context, 'Could not import: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runChecks() async {
    setState(() {
      _running = true;
      _results = null;
    });
    final diagnostics = Diagnostics(ref.read(appDatabaseProvider), ref.read(clockProvider));
    final results = await diagnostics.run();
    if (!mounted) return;
    setState(() {
      _results = results;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sync = ref.watch(syncStateProvider).valueOrNull ?? ref.read(syncServiceProvider).state;
    final results = _results;
    final passed = results?.where((r) => r.ok).length ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.cloud_outlined, color: syncPhaseColor(context, sync.phase)),
                  title: Text(sync.label),
                  subtitle: sync.message.isEmpty ? null : Text(sync.message),
                  onTap: () => _go(const SyncStatusScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Account'),
                  onTap: () => _go(const AccountScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.sync_problem_outlined),
                  title: const Text('Sync status and problems'),
                  onTap: () => _go(const SyncStatusScreen()),
                ),
              ],
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('Curriculum'),
              subtitle: const Text('Edit lessons or move the start date'),
              onTap: () => _go(const CurriculumEditorScreen()),
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.upload_file_outlined),
                  title: const Text('Export a backup (ZIP)'),
                  subtitle: const Text('All your data and screenshots in one file'),
                  enabled: !_busy,
                  onTap: _exportBackup,
                ),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Import a backup'),
                  subtitle: const Text('Adds missing records; never overwrites'),
                  enabled: !_busy,
                  onTap: _importBackup,
                ),
              ],
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Foundation checks', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  const Text('Tests the database, the hypothesis-lock rules, the sync outbox and schema '
                      'upgrades on this phone. Your data is not changed.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _running ? null : _runChecks,
                    icon: _running
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.fact_check_outlined),
                    label: Text(_running ? 'Running...' : 'Run foundation checks'),
                  ),
                  if (results != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      '$passed of ${results.length} passed',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: passed == results.length ? Colors.green : theme.colorScheme.error,
                      ),
                    ),
                    for (final r in results)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          r.ok ? Icons.check_circle : Icons.cancel,
                          color: r.ok ? Colors.green : theme.colorScheme.error,
                        ),
                        title: Text(r.name),
                        subtitle: r.detail.isEmpty ? null : Text(r.detail),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
