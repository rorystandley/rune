import 'package:flutter/material.dart';
import 'package:notes_core/notes_core.dart';

/// Tap-to-open sheet with a note's created/modified timestamps, word count,
/// character count, and reading time.
///
/// [live] is the editor's current (possibly not-yet-autosaved) text, so the
/// counts track what's on screen rather than trailing the debounced autosave;
/// when null the persisted note is used. Timestamps always come from the
/// persisted [note] — an unsaved keystroke hasn't modified the note yet.
Future<void> showNoteInfoSheet(
  BuildContext context, {
  required Note note,
  ({String title, String body})? live,
}) {
  final current =
      live == null ? note : note.copyWith(title: live.title, body: live.body);
  final words = countWords(current.body);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                current.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Divider(),
              _InfoRow(label: 'Words', value: '$words'),
              _InfoRow(
                  label: 'Characters', value: '${current.body.runes.length}'),
              _InfoRow(label: 'Reading time', value: readingTimeLabel(words)),
              const Divider(),
              _InfoRow(
                  label: 'Created', value: formatFullTimestamp(note.createdAt)),
              _InfoRow(
                  label: 'Modified',
                  value: formatFullTimestamp(note.updatedAt)),
            ],
          ),
        ),
      );
    },
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            ),
          ),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Whitespace-separated word count of [text].
int countWords(String text) {
  var count = 0;
  for (final token in text.split(RegExp(r'\s+'))) {
    if (token.isNotEmpty) count++;
  }
  return count;
}

/// Reading time at a ~200 words-per-minute pace: "~N min", never less than a
/// minute for a non-empty note, an em dash for an empty one.
String readingTimeLabel(int words) {
  if (words == 0) return '—';
  return '~${(words / 200).ceil()} min';
}

/// Full, locale-agnostic timestamp for the info sheet, e.g. "11 Jul 2026, 17:22".
String formatFullTimestamp(DateTime when) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final l = when.toLocal();
  final h = l.hour.toString().padLeft(2, '0');
  final m = l.minute.toString().padLeft(2, '0');
  return '${l.day} ${months[l.month - 1]} ${l.year}, $h:$m';
}
