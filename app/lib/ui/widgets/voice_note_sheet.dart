import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:notes_core/notes_core.dart';

import '../../state/app_controller.dart';
import '../../state/app_scope.dart';

/// Opens the voice-note flow: record locally → transcribe locally → delete the
/// raw audio by default.
///
/// When [onTranscribed] is given (the editor's mic), the transcript is inserted
/// into the open note via that callback. Otherwise (the home/sidebar mic) a new
/// note is created from the transcript.
Future<void> showVoiceNoteSheet(
  BuildContext context, {
  ValueChanged<String>? onTranscribed,
}) {
  final controller = AppScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _VoiceNoteSheet(controller: controller, onTranscribed: onTranscribed),
  );
}

enum _Stage { checking, unsupported, idle, recording, transcribing, failed }

class _VoiceNoteSheet extends StatefulWidget {
  const _VoiceNoteSheet({required this.controller, this.onTranscribed});

  final AppController controller;

  /// When set, the transcript is handed here (insert into the open note)
  /// instead of creating a new note.
  final ValueChanged<String>? onTranscribed;

  @override
  State<_VoiceNoteSheet> createState() => _VoiceNoteSheetState();
}

class _VoiceNoteSheetState extends State<_VoiceNoteSheet> {
  _Stage _stage = _Stage.checking;
  String? _audioPath;
  String? _message;
  late bool _keepAudio = widget.controller.settings.keepAudioByDefault;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  /// Bumped when the sheet is dismissed or the vault locks, so an in-flight
  /// permission check or transcription cannot start or keep a capture.
  int _session = 0;
  bool _sessionClosed = false;

  /// Set only after transcription finishes with "keep audio" on, so closing
  /// the sheet does not delete that recording.
  bool _retainOnClose = false;

  AppController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
    _check();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _closeSession();
    super.dispose();
  }

  void _onController() {
    if (widget.controller.phase == AppPhase.unlocked) return;
    if (!mounted) return;
    // Capture the route before closing. removeRoute drops the sheet even when
    // app-lifecycle pause has stopped route animations, so the lock screen is
    // what remains.
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    _closeSession();
    if (route != null && route.isActive) {
      navigator.removeRoute(route);
    }
  }

  bool _sessionOpen(int session) =>
      !_sessionClosed &&
      mounted &&
      session == _session &&
      widget.controller.phase == AppPhase.unlocked;

  /// Stops the microphone and deletes the in-progress file. Safe to call more
  /// than once. Does not remove a recording the user already chose to keep.
  void _closeSession() {
    if (_sessionClosed) return;
    _sessionClosed = true;
    _session++;
    _ticker?.cancel();
    _ticker = null;
    final deleteFile = !_retainOnClose;
    final path = deleteFile ? _audioPath : null;
    _audioPath = null;
    unawaited(_stopRecorderAndDelete(path, delete: deleteFile));
  }

  Future<void> _check() async {
    // Voice notes need both a working recorder and an on-device transcription
    // engine. Platforms without a bundled engine (transcription == null) show
    // the unsupported state rather than recording audio we can't transcribe.
    final supported =
        _c.transcription != null && await _c.recorder.isSupported();
    if (!mounted) return;
    setState(() => _stage = supported ? _Stage.idle : _Stage.unsupported);
  }

  Future<void> _startRecording() async {
    final session = _session;
    if (!await _c.recorder.hasPermission()) {
      if (!_sessionOpen(session)) return;
      setState(() {
        _stage = _Stage.failed;
        _message = 'Microphone permission was not granted.';
      });
      return;
    }
    // Re-check after every await. The sheet may have been dismissed, or the
    // vault locked, while the permission prompt was up.
    if (!_sessionOpen(session)) return;
    await _c.audioTempDir.create(recursive: true);
    if (!_sessionOpen(session)) return;
    final path =
        '${_c.audioTempDir.path}/voice-${DateTime.now().millisecondsSinceEpoch}.wav';
    _audioPath = path;
    await _c.recorder.start(path);
    if (!_sessionOpen(session)) {
      await _stopRecorderAndDelete(path, delete: true);
      return;
    }
    setState(() {
      _audioPath = path;
      _stage = _Stage.recording;
      _elapsed = Duration.zero;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _stopAndTranscribe() async {
    final session = _session;
    _ticker?.cancel();
    _ticker = null;
    setState(() => _stage = _Stage.transcribing);
    final recordedPath = await _c.recorder.stop() ?? _audioPath;
    _audioPath = recordedPath;
    if (!_sessionOpen(session)) {
      await _stopRecorderAndDelete(recordedPath, delete: true);
      return;
    }

    final transcription = _c.transcription;
    if (transcription == null) {
      // Should be unreachable (the entry point is disabled), but never inject
      // placeholder text if we somehow get here.
      await _deleteAudio(recordedPath);
      if (_sessionOpen(session)) {
        setState(() {
          _stage = _Stage.failed;
          _message =
              'On-device transcription is not available on this platform.';
        });
      }
      return;
    }

    final appended = widget.onTranscribed != null;
    try {
      final result = await transcription.transcribe(
        TranscriptionRequest(
          audioFilePath: recordedPath ?? '',
          languageHint: 'en',
        ),
      );
      if (!_sessionOpen(session)) {
        await _deleteAudio(recordedPath);
        return;
      }
      if (widget.onTranscribed != null) {
        widget.onTranscribed!(result.text);
      } else {
        final note = await _c.newNote();
        await _c.saveNote(note.id, title: 'Voice note', body: result.text);
      }
      if (!_sessionOpen(session)) {
        await _deleteAudio(recordedPath);
        return;
      }

      if (_keepAudio) {
        _retainOnClose = true;
        await _retainAudio(recordedPath);
      } else {
        await _deleteAudio(recordedPath);
      }
      _audioPath = null;

      if (!_sessionOpen(session) || !mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      final where = appended ? 'Added to note.' : 'Voice note added.';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$where ${_keepAudio ? 'Audio kept locally.' : 'Audio discarded.'}',
          ),
        ),
      );
    } catch (_) {
      // On-device transcription failed to run. Surface an honest error rather
      // than writing placeholder text into the note.
      await _deleteAudio(recordedPath);
      if (!_sessionOpen(session)) return;
      setState(() {
        _stage = _Stage.failed;
        _message =
            'On-device transcription failed to run. Your recording was not '
            'added.';
      });
    }
  }

  /// Moves a finished recording aside so the unlock sweep keeps it.
  Future<void> _retainAudio(String? recordedPath) async {
    if (recordedPath == null) return;
    final file = File(recordedPath);
    try {
      if (!await file.exists()) return;
      final name = _audioBaseName(recordedPath);
      if (name.startsWith(AppController.keptAudioFilePrefix)) return;
      final dest = File(
        '${file.parent.path}/${AppController.keptAudioFilePrefix}$name',
      );
      await file.rename(dest.path);
    } catch (_) {
      // If the rename does not land, the temporary name is removed on the
      // next unlock.
    }
  }

  Future<void> _stopRecorderAndDelete(
    String? path, {
    required bool delete,
  }) async {
    try {
      if (await _c.recorder.isRecording()) {
        final stopped = await _c.recorder.stop();
        if (delete && path == null) path = stopped;
      }
    } catch (_) {
      // Stopping is best-effort. The unlock sweep removes a leftover file.
    }
    if (!delete) return;
    await _deleteAudio(path);
  }

  Future<void> _deleteAudio(String? path) async {
    if (path == null) return;
    if (_audioBaseName(path).startsWith(AppController.keptAudioFilePrefix)) {
      return;
    }
    final file = File(path);
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // The file may still be open. The next unlock tries again.
    }
  }

  String _audioBaseName(String path) {
    final separator = path.lastIndexOf(RegExp(r'[/\\]'));
    return separator == -1 ? path : path.substring(separator + 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.mic, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Voice note', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Recording and transcription happen on this device. '
              'Nothing is uploaded.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 20),
            ..._buildBody(theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBody(ThemeData theme) {
    switch (_stage) {
      case _Stage.checking:
        return const [Center(child: Padding(
          padding: EdgeInsets.all(16), child: CircularProgressIndicator()))];
      case _Stage.unsupported:
        return [
          _info(theme, Icons.mic_off,
              'Microphone recording is not available on this platform or build.'),
        ];
      case _Stage.failed:
        return [
          _info(theme, Icons.error_outline, _message ?? 'Something went wrong.'),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => setState(() => _stage = _Stage.idle),
            child: const Text('Try again'),
          ),
        ];
      case _Stage.idle:
        return [
          FilledButton.icon(
            onPressed: _startRecording,
            icon: const Icon(Icons.fiber_manual_record),
            label: const Text('Start recording'),
          ),
          const SizedBox(height: 8),
          _keepAudioToggle(),
        ];
      case _Stage.recording:
        return [
          Center(
            child: Text(_format(_elapsed),
                style: theme.textTheme.displaySmall
                    ?.copyWith(fontFeatures: const [])),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _stopAndTranscribe,
            icon: const Icon(Icons.stop),
            label: const Text('Stop & transcribe'),
          ),
          const SizedBox(height: 8),
          _keepAudioToggle(),
        ];
      case _Stage.transcribing:
        return const [
          Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Transcribing locally…'),
              ]),
            ),
          ),
        ];
    }
  }

  Widget _keepAudioToggle() => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _keepAudio,
        onChanged: (v) => setState(() => _keepAudio = v),
        title: const Text('Keep audio recording'),
        subtitle: const Text('Off = delete the audio after transcription'),
      );

  Widget _info(ThemeData theme, IconData icon, String text) => Row(
        children: [
          Icon(icon, color: theme.hintColor),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      );

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
