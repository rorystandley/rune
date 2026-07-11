import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_scope.dart';
import '../widgets/note_actions.dart';
import '../widgets/note_editor.dart';
import '../widgets/note_info_sheet.dart';
import '../widgets/note_list.dart';
import '../widgets/note_share_sheet.dart';
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
        title: const Text('Rune'),
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

class _WideHome extends StatefulWidget {
  const _WideHome();

  @override
  State<_WideHome> createState() => _WideHomeState();
}

class _WideHomeState extends State<_WideHome> {
  final EditorInsertHandle _insertHandle = EditorInsertHandle();
  // The wide layout owns the search field's controller and focus so keyboard
  // shortcuts (⌘F to focus, Esc to clear) can drive it from outside the list.
  // Seeded from the live query (lazily, at first build) so a narrow→wide layout
  // switch mid-search shows the term instead of a blank field over a filtered
  // list.
  late final TextEditingController _searchController =
      TextEditingController(text: AppScope.of(context).search);
  final FocusNode _searchFocus = FocusNode(debugLabel: 'search');
  // A resting focus target inside the shortcuts subtree. Parking focus here
  // (rather than a bare unfocus) keeps the desktop shortcuts live after the
  // search field blurs — an unfocus would let focus escape above them.
  final FocusNode _homeFocus = FocusNode(debugLabel: 'home');

  // Optional Markdown read mode for the open note. Off by default and reset
  // whenever the selection changes — each note opens in the plain editor.
  bool _readMode = false;
  String? _readModeNoteId;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _homeFocus.dispose();
    super.dispose();
  }

  void _focusSearch() {
    _searchFocus.requestFocus();
    // Select any existing query so the next keystroke replaces it.
    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchController.text.length,
    );
  }

  void _clearSearch() {
    // Programmatic edits don't fire the field's onChanged, so tell the
    // controller directly to keep the visible list in sync.
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
      AppScope.of(context).setSearch('');
    }
    // Only move focus off the search field if it actually had it — Esc is bound
    // globally, so blindly grabbing focus here would yank it out of the note
    // editor (e.g. Esc pressed mid-typing on Windows/Linux).
    if (_searchFocus.hasFocus) _homeFocus.requestFocus();
  }

  void _deleteSelected() {
    final id = AppScope.of(context).selectedId;
    if (id != null) deleteNoteWithUndo(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final selected = controller.selectedNote;
    if (selected?.id != _readModeNoteId) {
      _readModeNoteId = selected?.id;
      _readMode = false;
    }

    return _HomeShortcuts(
      focusNode: _homeFocus,
      onNewNote: () => controller.newNote(),
      onFocusSearch: _focusSearch,
      onClearSearch: _clearSearch,
      onDeleteSelected: _deleteSelected,
      onLock: controller.lock,
      child: Scaffold(
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
                      searchController: _searchController,
                      searchFocusNode: _searchFocus,
                      onSearchDismiss: _clearSearch,
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
                        _EditorToolbar(
                          noteId: selected.id,
                          readMode: _readMode,
                          onVoice: () => showVoiceNoteSheet(
                            context,
                            onTranscribed: _insertHandle.insert,
                          ),
                          onInfo: () => showNoteInfoSheet(
                            context,
                            note: selected,
                            live: _insertHandle.readCurrent(),
                          ),
                          onShare: () => showNoteShareSheet(
                            context,
                            note: selected,
                            live: _insertHandle.readCurrent(),
                          ),
                          onTogglePreview: () =>
                              setState(() => _readMode = !_readMode),
                        ),
                        const Divider(height: 0.5),
                        Expanded(
                          child: NoteEditorView(
                            key: ValueKey(selected.id),
                            note: selected,
                            insertHandle: _insertHandle,
                            readMode: _readMode,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Desktop keyboard shortcuts for the two-pane layout. Bound at the top of the
/// wide home so they fire wherever focus sits within it: ⌘N new note, ⌘F focus
/// search, ⌘L lock, ⌘⌫ delete the selected note, and Esc to clear search. The
/// modifier follows the platform — Cmd on macOS, Ctrl elsewhere.
///
/// Esc is delivered two different ways. Everywhere except a focused macOS text
/// field it arrives as a key event, caught by the [SingleActivator] below. But
/// while a text field is the focused first responder, macOS turns a bare Escape
/// into the `cancelOperation:` command, which the framework routes to a
/// [DismissIntent] at the field rather than the key-event path — so that case is
/// handled next to the search field in [NoteList] (via `onSearchDismiss`).
class _HomeShortcuts extends StatelessWidget {
  const _HomeShortcuts({
    required this.focusNode,
    required this.onNewNote,
    required this.onFocusSearch,
    required this.onClearSearch,
    required this.onDeleteSelected,
    required this.onLock,
    required this.child,
  });

  final FocusNode focusNode;
  final VoidCallback onNewNote;
  final VoidCallback onFocusSearch;
  final VoidCallback onClearSearch;
  final VoidCallback onDeleteSelected;
  final VoidCallback onLock;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    SingleActivator cmd(LogicalKeyboardKey key) =>
        SingleActivator(key, meta: isMac, control: !isMac);
    return CallbackShortcuts(
      bindings: {
        cmd(LogicalKeyboardKey.keyN): onNewNote,
        cmd(LogicalKeyboardKey.keyF): onFocusSearch,
        cmd(LogicalKeyboardKey.keyL): onLock,
        const SingleActivator(LogicalKeyboardKey.escape): onClearSearch,
      },
      // Delete goes through Actions rather than CallbackShortcuts (which would
      // always consume the key). The action disables itself while a text field
      // is focused, so the event falls through to the default text-editing
      // shortcuts and ⌘⌫ still means delete-to-line-start inside the editor —
      // rather than nuking the whole note.
      child: Shortcuts(
        shortcuts: {
          // ⌘⌫ on a Mac keyboard; also accept the forward Delete key, the usual
          // delete key on Windows/Linux.
          cmd(LogicalKeyboardKey.backspace): const _DeleteSelectedIntent(),
          cmd(LogicalKeyboardKey.delete): const _DeleteSelectedIntent(),
        },
        child: Actions(
          actions: {
            _DeleteSelectedIntent: _DeleteSelectedAction(onDeleteSelected),
          },
          // A default focus target so the shortcuts are live before the user
          // interacts with any specific pane.
          child: Focus(focusNode: focusNode, autofocus: true, child: child),
        ),
      ),
    );
  }
}

/// Deletes the selected note — but only when no text field is focused, so it
/// never steals ⌘⌫ from the note editor or search box.
class _DeleteSelectedIntent extends Intent {
  const _DeleteSelectedIntent();
}

class _DeleteSelectedAction extends Action<_DeleteSelectedIntent> {
  _DeleteSelectedAction(this.onDelete);

  final VoidCallback onDelete;

  @override
  bool get isActionEnabled => !_editableTextHasFocus();

  @override
  void invoke(_DeleteSelectedIntent intent) => onDelete();
}

/// Whether primary focus currently sits inside an [EditableText] (a text field).
bool _editableTextHasFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context != null &&
      context.findAncestorStateOfType<EditableTextState>() != null;
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
              'Rune',
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
  const _EditorToolbar(
      {required this.noteId,
      required this.readMode,
      required this.onVoice,
      required this.onInfo,
      required this.onShare,
      required this.onTogglePreview});
  final String noteId;
  final bool readMode;
  final VoidCallback onVoice;
  final VoidCallback onInfo;
  final VoidCallback onShare;
  final VoidCallback onTogglePreview;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final pinned = controller.repo.getNote(noteId)?.pinned ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const Spacer(),
          IconButton(
            key: const Key('preview-toggle'),
            icon: Icon(readMode ? Icons.edit_outlined : Icons.visibility_outlined),
            tooltip: readMode ? 'Edit' : 'Preview',
            onPressed: onTogglePreview,
          ),
          IconButton(
            key: const Key('note-info-button'),
            icon: const Icon(Icons.info_outline),
            tooltip: 'Note info',
            onPressed: onInfo,
          ),
          IconButton(
            key: const Key('note-share-button'),
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share or export',
            onPressed: onShare,
          ),
          IconButton(
            icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
            tooltip: pinned ? 'Unpin' : 'Pin to top',
            onPressed: () => controller.togglePinned(noteId),
          ),
          IconButton(
            icon: const Icon(Icons.mic_none),
            tooltip: 'Voice note',
            onPressed: onVoice,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete note',
            onPressed: () => deleteNoteWithUndo(context, noteId),
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
