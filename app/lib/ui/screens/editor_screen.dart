import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../widgets/note_actions.dart';
import '../widgets/note_editor.dart';
import '../widgets/note_info_sheet.dart';
import '../widgets/note_share_sheet.dart';
import '../widgets/voice_note_sheet.dart';

/// Full-screen note editor used on narrow (mobile) layouts.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.noteId});

  final String noteId;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final EditorInsertHandle _insertHandle = EditorInsertHandle();

  // Optional Markdown read mode; off by default, per editor session.
  bool _readMode = false;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final note = controller.repo.getNote(widget.noteId);

    if (note == null) {
      return const Scaffold(body: Center(child: Text('Note not found')));
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            key: const Key('preview-toggle'),
            icon: Icon(
                _readMode ? Icons.edit_outlined : Icons.visibility_outlined),
            tooltip: _readMode ? 'Edit' : 'Preview',
            onPressed: () => setState(() => _readMode = !_readMode),
          ),
          IconButton(
            key: const Key('note-info-button'),
            icon: const Icon(Icons.info_outline),
            tooltip: 'Note info',
            onPressed: () => showNoteInfoSheet(
              context,
              note: note,
              live: _insertHandle.readCurrent(),
            ),
          ),
          IconButton(
            key: const Key('note-share-button'),
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share or export',
            onPressed: () => showNoteShareSheet(
              context,
              note: note,
              live: _insertHandle.readCurrent(),
            ),
          ),
          IconButton(
            icon: Icon(note.pinned ? Icons.push_pin : Icons.push_pin_outlined),
            tooltip: note.pinned ? 'Unpin' : 'Pin to top',
            onPressed: () => controller.togglePinned(note.id),
          ),
          IconButton(
            icon: const Icon(Icons.mic_none),
            tooltip: 'Voice note',
            onPressed: () =>
                showVoiceNoteSheet(context, onTranscribed: _insertHandle.insert),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete note',
            onPressed: () async {
              final navigator = Navigator.of(context);
              await deleteNoteWithUndo(context, widget.noteId);
              if (mounted) navigator.pop();
            },
          ),
        ],
      ),
      body: NoteEditorView(
        key: ValueKey(note.id),
        note: note,
        insertHandle: _insertHandle,
        readMode: _readMode,
      ),
    );
  }
}
