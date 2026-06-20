import 'dart:io';

import 'package:notes_app/platform/audio_recorder.dart';
import 'package:notes_app/state/app_controller.dart';
import 'package:notes_app/state/app_settings.dart';
import 'package:notes_core/notes_core.dart';

/// Throwaway passphrase used only for the screenshot/demo vault. The vault lives
/// in a fresh temp directory and is never persisted with the app's real data.
const demoPassphrase = 'correct horse battery staple';

/// Builds an [AppController] backed by a temporary vault, unlocks it, and seeds
/// a handful of realistic demo notes so screens look populated for store
/// screenshots. Shared by [integration_test/screenshots_test.dart] (automated
/// capture) and [integration_test/demo_main.dart] (manual `flutter run`).
Future<AppController> buildSeededController() async {
  final tmp = await Directory.systemTemp.createTemp('notes_shots');
  Directory sub(String name) =>
      Directory('${tmp.path}/$name')..createSync(recursive: true);

  final controller = AppController(
    vaultDir: sub('vault'),
    audioTempDir: sub('audio'),
    exportsDir: sub('exports'),
    settingsStore: SettingsStore(File('${tmp.path}/settings.json')),
    transcription: const StubTranscriptionService(),
    recorder: RecordAudioRecorder(),
  );

  await controller.init();
  await controller.createVault(demoPassphrase);

  // Saved in order; the list shows most-recent first, so the hero note (saved
  // last) lands on top and is selected for the two-pane (tablet/desktop) view.
  const notes = <(String, String)>[
    (
      'Sourdough timings',
      'Levain 9pm · autolyse 8am · bulk 4h at 24°C\n'
          'Shape, fridge overnight, bake 250°C with steam.',
    ),
    (
      'Q3 planning',
      'Themes: reliability, fewer settings, faster unlock.\n'
          '- Calibrate Argon2id to ~750ms on-device\n'
          '- Reproducible builds\n'
          '- Encrypted attachments',
    ),
    (
      'Reading list',
      '· The Order of Time\n· Project Hail Mary\n· Thinking in Systems',
    ),
    (
      'Lisbon trip',
      'Tram 28 early to beat crowds. Time Out Market for lunch.\n'
          'Sunset at Miradouro da Senhora do Monte.',
    ),
    (
      'Welcome to Notes',
      'Everything you write here is encrypted on this device with your '
          'passphrase — using AES-GCM and Argon2id.\n\n'
          'No account. No cloud. No telemetry. The app works fully offline, '
          'and only ciphertext ever touches the disk.',
    ),
  ];

  String? heroId;
  for (final (title, body) in notes) {
    final note = await controller.newNote();
    await controller.saveNote(note.id, title: title, body: body);
    heroId = note.id;
  }
  controller.selectNote(heroId);

  return controller;
}
