import 'package:notes_core/notes_core.dart';
import 'package:test/test.dart';

void main() {
  test('whisper transcription service is local and unavailable without model',
      () async {
    final service = WhisperTranscriptionService(
      modelPath: '__missing_model__.bin',
      libraryPathResolver: () => '__missing_library__.dylib',
    );

    expect(service.engineName, contains('whisper.cpp'));
    expect(service.isLocal, isTrue);
    expect(await service.isAvailable(), isFalse);

    service.dispose();
  });
}
