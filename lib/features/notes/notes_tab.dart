import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../data/repositories/notes_repository.dart';
import '../../widgets/common.dart';
import 'note_editor_screen.dart';

IconData noteKindIcon(String kind) {
  switch (kind) {
    case 'definition':
      return Icons.menu_book_outlined;
    case 'example':
      return Icons.lightbulb_outline;
    case 'question':
      return Icons.help_outline;
    case 'reference':
      return Icons.library_books_outlined;
  }
  return Icons.sticky_note_2_outlined;
}

/// The Study Room: notes, definitions (glossary), examples, questions and references.
class NotesTab extends ConsumerStatefulWidget {
  const NotesTab({super.key});

  @override
  ConsumerState<NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends ConsumerState<NotesTab> {
  static const _chips = [
    'All', 'Note', 'Definition', 'Example', 'Question', 'Reference', 'Bookmarked', 'Open questions',
  ];

  final _search = TextEditingController();
  String _chip = 'All';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  NoteFilter get _filter {
    final q = _search.text;
    switch (_chip) {
      case 'All':
        return NoteFilter(query: q);
      case 'Bookmarked':
        return NoteFilter(query: q, bookmarkedOnly: true);
      case 'Open questions':
        return NoteFilter(query: q, openQuestionsOnly: true);
      default:
        return NoteFilter(query: q, kind: _chip.toLowerCase());
    }
  }

  void _open({String? id}) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(noteId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesProvider(_filter));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search notes, tags, books',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () => _open(),
                icon: const Icon(Icons.add),
                label: const Text('New'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final label in _chips)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _chip == label,
                    onSelected: (_) => setState(() => _chip = label),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: notes.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => EmptyState('$e'),
            data: (items) {
              if (items.isEmpty) {
                return const EmptyState('Nothing here yet.\nTap "New" to add a note, definition or question.');
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final n = items[i];
                  final kind = n.s('kind', 'note');
                  final title = n.sn('title') ?? n.s('body_md');
                  final open = kind == 'question' && (n.sn('question_status') ?? 'open') == 'open';
                  return Card(
                    child: ListTile(
                      leading: Icon(noteKindIcon(kind)),
                      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          pretty(kind) + (kind == 'question' ? (open ? ' (open)' : ' (answered)') : ''),
                          if (n.sn('tag_names') != null) n.s('tag_names'),
                          formatLocalDate(n.sn('created_at')),
                        ].join('  |  '),
                      ),
                      trailing: IconButton(
                        tooltip: 'Bookmark',
                        icon: Icon(n.b('is_bookmarked') ? Icons.bookmark : Icons.bookmark_border),
                        onPressed: () => ref
                            .read(notesRepositoryProvider)
                            .setBookmarked(n.s('id'), !n.b('is_bookmarked')),
                      ),
                      onTap: () => _open(id: n.s('id')),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
