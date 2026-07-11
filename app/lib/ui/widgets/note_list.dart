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
      {super.key,
      required this.onOpen,
      this.selectedId,
      this.onNew,
      this.searchController,
      this.searchFocusNode,
      this.onSearchDismiss});

  final void Function(Note note) onOpen;
  final String? selectedId;

  /// Invoked by the empty-state "New note" button (layout decides what happens).
  final VoidCallback? onNew;

  /// Optional externally-owned search controller/focus, so a parent (the wide
  /// layout) can drive the field via keyboard shortcuts. When null, the list
  /// owns its own — the plain narrow/mobile case.
  final TextEditingController? searchController;
  final FocusNode? searchFocusNode;

  /// Called when the search field receives a [DismissIntent] — how macOS
  /// delivers a bare Escape while a text field is focused. Lets the wide layout
  /// run its full clear (which also re-parks focus for the shortcuts); when
  /// null the list just clears the query itself.
  final VoidCallback? onSearchDismiss;

  @override
  State<NoteList> createState() => _NoteListState();
}

class _NoteListState extends State<NoteList> {
  // Captured at construction so dispose can't disagree with how `_search` was
  // created, even if the widget is later reconfigured with a different one.
  late final bool _ownsSearch;
  late final TextEditingController _search = widget.searchController ??
      TextEditingController(text: AppScope.of(context).search);

  @override
  void initState() {
    super.initState();
    _ownsSearch = widget.searchController == null;
  }

  @override
  void dispose() {
    // Only dispose the controller we created ourselves; a parent-owned one is
    // the parent's responsibility.
    if (_ownsSearch) _search.dispose();
    super.dispose();
  }

  void _clearSearch() {
    if (_search.text.isEmpty) return;
    _search.clear();
    AppScope.of(context).setSearch('');
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
          // Handle Escape-while-typing here, as a direct ancestor of the field:
          // on macOS a bare Escape arrives as a DismissIntent (cancelOperation:)
          // rather than a key event, and DismissIntent is re-dispatched up only
          // to the nearest handler. The wide layout passes its own clear (which
          // also re-parks focus); otherwise the list clears the query itself.
          child: Actions(
            actions: <Type, Action<Intent>>{
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) =>
                    (widget.onSearchDismiss ?? _clearSearch).call(),
              ),
            },
            child: TextField(
            key: const Key('search-field'),
            controller: _search,
            focusNode: widget.searchFocusNode,
            onChanged: controller.setSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search',
              prefixIcon: const Icon(Icons.search, size: 20),
              // A clear affordance for pointer users — the Esc shortcut does the
              // same thing from the keyboard.
              suffixIcon: controller.search.isEmpty
                  ? null
                  : IconButton(
                      key: const Key('search-clear'),
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Clear search',
                      onPressed: _clearSearch,
                    ),
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
        ),
        // While searching, say how many notes matched — the difference between
        // "did anything happen?" and a real tool. The empty state already
        // covers the zero case.
        if (controller.search.trim().isNotEmpty && notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                notes.length == 1 ? '1 result' : '${notes.length} results',
                key: const Key('search-result-count'),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.hintColor),
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
        query: controller.search,
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
      required this.query,
      required this.selected,
      required this.onTap,
      required this.onTogglePin});

  final Note note;

  /// The live search query; matched runs in the title/preview are highlighted
  /// so search shows its work. Empty when not searching.
  final String query;
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
    final highlight = TextStyle(
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.25),
      fontWeight: FontWeight.w600,
    );
    // While searching, prefer an excerpt around the body match over the plain
    // first-line preview, so a hit buried mid-note is actually visible.
    final snippet = searchSnippet(note.body, query);
    final previewText = snippet ??
        (note.preview.isEmpty ? 'No additional text' : note.preview);
    return ListTile(
      selected: selected,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.10),
      title: Text.rich(
        TextSpan(
          children:
              highlightMatches(note.displayTitle, query, highlight: highlight),
        ),
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
            child: Text.rich(
              TextSpan(
                children:
                    highlightMatches(previewText, query, highlight: highlight),
              ),
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

/// [text] split into spans with every case-insensitive occurrence of [query]
/// styled by [highlight]. A single unstyled span when the (trimmed) query is
/// empty or nothing matches.
List<TextSpan> highlightMatches(String text, String query,
    {required TextStyle highlight}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty || text.isEmpty) return [TextSpan(text: text)];
  final lower = text.toLowerCase();
  final spans = <TextSpan>[];
  var from = 0;
  while (true) {
    final at = lower.indexOf(q, from);
    if (at < 0) break;
    if (at > from) spans.add(TextSpan(text: text.substring(from, at)));
    spans.add(
        TextSpan(text: text.substring(at, at + q.length), style: highlight));
    from = at + q.length;
  }
  if (spans.isEmpty) return [TextSpan(text: text)];
  if (from < text.length) spans.add(TextSpan(text: text.substring(from)));
  return spans;
}

/// A single-line excerpt of [body] around its first case-insensitive match of
/// [query], or null when the (trimmed) query is empty or absent from the body.
/// Used in place of the first-line preview while searching. When the match
/// sits deep in its line, the excerpt starts shortly before it (with a leading
/// ellipsis) so the match survives the row's single-line truncation.
String? searchSnippet(String body, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return null;
  final at = body.toLowerCase().indexOf(q);
  if (at < 0) return null;
  // The query comes from a single-line field, so the match sits within one
  // line of the body.
  final lineStart = body.lastIndexOf('\n', at) + 1;
  final lineEnd = body.indexOf('\n', at);
  final line = body.substring(lineStart, lineEnd < 0 ? body.length : lineEnd);
  final trimmed = line.trimLeft();
  final matchAt = at - lineStart - (line.length - trimmed.length);
  const keepBefore = 16;
  if (matchAt > 24) return '…${trimmed.substring(matchAt - keepBefore)}';
  return trimmed.trimRight();
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
