import 'package:record/record.dart';

/// Thin port over the microphone so the voice-note UI can be tested and so the
/// app degrades gracefully where recording is unavailable. All capture is
/// local; nothing is uploaded.
abstract class AudioRecorderPort {
  /// Whether recording is possible on this platform/build at all.
  Future<bool> isSupported();

  /// Whether microphone permission is granted (requests it if needed).
  Future<bool> hasPermission();

  /// Starts recording to [filePath].
  Future<void> start(String filePath);

  /// Stops and returns the recorded file path (or null if nothing recorded).
  Future<String?> stop();

  Future<bool> isRecording();
  Future<void> dispose();
}

/// Real recorder backed by the `record` package. Captures 16 kHz mono WAV,
/// which is exactly what whisper.cpp expects (see docs/transcription.md).
class RecordAudioRecorder implements AudioRecorderPort {
  RecordAudioRecorder();

  final AudioRecorder _recorder = AudioRecorder();

  static const RecordConfig _config = RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: 16000,
    numChannels: 1,
  );

  @override
  Future<bool> isSupported() async {
    try {
      // Probing the platform throws MissingPluginException where unsupported.
      await _recorder.isRecording();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> start(String filePath) =>
      _recorder.start(_config, path: filePath);

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<bool> isRecording() async {
    try {
      return await _recorder.isRecording();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}

/// A recorder that reports itself unavailable. Used in tests and on platforms
/// without a microphone plugin.
class UnavailableAudioRecorder implements AudioRecorderPort {
  const UnavailableAudioRecorder();

  @override
  Future<bool> isSupported() async => false;
  @override
  Future<bool> hasPermission() async => false;
  @override
  Future<void> start(String filePath) async {}
  @override
  Future<String?> stop() async => null;
  @override
  Future<bool> isRecording() async => false;
  @override
  Future<void> dispose() async {}
}
