import 'dart:io';

import 'package:flutter/services.dart';
import 'package:notes_core/notes_core.dart';

import 'app_paths.dart';

const String _whisperModelAsset = 'assets/models/ggml-tiny.en-q5_1.bin';
const String _whisperModelFileName = 'ggml-tiny.en-q5_1.bin';

Future<TranscriptionService> resolveTranscriptionService(AppPaths paths) async {
  if (!Platform.isMacOS && !Platform.isAndroid) {
    return const StubTranscriptionService();
  }

  final model = await _copyBundledWhisperModel(paths);
  final service = WhisperTranscriptionService(modelPath: model.path);
  if (await service.isAvailable()) return service;

  service.dispose();
  return const StubTranscriptionService();
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
