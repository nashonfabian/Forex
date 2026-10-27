import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/rows.dart';
import '../../widgets/common.dart';
import '../shared/link_navigation.dart';

const noteKinds = ['note', 'definition', 'example', 'question', 'reference'];

class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, this.noteId, this.lessonId, this.initialKind});

  final String? noteId;
  final String? lessonId;
  final String? initialKind;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _book = TextEditingController();
  final _chapter = TextEditingController();
  final _page = TextEditingController();
  final _tags = TextEditingController();

  String _kind = 'note';
  bool _bookmarked = false;
  String _questionStatus = 'open';
  String? _lessonId;
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _lessonId = widget.lessonId;
    _kind = widget.initialKind ?? 'note';
    if (widget.noteId != null) {
      _loading = true;
      _load();
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _body, _book, _chapter, _page, _tags]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final n = await ref.read(notesRepositoryProvider).byId(widget.noteId!);
    final tags = await ref.read(tagsRepositoryProvider).namesFor('notes', widget.noteId!);
    if (!mounted) return;
    if (n != null) {
      _title.text = n.s('title');
      _body.text = n.s('body_md');
      _book.text = n.s('book');
      _chapter.text = n.s('chapter');
      _page.text = n.s('page');
      _tags.text = tags.join(', ');
      _kind = n.s('kind', 'note');
      _bookmarked = n.b('is_bookmarked');
      _questionStatus = n.sn('question_status') ?? 'open';
      _lessonId = n.sn('lesson_id');
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_body.text.trim().isEmpty && _title.text.trim().isEmpty) {
      snack(context, 'Write something first.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(notesRepositoryProvider).save(
        id: widget.noteId,
        values: {
          'kind': _kind,
          'title': emptyToNull(_title.text),
          'body_md': _body.text,
          'lesson_id': _lessonId,
          'book': emptyToNull(_book.text),
          'chapter': emptyToNull(_chapter.text),
          'page': emptyToNull(_page.text),
          'is_bookmarked': _bookmarked ? 1 : 0,
          'question_status': _kind == 'question' ? _questionStatus : null,
        },
        tags: splitTags(_tags.text),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        snack(context, friendlyError(e));
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete this note?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(notesRepositoryProvider).delete(widget.noteId!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isQuestion = _kind == 'question';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.noteId == null ? 'New note' : 'Edit note'),
        actions: [
          IconButton(
            tooltip: _bookmarked ? 'Remove bookmark' : 'Bookmark',
            icon: Icon(_bookmarked ? Icons.bookmark : Icons.bookmark_border),
            onPressed: () => setState(() => _bookmarked = !_bookmarked),
          ),
          if (widget.noteId != null)
            IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ChoiceRow(
                  label: 'Type',
                  options: noteKinds,
                  value: _kind,
                  allowClear: false,
                  onChanged: (v) => setState(() => _kind = v ?? _kind),
                ),
                if (isQuestion)
                  ChoiceRow(
                    label: 'Question status',
                    options: const ['open', 'answered'],
                    value: _questionStatus,
                    allowClear: false,
                    onChanged: (v) => setState(() => _questionStatus = v ?? _questionStatus),
                  ),
                LabeledField(controller: _title, label: 'Title (optional)'),
                LabeledField(
                  controller: _body,
                  label: isQuestion ? 'Question' : 'Note',
                  hint: 'Markdown works: # heading, - list, **bold**',
                  minLines: 8,
                  maxLines: 24,
                ),
                Row(
                  children: [
                    Expanded(flex: 3, child: LabeledField(controller: _book, label: 'Book')),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: LabeledField(controller: _chapter, label: 'Chapter')),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: LabeledField(controller: _page, label: 'Page')),
                  ],
                ),
                LabeledField(controller: _tags, label: 'Tags', hint: 'Separate with commas'),
                if (_lessonId != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.school_outlined, size: 18),
                        const SizedBox(width: 6),
                        const Expanded(child: Text('Attached to a lesson')),
                        TextButton(onPressed: () => setState(() => _lessonId = null), child: const Text('Detach')),
                      ],
                    ),
                  ),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving...' : 'Save'),
                ),
                const SizedBox(height: 16),
                if (widget.noteId != null)
                  LinkedItemsCard(
                    entityType: 'notes',
                    entityId: widget.noteId!,
                    actions: [
                      OutlinedButton.icon(
                        onPressed: () => linkToCase(context, ref, 'notes', widget.noteId!),
                        icon: const Icon(Icons.insights_outlined, size: 18),
                        label: const Text('Case'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => linkToLesson(context, ref, 'notes', widget.noteId!),
                        icon: const Icon(Icons.school_outlined, size: 18),
                        label: const Text('Lesson'),
                      ),
                    ],
                  ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
