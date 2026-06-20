import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../widgets/dialogs.dart';
import '../widgets/note_editor.dart';
import '../widgets/voice_note_sheet.dart';

/// Full-screen note editor used on narrow (mobile) layouts.
class EditorScreen extends StatelessWidget {
  const EditorScreen({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final note = controller.repo.getNote(noteId);

    if (note == null) {
      return const Scaffold(body: Center(child: Text('Note not found')));
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.mic_none),
            tooltip: 'Voice note',
            onPressed: () => showVoiceNoteSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete note',
            onPressed: () async {
              final ok = await confirmDestructive(
                context,
                title: 'Delete note?',
                message: 'This permanently removes the note from your vault.',
                confirmLabel: 'Delete',
              );
              if (!ok) return;
              await controller.deleteNote(noteId);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: NoteEditorView(key: ValueKey(note.id), note: note),
    );
  }
}
