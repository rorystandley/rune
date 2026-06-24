import 'package:flutter/material.dart';

import 'app.dart';
import 'platform/app_paths.dart';
import 'platform/audio_recorder.dart';
import 'platform/transcription_factory.dart';
import 'state/app_controller.dart';
import 'state/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final paths = await AppPaths.resolve();
  final transcription = await resolveTranscriptionService(paths);

  final controller = AppController(
    vaultDir: paths.vaultDir,
    audioTempDir: paths.tempAudioDir,
    exportsDir: paths.exportsBase,
    settingsStore: SettingsStore(paths.settingsFile),
    transcription: transcription,
    recorder: RecordAudioRecorder(),
  );
  await controller.init();

  runApp(NotesApp(controller: controller));
}
