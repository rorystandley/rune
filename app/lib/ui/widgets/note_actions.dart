import 'package:flutter/material.dart';

import '../../state/app_scope.dart';

/// Soft-deletes [noteId] and shows an "Undo" snackbar that restores it.
///
/// This is the standard delete gesture from the editor: there is no confirm
/// dialog because the action is reversible — the note goes to Recently Deleted
/// and can be brought straight back from the snackbar. Callers must capture any
/// [Navigator] they need *before* awaiting this, since it crosses an async gap.
Future<void> deleteNoteWithUndo(BuildContext context, String noteId) async {
  final controller = AppScope.of(context);
  // Grab the messenger synchronously so the snackbar still shows even if the
  // caller pops this route immediately afterwards (narrow editor).
  final messenger = ScaffoldMessenger.of(context);

  await controller.deleteNote(noteId);

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text('Note deleted'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => controller.restoreNote(noteId),
        ),
      ),
    );
}
