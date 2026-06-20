import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:notes_core/notes_core.dart';

import '../../state/app_controller.dart';
import '../../state/app_scope.dart';

/// Opens the voice-note flow: record locally → transcribe locally → insert into
/// a new note → delete the raw audio by default. Returns the new note's id if
/// one was created.
Future<void> showVoiceNoteSheet(BuildContext context) {
  final controller = AppScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _VoiceNoteSheet(controller: controller),
  );
}

enum _Stage { checking, unsupported, idle, recording, transcribing, failed }

class _VoiceNoteSheet extends StatefulWidget {
  const _VoiceNoteSheet({required this.controller});

  final AppController controller;

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

  AppController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final supported = await _c.recorder.isSupported();
    if (!mounted) return;
    setState(() => _stage = supported ? _Stage.idle : _Stage.unsupported);
  }

  Future<void> _startRecording() async {
    if (!await _c.recorder.hasPermission()) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _message = 'Microphone permission was not granted.';
      });
      return;
    }
    await _c.audioTempDir.create(recursive: true);
    final path = '${_c.audioTempDir.path}/voice-${DateTime.now().millisecondsSinceEpoch}.wav';
    await _c.recorder.start(path);
    if (!mounted) return;
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
    _ticker?.cancel();
    setState(() => _stage = _Stage.transcribing);
    final recordedPath = await _c.recorder.stop() ?? _audioPath;

    var inserted = false;
    try {
      final result = await _c.transcription.transcribe(
        TranscriptionRequest(audioFilePath: recordedPath ?? '', languageHint: 'en'),
      );
      final note = await _c.newNote();
      await _c.saveNote(note.id, title: 'Voice note', body: result.text);
      inserted = true;

      if (!_keepAudio && recordedPath != null) {
        final f = File(recordedPath);
        if (await f.exists()) await f.delete();
      }
    } finally {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(inserted
                ? (_keepAudio
                    ? 'Voice note added. Audio kept locally.'
                    : 'Voice note added. Audio discarded.')
                : 'Could not create the voice note.'),
          ),
        );
      }
    }
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
          _stubNotice(theme),
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

  Widget _stubNotice(ThemeData theme) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Note: transcription uses a placeholder in this build. '
          'See docs/transcription.md to enable on-device whisper.cpp.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
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
