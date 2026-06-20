import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../widgets/dialogs.dart';
import '../widgets/note_editor.dart';
import '../widgets/note_list.dart';
import '../widgets/voice_note_sheet.dart';
import 'editor_screen.dart';
import 'settings_screen.dart';

/// The main screen once unlocked. Two-pane on wide displays (sidebar + editor),
/// single-pane with push navigation on narrow ones. A [Listener] resets the
/// auto-lock timer on interaction.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => controller.onUserActivity(),
      child: LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth >= 760 ? const _WideHome() : const _NarrowHome(),
      ),
    );
  }
}

// --------------------------------------------------------------- narrow ---

class _NarrowHome extends StatelessWidget {
  const _NarrowHome();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic_none),
            tooltip: 'Voice note',
            onPressed: () => showVoiceNoteSheet(context),
          ),
          IconButton(
            key: const Key('lock-button'),
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Lock',
            onPressed: controller.lock,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => _openSettings(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('new-note-button'),
        onPressed: () => _newNote(context),
        child: const Icon(Icons.add),
      ),
      body: NoteList(
        onOpen: (note) => _openNote(context, note.id),
        onNew: () => _newNote(context),
      ),
    );
  }
}

// ----------------------------------------------------------------- wide ---

class _WideHome extends StatelessWidget {
  const _WideHome();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final selected = controller.selectedNote;

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 320,
            child: Column(
              children: [
                const _SidebarHeader(),
                const Divider(height: 0.5),
                Expanded(
                  child: NoteList(
                    selectedId: controller.selectedId,
                    onOpen: (note) => controller.selectNote(note.id),
                    onNew: () => controller.newNote(),
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 0.5),
          Expanded(
            child: selected == null
                ? const _EmptyEditor()
                : Column(
                    children: [
                      _EditorToolbar(noteId: selected.id),
                      const Divider(height: 0.5),
                      Expanded(
                        child: NoteEditorView(
                          key: ValueKey(selected.id),
                          note: selected,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Notes',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButtonTheme(
            data: IconButtonThemeData(
              style:
                  IconButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.mic_none),
                  tooltip: 'Voice note',
                  onPressed: () => showVoiceNoteSheet(context),
                ),
                IconButton(
                  key: const Key('new-note-button'),
                  icon: const Icon(Icons.add),
                  tooltip: 'New note',
                  onPressed: () => controller.newNote(),
                ),
                IconButton(
                  key: const Key('lock-button'),
                  icon: const Icon(Icons.lock_outline),
                  tooltip: 'Lock',
                  onPressed: controller.lock,
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                  onPressed: () => _openSettings(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({required this.noteId});
  final String noteId;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const Spacer(),
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
              if (ok) await controller.deleteNote(noteId);
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyEditor extends StatelessWidget {
  const _EmptyEditor();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = AppScope.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No note selected',
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => controller.newNote(),
            icon: const Icon(Icons.add),
            label: const Text('New note'),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- actions ---

Future<void> _newNote(BuildContext context) async {
  final controller = AppScope.of(context);
  final note = await controller.newNote();
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => EditorScreen(noteId: note.id)),
  );
}

void _openNote(BuildContext context, String id) {
  AppScope.of(context).selectNote(id);
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => EditorScreen(noteId: id)),
  );
}

void _openSettings(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
  );
}
