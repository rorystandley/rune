import 'dart:io';

import 'package:flutter/services.dart';
import 'package:notes_core/notes_core.dart';

import 'app_paths.dart';

const String _whisperModelAsset = 'assets/models/ggml-tiny.en-q5_1.bin';
const String _whisperModelFileName = 'ggml-tiny.en-q5_1.bin';

/// Resolves the on-device transcription engine for this platform, or `null`
/// when the platform has no bundled engine.
///
/// whisper.cpp is bundled and verified on macOS, Android, and iOS. Everywhere
/// else there is no local STT, so this returns `null` and the voice-note UI is
/// disabled — we deliberately do NOT fall back to a placeholder that writes
/// fake "[Voice note recorded …]" text into a real note. If whisper is present
/// but fails to load at runtime, the failure surfaces as an honest error in the
/// voice sheet rather than being silently swallowed.
Future<TranscriptionService?> resolveTranscriptionService(AppPaths paths) async {
  if (!Platform.isMacOS && !Platform.isAndroid && !Platform.isIOS) {
    return null;
  }

  final model = await _copyBundledWhisperModel(paths);
  return WhisperTranscriptionService(modelPath: model.path);
}

Future<File> _copyBundledWhisperModel(AppPaths paths) async {
  final data = await rootBundle.load(_whisperModelAsset);
  final bytes = _bytesFrom(data);
  await paths.modelsDir.create(recursive: true);

  final model = File('${paths.modelsDir.path}/$_whisperModelFileName');
  if (await model.exists() && await model.length() == bytes.length) {
    return model;
  }

  await model.writeAsBytes(bytes, flush: true);
  return model;
}

Uint8List _bytesFrom(ByteData data) =>
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
