import 'dart:async';

import 'package:flutter/material.dart';
import 'package:notes_core/notes_core.dart';

import '../../state/app_controller.dart';
import '../../state/app_scope.dart';

/// The title + body editor with debounced autosave.
///
/// Seeded once from [note]; thereafter it owns its text so external rebuilds
/// never clobber the cursor. Switch notes by giving it a `ValueKey(note.id)` so
/// Flutter rebuilds the state for the new note.
/// Bridges the editor's chrome (app bar / toolbar) to the live body field so a
/// voice-note transcription inserts into the open note, rather than persisting
/// behind the editor's back where the debounced autosave would clobber it. The
/// mounted editor attaches its insert function; callers invoke [insert].
class EditorInsertHandle {
  void Function(String text)? _insert;

  /// Whether an editor is currently mounted and listening.
  bool get isAttached => _insert != null;

  /// Inserts [text] into the open editor body, if one is mounted.
  void insert(String text) => _insert?.call(text);
}

class NoteEditorView extends StatefulWidget {
  const NoteEditorView({super.key, required this.note, this.insertHandle});

  final Note note;

  /// Optional bridge letting the surrounding chrome insert into the live body.
  final EditorInsertHandle? insertHandle;

  @override
  State<NoteEditorView> createState() => _NoteEditorViewState();
}

class _NoteEditorViewState extends State<NoteEditorView> {
  late final TextEditingController _title =
      TextEditingController(text: widget.note.title);
  late final TextEditingController _body =
      TextEditingController(text: widget.note.body);
  Timer? _debounce;
  AppController? _controller;

  static const Duration _debounceDelay = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();
    widget.insertHandle?._insert = _insertTranscript;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = AppScope.of(context);
  }

  @override
  void dispose() {
    if (identical(widget.insertHandle?._insert, _insertTranscript)) {
      widget.insertHandle?._insert = null;
    }
    _debounce?.cancel();
    _flush(); // best-effort save of any pending edits
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// Inserts [text] at the cursor (or appends), on its own line when there is
  /// preceding content, then schedules the normal debounced autosave.
  void _insertTranscript(String text) {
    final addition = text.trim();
    if (addition.isEmpty) return;
    final existing = _body.text;
    final sel = _body.selection;
    final at = (sel.isValid && sel.start >= 0 && sel.start <= existing.length)
        ? sel.start
        : existing.length;
    final before = existing.substring(0, at);
    final after = existing.substring(at);
    final piece =
        before.isEmpty || before.endsWith('\n') ? addition : '\n$addition';
    _body.value = TextEditingValue(
      text: '$before$piece$after',
      selection: TextSelection.collapsed(offset: (before + piece).length),
    );
    _onChanged();
  }

  void _onChanged() {
    _controller?.onUserActivity();
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, _flush);
  }

  void _flush() {
    _debounce?.cancel();
    final controller = _controller;
    if (controller == null) return;
    unawaited(controller.saveNote(
      widget.note.id,
      title: _title.text,
      body: _body.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('editor-title'),
            controller: _title,
            onChanged: (_) => _onChanged(),
            textCapitalization: TextCapitalization.sentences,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              hintText: 'Title',
              border: InputBorder.none,
              isCollapsed: true,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              key: const Key('editor-body'),
              controller: _body,
              onChanged: (_) => _onChanged(),
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
              decoration: const InputDecoration(
                hintText: 'Start writing…',
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
