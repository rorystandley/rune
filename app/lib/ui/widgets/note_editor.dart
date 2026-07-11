import 'dart:async';

import 'package:flutter/material.dart';
import 'package:notes_core/notes_core.dart';

import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import 'markdown_preview.dart';

/// The title + body editor with debounced autosave.
///
/// Seeded once from [note]; thereafter it owns its text so external rebuilds
/// never clobber the cursor. Switch notes by giving it a `ValueKey(note.id)` so
/// Flutter rebuilds the state for the new note.
/// Bridges the editor's chrome (app bar / toolbar) to the live body field so a
/// voice-note transcription inserts into the open note, rather than persisting
/// behind the editor's back where the debounced autosave would clobber it. The
/// mounted editor attaches its insert function; callers invoke [insert].
class EditorInsertHandle {
  void Function(String text)? _insert;
  ({String title, String body}) Function()? _read;

  /// Whether an editor is currently mounted and listening.
  bool get isAttached => _insert != null;

  /// Inserts [text] into the open editor body, if one is mounted.
  void insert(String text) => _insert?.call(text);

  /// The editor's current (possibly not-yet-autosaved) title and body, or null
  /// when no editor is mounted. Lets chrome like the note-info sheet report on
  /// what's on screen instead of trailing the debounced autosave.
  ({String title, String body})? readCurrent() => _read?.call();
}

class NoteEditorView extends StatefulWidget {
  const NoteEditorView(
      {super.key, required this.note, this.insertHandle, this.readMode = false});

  final Note note;

  /// Optional bridge letting the surrounding chrome insert into the live body.
  final EditorInsertHandle? insertHandle;

  /// When true, the body renders as a read-only Markdown preview (headings,
  /// lists, links, tappable checkboxes) instead of the text field. Off by
  /// default — the editor itself always stays plain text.
  final bool readMode;

  @override
  State<NoteEditorView> createState() => _NoteEditorViewState();
}

class _NoteEditorViewState extends State<NoteEditorView> {
  late final TextEditingController _title =
      TextEditingController(text: widget.note.title);
  late final TextEditingController _body =
      TextEditingController(text: widget.note.body);
  Timer? _debounce;
  AppController? _controller;

  static const Duration _debounceDelay = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();
    widget.insertHandle?._insert = _insertTranscript;
    widget.insertHandle?._read = _readCurrent;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = AppScope.of(context);
  }

  @override
  void dispose() {
    if (identical(widget.insertHandle?._insert, _insertTranscript)) {
      widget.insertHandle?._insert = null;
    }
    if (identical(widget.insertHandle?._read, _readCurrent)) {
      widget.insertHandle?._read = null;
    }
    _debounce?.cancel();
    _flush(); // best-effort save of any pending edits
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  ({String title, String body}) _readCurrent() =>
      (title: _title.text, body: _body.text);

  /// Inserts [text] at the cursor (or appends), on its own line when there is
  /// preceding content, then schedules the normal debounced autosave.
  void _insertTranscript(String text) {
    final addition = text.trim();
    if (addition.isEmpty) return;
    final existing = _body.text;
    final sel = _body.selection;
    final at = (sel.isValid && sel.start >= 0 && sel.start <= existing.length)
        ? sel.start
        : existing.length;
    final before = existing.substring(0, at);
    final after = existing.substring(at);
    final piece =
        before.isEmpty || before.endsWith('\n') ? addition : '\n$addition';
    _body.value = TextEditingValue(
      text: '$before$piece$after',
      selection: TextSelection.collapsed(offset: (before + piece).length),
    );
    // The preview renders from _body.text at build time, so it needs a nudge —
    // the text field variant listens to the controller directly.
    if (widget.readMode) setState(() {});
    _onChanged();
  }

  void _onChanged() {
    _controller?.onUserActivity();
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, _flush);
  }

  void _flush() {
    _debounce?.cancel();
    final controller = _controller;
    if (controller == null) return;
    unawaited(controller.saveNote(
      widget.note.id,
      title: _title.text,
      body: _body.text,
    ));
  }

  /// Comfortable reading measure for the title/body text; on wide screens the
  /// content stops stretching edge-to-edge and stays centred within this width.
  static const double _maxContentWidth = 720;

  /// Base side gutter kept on every screen width, on both sides.
  static const double _sideGutter = 20;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Centre the content by padding the sides once the *content* (i.e.
        // excluding the two base gutters) would exceed the reading measure.
        // Padding (not Center/Align) keeps the Column's height tight so its
        // Expanded body still lays out.
        final overflow =
            constraints.maxWidth - _maxContentWidth - 2 * _sideGutter;
        final sidePad = overflow > 0 ? overflow / 2 : 0.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(
              _sideGutter + sidePad, 12, _sideGutter + sidePad, 12),
          child: _buildEditor(theme),
        );
      },
    );
  }

  Widget _buildEditor(ThemeData theme) {
    if (widget.readMode) return _buildPreview(theme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('editor-title'),
          controller: _title,
          onChanged: (_) => _onChanged(),
          textCapitalization: TextCapitalization.sentences,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
          decoration: const InputDecoration(
            hintText: 'Title',
            border: InputBorder.none,
            isCollapsed: true,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TextField(
            key: const Key('editor-body'),
            controller: _body,
            onChanged: (_) => _onChanged(),
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
            decoration: const InputDecoration(
              hintText: 'Start writing…',
              border: InputBorder.none,
              isCollapsed: true,
            ),
          ),
        ),
      ],
    );
  }

  /// Read mode: the same title/body content, rendered instead of editable.
  /// Checkbox toggles rewrite the live body and go through the normal
  /// debounced autosave — the only mutation preview mode allows.
  Widget _buildPreview(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_title.text.trim().isNotEmpty) ...[
          Text(
            _title.text,
            style:
                theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: MarkdownPreview(
            body: _body.text,
            onBodyChanged: (next) {
              setState(() => _body.text = next);
              _onChanged();
            },
          ),
        ),
      ],
    );
  }
}
