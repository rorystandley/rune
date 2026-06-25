import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/platform/app_paths.dart';
import 'package:notes_core/notes_core.dart';

void main() {
  test(
    'transcribes the bundled JFK sample with whisper.cpp',
    () async {
      final paths = await AppPaths.resolve();
      final modelPath = await _copyAsset(
        paths,
        assetPath: 'assets/models/ggml-tiny.en-q5_1.bin',
        fileName: 'ggml-tiny.en-q5_1.bin',
      );
      final wavPath = await _copyFixtureWav(paths);
      final service = WhisperTranscriptionService(modelPath: modelPath);
      addTearDown(service.dispose);

      final result = await service.transcribe(
        TranscriptionRequest(audioFilePath: wavPath, languageHint: 'en'),
      );

      expect(result.isStub, isFalse);
      expect(result.text.toLowerCase(), contains('ask not'));
      expect(result.text.toLowerCase(), contains('country'));
    },
    // Host runs (macOS) pass the flag via the process environment; on-device
    // runs (Android/iOS) don't inherit the host env, so also honour a
    // compile-time --dart-define=RUNE_RUN_WHISPER_TEST=true.
    skip: (Platform.environment['RUNE_RUN_WHISPER_TEST'] == '1' ||
            const bool.fromEnvironment('RUNE_RUN_WHISPER_TEST'))
        ? false
        : 'Requires local whisper.cpp native library and bundled model.',
    tags: const ['whisper'],
    // Debug-built native whisper.cpp is unoptimised and slow on mobile CPUs;
    // release builds are far faster. Allow ample time for the opt-in run.
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<String> _copyFixtureWav(AppPaths paths) async {
  return _copyAsset(
    paths,
    assetPath: 'integration_test/fixtures/jfk.wav',
    fileName: 'jfk.wav',
  );
}

Future<String> _copyAsset(
  AppPaths paths, {
  required String assetPath,
  required String fileName,
}) async {
  final targetDir = Directory('${paths.tempAudioDir.path}/fixtures');
  await targetDir.create(recursive: true);
  final data = await rootBundle.load(assetPath);
  final file = File('${targetDir.path}/$fileName');
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
