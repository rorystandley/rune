import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

/// A deliberately small, read-only Markdown renderer for the editor's optional
/// preview mode: headings, bulleted / numbered lists, links, and tappable
/// `- [ ]` checkboxes. Nothing more — the editor stays plain text and WYSIWYG
/// stays out (see the roadmap's non-goals). Hand-rolled rather than a
/// dependency to keep the low-dependency posture.
///
/// Tapping a checkbox flips the underlying `[ ]`/`[x]` marker in the note body
/// and reports the whole updated body through [onBodyChanged]. Tapping a link
/// copies its URL to the clipboard — the app never opens a browser itself.
class MarkdownPreview extends StatefulWidget {
  const MarkdownPreview({super.key, required this.body, this.onBodyChanged});

  final String body;

  /// Receives the full body text after a checkbox toggle. Null renders the
  /// checkboxes disabled.
  final ValueChanged<String>? onBodyChanged;

  @override
  State<MarkdownPreview> createState() => _MarkdownPreviewState();
}

class _MarkdownPreviewState extends State<MarkdownPreview> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  /// Recognizers belong to the spans of a single build; retire the previous
  /// build's set once its frame is gone.
  void _retireRecognizers() {
    final old = List.of(_recognizers);
    _recognizers.clear();
    if (old.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final r in old) {
        r.dispose();
      }
    });
  }

  void _copyLink(String url) {
    unawaited(Clipboard.setData(ClipboardData(text: url)));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  @override
  Widget build(BuildContext context) {
    _retireRecognizers();
    final theme = Theme.of(context);
    final lines = parseMarkdown(widget.body);
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: lines.length,
      itemBuilder: (context, i) => _line(theme, lines[i]),
    );
  }

  Widget _line(ThemeData theme, MarkdownLine line) {
    final body = theme.textTheme.bodyLarge?.copyWith(height: 1.4);
    switch (line.kind) {
      case MarkdownLineKind.blank:
        return const SizedBox(height: 12);
      case MarkdownLineKind.heading:
        final style = switch (line.level) {
          1 => theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
          2 => theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          _ => theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        };
        return Padding(
          padding: EdgeInsets.only(top: line.index == 0 ? 0 : 12, bottom: 4),
          child: _rich(theme, line.text, style),
        );
      case MarkdownLineKind.bullet:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('  •  ', style: body),
              Expanded(child: _rich(theme, line.text, body)),
            ],
          ),
        );
      case MarkdownLineKind.numbered:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('  ${line.ordinal}.  ', style: body),
              Expanded(child: _rich(theme, line.text, body)),
            ],
          ),
        );
      case MarkdownLineKind.task:
        final done = line.checked;
        final style = done
            ? body?.copyWith(
                color: theme.hintColor, decoration: TextDecoration.lineThrough)
            : body;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 28,
              width: 36,
              child: Checkbox(
                value: done,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: widget.onBodyChanged == null
                    ? null
                    : (_) => widget.onBodyChanged!(
                        toggleTask(widget.body, line.index)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: _rich(theme, line.text, style),
              ),
            ),
          ],
        );
      case MarkdownLineKind.paragraph:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: _rich(theme, line.text, body),
        );
    }
  }

  /// The line's text with `[label](url)` runs turned into tappable links.
  Widget _rich(ThemeData theme, String text, TextStyle? style) {
    final spans = <InlineSpan>[];
    var from = 0;
    for (final m in _linkPattern.allMatches(text)) {
      if (m.start > from) spans.add(TextSpan(text: text.substring(from, m.start)));
      final url = m.group(2)!;
      final recognizer = TapGestureRecognizer()..onTap = () => _copyLink(url);
      _recognizers.add(recognizer);
      spans.add(TextSpan(
        text: m.group(1),
        style: TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: theme.colorScheme.primary,
        ),
        recognizer: recognizer,
      ));
      from = m.end;
    }
    if (spans.isEmpty) return Text(text, style: style);
    if (from < text.length) spans.add(TextSpan(text: text.substring(from)));
    return Text.rich(TextSpan(children: spans), style: style);
  }
}

final RegExp _linkPattern = RegExp(r'\[([^\]]+)\]\(([^)\s]+)\)');
final RegExp _headingPattern = RegExp(r'^(#{1,6})\s+(.*)$');
final RegExp _taskPattern = RegExp(r'^\s*[-*]\s+\[( |x|X)\]\s*(.*)$');
final RegExp _bulletPattern = RegExp(r'^\s*[-*]\s+(.*)$');
final RegExp _numberedPattern = RegExp(r'^\s*(\d{1,3})[.)]\s+(.*)$');

enum MarkdownLineKind { heading, bullet, numbered, task, paragraph, blank }

/// One classified line of a note body. [index] is the line's position in the
/// body (split on `\n`), which is how a checkbox toggle addresses its line.
class MarkdownLine {
  const MarkdownLine({
    required this.kind,
    required this.index,
    this.text = '',
    this.level = 0,
    this.checked = false,
    this.ordinal = '',
  });

  final MarkdownLineKind kind;
  final int index;
  final String text;

  /// Heading depth, 1–6.
  final int level;

  /// Whether a task line is ticked (`[x]`).
  final bool checked;

  /// The number in front of a numbered item, as written.
  final String ordinal;
}

/// Line-by-line classification of [body]. Purely lexical — no nesting, no
/// multi-line constructs — which keeps it predictable on note-style text.
List<MarkdownLine> parseMarkdown(String body) {
  final lines = body.split('\n');
  return [for (var i = 0; i < lines.length; i++) _parseLine(lines[i], i)];
}

MarkdownLine _parseLine(String line, int index) {
  if (line.trim().isEmpty) {
    return MarkdownLine(kind: MarkdownLineKind.blank, index: index);
  }
  final heading = _headingPattern.firstMatch(line);
  if (heading != null) {
    return MarkdownLine(
      kind: MarkdownLineKind.heading,
      index: index,
      level: heading.group(1)!.length,
      text: heading.group(2)!,
    );
  }
  final task = _taskPattern.firstMatch(line);
  if (task != null) {
    return MarkdownLine(
      kind: MarkdownLineKind.task,
      index: index,
      checked: task.group(1)!.toLowerCase() == 'x',
      text: task.group(2)!,
    );
  }
  final bullet = _bulletPattern.firstMatch(line);
  if (bullet != null) {
    return MarkdownLine(
      kind: MarkdownLineKind.bullet,
      index: index,
      text: bullet.group(1)!,
    );
  }
  final numbered = _numberedPattern.firstMatch(line);
  if (numbered != null) {
    return MarkdownLine(
      kind: MarkdownLineKind.numbered,
      index: index,
      ordinal: numbered.group(1)!,
      text: numbered.group(2)!,
    );
  }
  return MarkdownLine(
    kind: MarkdownLineKind.paragraph,
    index: index,
    text: line,
  );
}

/// [body] with the task checkbox on line [lineIndex] flipped between `[ ]`
/// and `[x]`. Returns [body] unchanged when the line isn't a task.
String toggleTask(String body, int lineIndex) {
  final lines = body.split('\n');
  if (lineIndex < 0 || lineIndex >= lines.length) return body;
  final m = RegExp(r'^(\s*[-*]\s+\[)( |x|X)(\].*)$').firstMatch(lines[lineIndex]);
  if (m == null) return body;
  final flipped = m.group(2) == ' ' ? 'x' : ' ';
  lines[lineIndex] = '${m.group(1)!}$flipped${m.group(3)!}';
  return lines.join('\n');
}
