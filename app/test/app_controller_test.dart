import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/platform/audio_recorder.dart';
import 'package:notes_app/state/app_controller.dart';
import 'package:notes_app/state/app_settings.dart';
import 'package:notes_core/notes_core.dart';

void main() {
  late Directory root;
  late AppController controller;

  Future<AppController> buildController() async {
    final store = SettingsStore(File('${root.path}/settings.json'));
    // Disable auto-lock in tests so no Timer is left pending.
    await store.save(const AppSettings(autoLockMinutes: 0));
    final c = AppController(
      vaultDir: Directory('${root.path}/vault'),
      audioTempDir: Directory('${root.path}/audio'),
      exportsDir: Directory('${root.path}/exports'),
      settingsStore: store,
      transcription: const StubTranscriptionService(),
      recorder: const UnavailableAudioRecorder(),
      // Cheap KDF so tests are fast.
      createKdfParams: CryptoService()
          .newKdfParams(memoryKiB: 256, iterations: 1, parallelism: 1),
    );
    await c.init();
    return c;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('notes_app_test_');
    controller = await buildController();
  });

  tearDown(() async {
    controller.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('first launch starts in needsCreation', () {
    expect(controller.phase, AppPhase.needsCreation);
  });

  test('createVault unlocks the app', () async {
    await controller.createVault('passphrase123');
    expect(controller.phase, AppPhase.unlocked);
    expect(controller.visibleNotes, isEmpty);
  });

  test('create, save, search, and delete a note', () async {
    await controller.createVault('passphrase123');
    final note = await controller.newNote();
    await controller.saveNote(note.id, title: 'Shopping', body: 'milk, eggs');

    expect(controller.visibleNotes.length, 1);
    controller.setSearch('eggs');
    expect(controller.visibleNotes.length, 1);
    controller.setSearch('nonexistent');
    expect(controller.visibleNotes, isEmpty);
    controller.setSearch('');

    await controller.deleteNote(note.id);
    expect(controller.visibleNotes, isEmpty);
  });

  test('lock, reject wrong passphrase, accept correct one', () async {
    await controller.createVault('passphrase123');
    await controller.newNote();
    controller.lock();
    expect(controller.phase, AppPhase.locked);

    final wrong = await controller.unlock('not-the-passphrase');
    expect(wrong, isFalse);
    expect(controller.phase, AppPhase.locked);
    expect(controller.unlockError, isNotNull);

    final right = await controller.unlock('passphrase123');
    expect(right, isTrue);
    expect(controller.phase, AppPhase.unlocked);
    expect(controller.visibleNotes.length, 1);
  });

  test('encrypted backup contains no plaintext', () async {
    await controller.createVault('passphrase123');
    final note = await controller.newNote();
    await controller.saveNote(note.id, title: 'T', body: 'SECRET-BODY-XYZ');
    final file = await controller.exportEncryptedBackup();
    expect((await file.readAsString()).contains('SECRET-BODY-XYZ'), isFalse);
  });

  test('plaintext export requires explicit confirmation', () async {
    await controller.createVault('passphrase123');
    await expectLater(
      controller.exportPlaintext(confirmed: false),
      throwsA(isA<PlaintextExportNotConfirmedException>()),
    );
  });
}
