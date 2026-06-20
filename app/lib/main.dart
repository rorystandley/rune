import 'package:flutter/material.dart';
import 'package:notes_core/notes_core.dart';

import 'app.dart';
import 'platform/app_paths.dart';
import 'platform/audio_recorder.dart';
import 'state/app_controller.dart';
import 'state/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final paths = await AppPaths.resolve();

  final controller = AppController(
    vaultDir: paths.vaultDir,
    audioTempDir: paths.tempAudioDir,
    exportsDir: paths.exportsBase,
    settingsStore: SettingsStore(paths.settingsFile),
    transcription: const StubTranscriptionService(),
    recorder: RecordAudioRecorder(),
  );
  await controller.init();

  runApp(NotesApp(controller: controller));
}
