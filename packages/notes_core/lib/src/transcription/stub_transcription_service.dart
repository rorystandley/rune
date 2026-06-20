import 'transcription_service.dart';

/// A clearly-marked placeholder that performs NO real transcription.
///
/// It exists so the whole voice-note flow (record → transcribe → insert →
/// discard audio by default) works end-to-end today, and so a real on-device
/// engine can be dropped in behind [TranscriptionService] without touching the
/// UI. See `docs/transcription.md` for how to wire in whisper.cpp.
///
/// This is honest by design: the inserted text states plainly that no real STT
/// ran, rather than pretending to have transcribed audio.
class StubTranscriptionService implements TranscriptionService {
  const StubTranscriptionService();

  @override
  String get engineName => 'stub (no real STT wired)';

  @override
  bool get isLocal => true;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    final stamp = DateTime.now().toUtc().toIso8601String();
    return TranscriptionResult(
      engine: engineName,
      isStub: true,
      text: '[Voice note recorded $stamp]\n\n'
          '_Local transcription is not wired up in this build. The audio was '
          'captured locally; see docs/transcription.md to enable on-device '
          'whisper.cpp transcription._',
    );
  }
}
