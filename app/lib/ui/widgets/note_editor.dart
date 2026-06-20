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
class NoteEditorView extends StatefulWidget {
  const NoteEditorView({super.key, required this.note});

  final Note note;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = AppScope.of(context);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _flush(); // best-effort save of any pending edits
    _title.dispose();
    _body.dispose();
    super.dispose();
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
