import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/repositories/search_repository.dart';
import '../../widgets/common.dart';
import '../learn/lesson_detail_screen.dart';
import '../notes/note_editor_screen.dart';
import '../research/case_detail_screen.dart';
import '../trades/trade_form_screen.dart';

/// One search box across notes, research cases, trades and lessons.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  Future<SearchResults>? _future;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _future = ref.read(searchRepositoryProvider).search(text));
    });
  }

  void _go(Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));

  List<Widget> _section(String title, List<Rec> rows, Widget Function(Rec) tile) {
    if (rows.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
      for (final r in rows) tile(r),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(hintText: 'Search everything', border: InputBorder.none),
        ),
      ),
      body: _future == null
          ? const EmptyState('Type at least two letters to search your notes, cases, trades and lessons.')
          : FutureBuilder<SearchResults>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) return EmptyState('${snapshot.error}');
                final r = snapshot.data ?? const SearchResults();
                if (r.isEmpty) return const EmptyState('Nothing found.');
                return ListView(
                  children: [
                    ..._section(
                      'Research cases',
                      r.cases,
                      (c) => ListTile(
                        leading: const Icon(Icons.insights_outlined),
                        title: Text(c.s('title', 'Untitled')),
                        subtitle: Text([c.sn('instrument'), c.sn('timeframe')].whereType<String>().join(' | ')),
                        onTap: () => _go(CaseDetailScreen(caseId: c.s('id'))),
                      ),
                    ),
                    ..._section(
                      'Notes',
                      r.notes,
                      (n) => ListTile(
                        leading: const Icon(Icons.sticky_note_2_outlined),
                        title: Text(n.sn('title') ?? n.s('body_md'), maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(pretty(n.s('kind'))),
                        onTap: () => _go(NoteEditorScreen(noteId: n.s('id'))),
                      ),
                    ),
                    ..._section(
                      'Trades',
                      r.trades,
                      (t) => ListTile(
                        leading: const Icon(Icons.show_chart),
                        title: Text('${t.s('instrument')} ${t.s('direction')}'),
                        subtitle: Text('${pretty(t.s('account_type'))} | ${formatLocalDate(t.sn('opened_at'))}'),
                        onTap: () => _go(TradeFormScreen(tradeId: t.s('id'))),
                      ),
                    ),
                    ..._section(
                      'Lessons',
                      r.lessons,
                      (l) => ListTile(
                        leading: const Icon(Icons.school_outlined),
                        title: Text(l.s('title')),
                        subtitle: Text(l.s('objective'), maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => _go(LessonDetailScreen(lessonId: l.s('id'))),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
    );
  }
}
