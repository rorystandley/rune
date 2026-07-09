import 'package:flutter/material.dart';
import 'package:notes_core/notes_core.dart';

import '../../state/app_scope.dart';
import '../widgets/dialogs.dart';
import '../widgets/note_list.dart' show formatNoteDate;

/// The Recently Deleted view: soft-deleted notes awaiting restore or permanent
/// purge. Notes land here from the editor's delete action and leave either by
/// being restored, purged, or ageing out after the retention window.
class RecentlyDeletedScreen extends StatelessWidget {
  const RecentlyDeletedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final notes = controller.deletedNotes;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recently Deleted'),
        actions: [
          if (notes.isNotEmpty)
            TextButton(
              onPressed: () => _emptyAll(context),
              child: const Text('Empty'),
            ),
        ],
      ),
      body: notes.isEmpty
          ? _empty(theme)
          : Column(
              children: [
                _RetentionBanner(retention: controller.recentlyDeletedRetention),
                Expanded(
                  child: ListView.separated(
                    itemCount: notes.length,
                    separatorBuilder: (_, _) =>
                        const Divider(indent: 16, endIndent: 16, height: 0.5),
                    itemBuilder: (context, i) =>
                        _DeletedTile(note: notes[i]),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _empty(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nothing here.\nDeleted notes appear here before they are removed for good.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
        ),
      );

  Future<void> _emptyAll(BuildContext context) async {
    final controller = AppScope.of(context);
    final ok = await confirmDestructive(
      context,
      title: 'Empty Recently Deleted?',
      message:
          'This permanently removes every note here. This cannot be undone.',
      confirmLabel: 'Delete All',
    );
    if (ok) await controller.emptyRecentlyDeleted();
  }
}

class _RetentionBanner extends StatelessWidget {
  const _RetentionBanner({required this.retention});
  final Duration retention;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: theme.hintColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Notes are deleted permanently after ${retention.inDays} days.',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeletedTile extends StatelessWidget {
  const _DeletedTile({required this.note});
  final Note note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(
        note.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        'Deleted ${formatNoteDate(note.deletedAt!)}',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
      ),
      onTap: () => _showActions(context),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    final controller = AppScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restore'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller.restoreNote(note.id);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_forever,
                  color: Theme.of(sheetContext).colorScheme.error),
              title: const Text('Delete forever'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final ok = await confirmDestructive(
                  context,
                  title: 'Delete forever?',
                  message:
                      'This permanently removes the note. This cannot be undone.',
                  confirmLabel: 'Delete',
                );
                if (ok) await controller.purgeNote(note.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}
