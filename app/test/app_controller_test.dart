import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/platform/audio_recorder.dart';
import 'package:notes_app/platform/biometric_unlock_store.dart';
import 'package:notes_app/state/app_controller.dart';
import 'package:notes_app/state/app_settings.dart';
import 'package:notes_core/notes_core.dart';

void main() {
  late Directory root;
  late AppController controller;

  Future<AppController> buildController({
    BiometricUnlockStore? biometricUnlockStore,
  }) async {
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
      biometricUnlockStore: biometricUnlockStore,
      // Cheap KDF so tests are fast.
      createKdfParams: CryptoService().newKdfParams(
        memoryKiB: 256,
        iterations: 1,
        parallelism: 1,
      ),
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

  test('togglePinned moves a note to the top of the visible list', () async {
    await controller.createVault('passphrase123');
    final first = await controller.newNote();
    await controller.saveNote(first.id, title: 'First', body: '');
    final second = await controller.newNote();
    await controller.saveNote(second.id, title: 'Second', body: '');

    // Newest-first by default: Second above First.
    expect(controller.visibleNotes.map((n) => n.id).toList(),
        [second.id, first.id]);

    await controller.togglePinned(first.id);
    expect(controller.visibleNotes.first.id, first.id);
    expect(controller.visibleNotes.first.pinned, isTrue);

    await controller.togglePinned(first.id);
    expect(controller.visibleNotes.map((n) => n.id).toList(),
        [second.id, first.id]);
    expect(controller.visibleNotes.every((n) => !n.pinned), isTrue);
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

  test('biometric unlock is unavailable until explicitly enabled', () async {
    final biometrics = MemoryBiometricUnlockStore();
    controller.dispose();
    controller = await buildController(biometricUnlockStore: biometrics);

    await controller.createVault('passphrase123');
    await controller.newNote();
    controller.lock();

    expect(controller.settings.biometricUnlockEnabled, isFalse);
    expect(controller.canUnlockWithBiometric, isFalse);
    expect(await controller.unlockWithBiometric(), isFalse);
    expect(controller.phase, AppPhase.locked);
  });

  test('enabled biometric unlock reopens the vault with cached DEK', () async {
    final biometrics = MemoryBiometricUnlockStore();
    controller.dispose();
    controller = await buildController(biometricUnlockStore: biometrics);

    await controller.createVault('passphrase123');
    final note = await controller.newNote();
    await controller.saveNote(note.id, title: 'Cached', body: 'secret');

    expect(await controller.enableBiometricUnlock(), isTrue);
    expect(controller.settings.biometricUnlockEnabled, isTrue);

    controller.lock();
    expect(controller.canUnlockWithBiometric, isTrue);

    expect(await controller.unlockWithBiometric(), isTrue);
    expect(controller.phase, AppPhase.unlocked);
    expect(controller.visibleNotes.single.title, 'Cached');
  });

  test('disabling biometric unlock clears the cached DEK', () async {
    final biometrics = MemoryBiometricUnlockStore();
    controller.dispose();
    controller = await buildController(biometricUnlockStore: biometrics);

    await controller.createVault('passphrase123');
    expect(await controller.enableBiometricUnlock(), isTrue);
    expect(biometrics.hasCachedDek, isTrue);

    await controller.disableBiometricUnlock();
    controller.lock();

    expect(biometrics.hasCachedDek, isFalse);
    expect(controller.settings.biometricUnlockEnabled, isFalse);
    expect(controller.canUnlockWithBiometric, isFalse);
  });

  test(
    'passphrase change keeps enabled biometric unlock bound to new header',
    () async {
      final biometrics = MemoryBiometricUnlockStore();
      controller.dispose();
      controller = await buildController(biometricUnlockStore: biometrics);

      await controller.createVault('old-passphrase');
      final note = await controller.newNote();
      await controller.saveNote(note.id, title: 'Still here', body: 'body');
      expect(await controller.enableBiometricUnlock(), isTrue);
      final firstBinding = controller.settings.biometricUnlockVaultBinding;

      await controller.changePassphrase('old-passphrase', 'new-passphrase');
      final nextBinding = controller.settings.biometricUnlockVaultBinding;
      expect(nextBinding, isNotNull);
      expect(nextBinding, isNot(firstBinding));

      controller.lock();
      expect(await controller.unlockWithBiometric(), isTrue);
      expect(controller.visibleNotes.single.title, 'Still here');
    },
  );

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

class MemoryBiometricUnlockStore implements BiometricUnlockStore {
  String? _vaultBinding;
  Uint8List? _dek;

  bool get hasCachedDek => _dek != null;

  @override
  Future<BiometricUnlockAvailability> checkAvailability() async =>
      const BiometricUnlockAvailability.available('Test biometrics');

  @override
  Future<void> clearCachedDek() async {
    _zero(_dek);
    _vaultBinding = null;
    _dek = null;
  }

  @override
  Future<Uint8List?> readCachedDek({required String vaultBinding}) async {
    final dek = _dek;
    if (_vaultBinding != vaultBinding || dek == null) return null;
    return Uint8List.fromList(dek);
  }

  @override
  Future<void> saveCachedDek({
    required String vaultBinding,
    required Uint8List dek,
  }) async {
    _zero(_dek);
    _vaultBinding = vaultBinding;
    _dek = Uint8List.fromList(dek);
  }

  void _zero(Uint8List? bytes) {
    if (bytes == null) return;
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }
}
