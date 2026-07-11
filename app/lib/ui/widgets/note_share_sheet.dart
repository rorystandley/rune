import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:notes_core/notes_core.dart';
import 'package:share_plus/share_plus.dart';

import '../../state/app_scope.dart';

/// Share / export options for a single note: the native share sheet, copy as
/// text, or an encrypted single-note export (same format as a full backup).
///
/// [live] is the editor's current text (see the note-info sheet); sharing and
/// copying use it so what leaves the app is what's on screen. The encrypted
/// export reads the stored blob, so any live text is saved first — the export
/// can never miss the last keystrokes to the autosave debounce.
Future<void> showNoteShareSheet(
  BuildContext context, {
  required Note note,
  ({String title, String body})? live,
}) {
  final controller = AppScope.of(context);
  final title = (live?.title ?? note.title).trim();
  final body = live?.body ?? note.body;
  final text = title.isEmpty ? body : '$title\n\n$body';
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('share-as-text'),
            leading: const Icon(Icons.ios_share),
            title: const Text('Share as text'),
            subtitle: const Text('Sends the note as plain, readable text'),
            onTap: () {
              // Anchor the share popover to the sheet (iPad/macOS need a
              // source rect), then close the sheet.
              final box = sheetContext.findRenderObject() as RenderBox?;
              final origin = box == null
                  ? null
                  : box.localToGlobal(Offset.zero) & box.size;
              Navigator.of(sheetContext).pop();
              SharePlus.instance.share(
                ShareParams(text: text, sharePositionOrigin: origin),
              );
            },
          ),
          ListTile(
            key: const Key('copy-as-text'),
            leading: const Icon(Icons.copy_outlined),
            title: const Text('Copy as text'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(content: Text('Note copied')));
            },
          ),
          ListTile(
            key: const Key('export-encrypted-note'),
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Export encrypted copy'),
            subtitle: const Text(
              'Safe: stays encrypted, needs your passphrase',
            ),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              try {
                if (live != null) {
                  await controller.saveNote(
                    note.id,
                    title: live.title,
                    body: live.body,
                  );
                }
                final file = await controller.exportEncryptedNote(note.id);
                if (context.mounted) {
                  await _showExportedPath(context, file.path);
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Export failed.')),
                  );
                }
              }
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _showExportedPath(BuildContext context, String path) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Encrypted note saved'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Saved to:'),
          const SizedBox(height: 8),
          SelectableText(path, style: Theme.of(ctx).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
