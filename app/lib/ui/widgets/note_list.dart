import 'package:flutter/material.dart';
import 'package:notes_core/notes_core.dart';

import '../../state/app_scope.dart';

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
              : ListView.separated(
                  itemCount: notes.length,
                  separatorBuilder: (_, _) =>
                      const Divider(indent: 16, endIndent: 16),
                  itemBuilder: (context, i) {
                    final note = notes[i];
                    return _NoteTile(
                      note: note,
                      selected: note.id == widget.selectedId,
                      onTap: () => widget.onOpen(note),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile(
      {required this.note, required this.selected, required this.onTap});

  final Note note;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
      onTap: onTap,
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
