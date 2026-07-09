import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:notes_core/notes_core.dart';

import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../screens/recently_deleted_screen.dart';

/// The search field + scrollable list of notes. Used in both the wide
/// (sidebar) and narrow (full-screen) layouts. [onOpen] is called when a note
/// is tapped; [selectedId] highlights the active note in the sidebar.
class NoteList extends StatefulWidget {
  const NoteList(
      {super.key, required this.onOpen, this.selectedId, this.onNew});

  final void Function(Note note) onOpen;
  final String? selectedId;

  /// Invoked by the empty-state "New note" button (layout decides what happens).
  final VoidCallback? onNew;

  @override
  State<NoteList> createState() => _NoteListState();
}

class _NoteListState extends State<NoteList> {
  late final TextEditingController _search =
      TextEditingController(text: AppScope.of(context).search);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final notes = controller.visibleNotes;
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: TextField(
            key: const Key('search-field'),
            controller: _search,
            onChanged: controller.setSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),
        Expanded(
          child: notes.isEmpty
              ? _EmptyList(
                  searching: controller.search.isNotEmpty, onNew: widget.onNew)
              : _buildList(controller, notes),
        ),
        // Recently Deleted lives at the foot of the list — out of the way, and
        // only when there's something to recover and we're not searching.
        if (controller.search.isEmpty && controller.deletedNotes.isNotEmpty)
          _RecentlyDeletedFooter(count: controller.deletedNotes.length),
      ],
    );
  }

  Widget _buildList(AppController controller, List<Note> notes) {
    final pinned = notes.where((n) => n.pinned).toList(growable: false);

    // Sections only make sense when something is pinned and we're not
    // searching — during search a flat, ranked list is calmer.
    if (pinned.isEmpty || controller.search.isNotEmpty) {
      return ListView.separated(
        itemCount: notes.length,
        separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
        itemBuilder: (context, i) => _noteTile(controller, notes[i]),
      );
    }

    final others = notes.where((n) => !n.pinned).toList(growable: false);
    final entries = <_ListEntry>[
      const _ListEntry.header('Pinned'),
      ...pinned.map(_ListEntry.note),
      if (others.isNotEmpty) const _ListEntry.header('Notes'),
      ...others.map(_ListEntry.note),
    ];

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        final header = entry.header;
        if (header != null) return _SectionHeader(label: header);
        final tile = _noteTile(controller, entry.note!);
        // Divider between adjacent note rows, but not before a section header.
        final next = i + 1 < entries.length ? entries[i + 1] : null;
        if (next?.note != null) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [tile, const Divider(indent: 16, endIndent: 16)],
          );
        }
        return tile;
      },
    );
  }

  Widget _noteTile(AppController controller, Note note) => _NoteTile(
        note: note,
        selected: note.id == widget.selectedId,
        onTap: () => widget.onOpen(note),
        onTogglePin: () => controller.togglePinned(note.id),
      );
}

/// One row in the sectioned list: either a section [header] or a [note].
class _ListEntry {
  const _ListEntry.header(this.header) : note = null;
  const _ListEntry.note(this.note) : header = null;

  final String? header;
  final Note? note;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.hintColor,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile(
      {required this.note,
      required this.selected,
      required this.onTap,
      required this.onTogglePin});

  final Note note;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Long-press opens the action sheet for pointer users; expose the same
    // pin/unpin action to assistive tech (which can't reach a long-press) as a
    // custom semantics action, keeping the row visually uncluttered.
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: note.pinned ? 'Unpin' : 'Pin to top'):
            onTogglePin,
      },
      child: _buildTile(theme, context),
    );
  }

  Widget _buildTile(ThemeData theme, BuildContext context) {
    return ListTile(
      selected: selected,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.10),
      title: Text(
        note.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Row(
        children: [
          Text(formatNoteDate(note.updatedAt),
              style: theme.textTheme.bodySmall),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              note.preview.isEmpty ? 'No additional text' : note.preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ),
        ],
      ),
      trailing: note.pinned
          ? Icon(Icons.push_pin, size: 16, color: theme.hintColor)
          : null,
      onTap: onTap,
      onLongPress: () => _showActions(context),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    final pinned = note.pinned;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                  pinned ? Icons.push_pin_outlined : Icons.push_pin),
              title: Text(pinned ? 'Unpin' : 'Pin to top'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onTogglePin();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Entry point to the Recently Deleted view, pinned below the list. Shown only
/// when at least one note is soft-deleted.
class _RecentlyDeletedFooter extends StatelessWidget {
  const _RecentlyDeletedFooter({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 0.5),
        ListTile(
          key: const Key('recently-deleted-entry'),
          leading: Icon(Icons.delete_outline, color: theme.hintColor),
          title: const Text('Recently Deleted'),
          trailing: Text('$count', style: theme.textTheme.bodyMedium),
          dense: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const RecentlyDeletedScreen(),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.searching, this.onNew});
  final bool searching;
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              searching ? 'No matching notes' : 'No notes yet',
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            ),
            if (!searching && onNew != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('empty-new-note-button'),
                onPressed: onNew,
                icon: const Icon(Icons.add),
                label: const Text('New note'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Short, locale-agnostic date label for a note row.
String formatNoteDate(DateTime when) {
  final local = when.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(local.year, local.month, local.day);
  final diff = today.difference(thatDay).inDays;

  if (diff == 0) {
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
  if (diff == 1) return 'Yesterday';
  if (diff < 7) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[local.weekday - 1];
  }
  final d = local.day.toString().padLeft(2, '0');
  final mo = local.month.toString().padLeft(2, '0');
  return '$d/$mo/${local.year}';
}
