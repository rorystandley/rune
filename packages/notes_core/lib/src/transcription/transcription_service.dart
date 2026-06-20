/// Request to transcribe a recorded audio file.
class TranscriptionRequest {
  const TranscriptionRequest({required this.audioFilePath, this.languageHint});

  /// Path to a local audio file (e.g. WAV/M4A) to transcribe.
  final String audioFilePath;

  /// Optional BCP-47-ish language hint (e.g. "en"). Null = auto/engine default.
  final String? languageHint;
}

/// Result of a transcription attempt.
class TranscriptionResult {
  const TranscriptionResult({
    required this.text,
    required this.engine,
    this.isStub = false,
  });

  /// The transcribed text to insert into the note.
  final String text;

  /// Engine that produced it, for display ("whisper.cpp base.en", etc.).
  final String engine;

  /// True if produced by a placeholder rather than a real STT engine.
  final bool isStub;
}

/// Abstraction over a speech-to-text engine.
///
/// CONTRACT: implementations MUST run entirely on-device and make NO network
/// calls. A remote/cloud transcriber would violate the app's privacy promise
/// and must not be added behind this interface.
abstract class TranscriptionService {
  /// Human-readable engine name.
  String get engineName;

  /// Whether the engine runs fully locally. Must be true for this app.
  bool get isLocal;

  /// Whether the engine can transcribe on this device/build right now.
  Future<bool> isAvailable();

  Future<TranscriptionResult> transcribe(TranscriptionRequest request);
}
