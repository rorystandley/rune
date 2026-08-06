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
    SettingsStore? settingsStore,
    VaultStore? vaultStore,
    int autoLockMinutes = 0,
  }) async {
    final settings =
        settingsStore ?? SettingsStore(File('${root.path}/settings.json'));
    // Auto-lock defaults off in tests so no Timer is left pending.
    await settings.save(AppSettings(autoLockMinutes: autoLockMinutes));
    final c = AppController(
      vaultDir: Directory('${root.path}/vault'),
      audioTempDir: Directory('${root.path}/audio'),
      exportsDir: Directory('${root.path}/exports'),
      settingsStore: settings,
      transcription: const StubTranscriptionService(),
      recorder: const UnavailableAudioRecorder(),
      biometricUnlockStore: biometricUnlockStore,
      initialStore: vaultStore,
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

  test('delete is a soft-delete that Undo (restore) reverses', () async {
    await controller.createVault('passphrase123');
    final note = await controller.newNote();
    await controller.saveNote(note.id, title: 'Keep me', body: 'body');

    await controller.deleteNote(note.id);
    expect(controller.visibleNotes, isEmpty);
    expect(controller.deletedNotes.single.id, note.id);
    // Deleting the selected note clears the selection.
    expect(controller.selectedNote, isNull);

    await controller.restoreNote(note.id);
    expect(controller.deletedNotes, isEmpty);
    expect(controller.visibleNotes.single.title, 'Keep me');
  });

  test('purge permanently removes one note; empty clears the rest', () async {
    await controller.createVault('passphrase123');
    final a = await controller.newNote();
    await controller.saveNote(a.id, title: 'A', body: '');
    final b = await controller.newNote();
    await controller.saveNote(b.id, title: 'B', body: '');

    await controller.deleteNote(a.id);
    await controller.deleteNote(b.id);
    expect(controller.deletedNotes.length, 2);

    await controller.purgeNote(a.id);
    expect(controller.deletedNotes.single.id, b.id);

    await controller.emptyRecentlyDeleted();
    expect(controller.deletedNotes, isEmpty);
    expect(controller.visibleNotes, isEmpty);
  });

  test('soft-deleted notes stay out of plaintext export', () async {
    await controller.createVault('passphrase123');
    final gone = await controller.newNote();
    await controller.saveNote(gone.id, title: 'GONE', body: 'trashed');
    await controller.deleteNote(gone.id);

    final dir = await controller.exportPlaintext(confirmed: true);
    final names = dir
        .listSync()
        .whereType<File>()
        .map((f) => f.readAsStringSync())
        .join('\n');
    expect(names.contains('GONE'), isFalse);
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

  // Writes a real .notesbak from a throwaway source vault, for the import and
  // restore tests below.
  Future<File> makeBackup({
    required String passphrase,
    required List<(String, String)> notes,
  }) async {
    final dir = await Directory.systemTemp.createTemp('notes_src_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final store = FileVaultStore(dir);
    final vault = VaultService(store: store);
    await vault.createVault(
      passphrase,
      kdfParams: CryptoService().newKdfParams(
        memoryKiB: 256,
        iterations: 1,
        parallelism: 1,
      ),
    );
    final repo = NotesRepository(vault: vault, store: store);
    await repo.loadAll();
    for (final (title, body) in notes) {
      await repo.createNote(title: title, body: body);
    }
    final out = File('${dir.path}/backup.notesbak');
    await ExportService(store: store).exportEncryptedBackup(out);
    return out;
  }

  test('restoreFromBackup adopts the backup and locks for its passphrase',
      () async {
    final backup =
        await makeBackup(passphrase: 'old-phone', notes: [('Groceries', 'milk')]);

    final count = await controller.restoreFromBackup(backup);
    expect(count, 1);
    // Fresh-device path: the app is now locked on the restored vault.
    expect(controller.phase, AppPhase.locked);

    expect(await controller.unlock('old-phone'), isTrue);
    expect(controller.visibleNotes.single.body, 'milk');
  });

  test('restoreFromBackup refuses to overwrite an existing vault', () async {
    await controller.createVault('mine');
    final backup = await makeBackup(passphrase: 'other', notes: [('X', 'y')]);
    await expectLater(
      controller.restoreFromBackup(backup),
      throwsA(isA<VaultAlreadyExistsException>()),
    );
    // Refused before any delete or write: the session and vault are intact.
    expect(controller.phase, AppPhase.unlocked);
    expect(await controller.vault.vaultExists(), isTrue);
  });

  test('a restore that fails mid-write ends fail-closed in needsCreation',
      () async {
    final biometrics = MemoryBiometricUnlockStore();
    controller.dispose();
    final failing =
        _ArmableFailingStore(FileVaultStore(Directory('${root.path}/vault')));
    controller = await buildController(
      biometricUnlockStore: biometrics,
      vaultStore: failing,
    );

    await controller.createVault('mine');
    final n = await controller.newNote();
    await controller.saveNote(n.id, title: 'Mine', body: 'keep');
    expect(await controller.enableBiometricUnlock(), isTrue);
    expect(biometrics.hasCachedDek, isTrue);

    final backup = await makeBackup(
      passphrase: 'fresh',
      notes: [('A', '1'), ('B', '2'), ('C', '3')],
    );

    // Writes fail from here: the replace deletes the old vault, then the first
    // blob write throws before the header is written.
    failing.failWrites = true;
    await expectLater(
      controller.restoreFromBackup(backup, replaceExisting: true),
      throwsA(isA<_InjectedWriteError>()),
    );

    // Fail-closed: no header was written, so there is no vault; the session is
    // dropped and the cached biometric key is cleared.
    expect(controller.phase, AppPhase.needsCreation);
    expect(controller.visibleNotes, isEmpty);
    expect(biometrics.hasCachedDek, isFalse);
    expect(controller.canUnlockWithBiometric, isFalse);
  });

  test('import completes with auto-lock enabled and leaves the vault unlocked',
      () async {
    controller.dispose();
    controller = await buildController(autoLockMinutes: 1);
    await controller.createVault('dest-pass');
    final backup = await makeBackup(passphrase: 'src', notes: [('A', '1')]);

    final count = await controller.importFromBackup(backup, 'src');
    expect(count, 1);
    // Exercises the timer suspend/restart path around a real import and checks
    // it ends unlocked with the note present. (The mid-import race itself isn't
    // deterministically reproducible in a unit test — the interval floor is one
    // minute and the cheap-KDF import finishes in milliseconds — so this does
    // not by itself prove the timer was cancelled while the import ran.)
    expect(controller.phase, AppPhase.unlocked);
    expect(controller.visibleNotes.length, 1);
  });

  test('a restore whose cleanup also fails still clears busy, needsCreation',
      () async {
    final settings = _ThrowingSettingsStore(File('${root.path}/settings.json'));
    final failing =
        _ArmableFailingStore(FileVaultStore(Directory('${root.path}/vault')));
    controller.dispose();
    controller = await buildController(
      settingsStore: settings,
      vaultStore: failing,
    );

    await controller.createVault('mine');
    final n = await controller.newNote();
    await controller.saveNote(n.id, title: 'Mine', body: 'keep');

    final backup = await makeBackup(passphrase: 'fresh', notes: [('A', '1')]);

    // Correlated failure (like a full disk): the restore write fails, and so
    // does the settings write in the cleanup path.
    failing.failWrites = true;
    settings.failSaves = true;
    await expectLater(
      controller.restoreFromBackup(backup, replaceExisting: true),
      throwsA(isA<_InjectedWriteError>()),
    );

    // The cleanup exception must not mask the restore error, strand busy, or
    // leave a stale phase: busy is cleared and we fail closed to needsCreation.
    expect(controller.busy, isFalse);
    expect(controller.phase, AppPhase.needsCreation);
  });

  test('restoreFromBackup replaceExisting swaps in the backup vault', () async {
    await controller.createVault('mine');
    final stale = await controller.newNote();
    await controller.saveNote(stale.id, title: 'Mine', body: 'stale');

    final backup = await makeBackup(
      passphrase: 'fresh-pass',
      notes: [('Fresh', 'fresh-body')],
    );
    final count =
        await controller.restoreFromBackup(backup, replaceExisting: true);
    expect(count, 1);
    expect(controller.phase, AppPhase.locked);

    // The old passphrase is gone; the backup's opens the restored notes.
    expect(await controller.unlock('mine'), isFalse);
    expect(await controller.unlock('fresh-pass'), isTrue);
    expect(controller.visibleNotes.single.body, 'fresh-body');
  });

  test('importFromBackup merges a backup into the current vault', () async {
    await controller.createVault('dest-pass');
    final mine = await controller.newNote();
    await controller.saveNote(mine.id, title: 'Mine', body: 'keep');

    final backup = await makeBackup(
      passphrase: 'src-pass',
      notes: [('Imported', 'from-backup'), ('Two', '2')],
    );
    final count = await controller.importFromBackup(backup, 'src-pass');
    expect(count, 2);
    expect(
      controller.visibleNotes.map((n) => n.body).toSet(),
      {'keep', 'from-backup', '2'},
    );
  });

  test('importFromBackup rejects a wrong backup passphrase', () async {
    await controller.createVault('dest-pass');
    final backup = await makeBackup(passphrase: 'src-pass', notes: [('X', 'y')]);
    await expectLater(
      controller.importFromBackup(backup, 'WRONG'),
      throwsA(isA<WrongPassphraseException>()),
    );
    expect(controller.visibleNotes, isEmpty);
  });

  test('restoreFromBackup clears any cached biometric unlock', () async {
    final biometrics = MemoryBiometricUnlockStore();
    controller.dispose();
    controller = await buildController(biometricUnlockStore: biometrics);

    await controller.createVault('mine');
    expect(await controller.enableBiometricUnlock(), isTrue);
    expect(biometrics.hasCachedDek, isTrue);

    // Replacing the vault invalidates the old DEK; the cache must be cleared so
    // a stale key can't unlock the freshly restored vault.
    final backup = await makeBackup(passphrase: 'fresh', notes: [('N', 'b')]);
    await controller.restoreFromBackup(backup, replaceExisting: true);

    expect(biometrics.hasCachedDek, isFalse);
    expect(controller.settings.biometricUnlockEnabled, isFalse);
    expect(controller.canUnlockWithBiometric, isFalse);
    expect(controller.phase, AppPhase.locked);
  });

  test('updateSettings rolls back and rethrows when the save fails', () async {
    final store = _ThrowingSettingsStore(File('${root.path}/settings.json'));
    controller.dispose();
    controller = await buildController(settingsStore: store);
    await controller.createVault('passphrase123');

    final before = controller.settings.autoLockMinutes;
    store.failSaves = true;

    // The write fails, so the change must not stick and the error must surface.
    await expectLater(
      controller.updateSettings(
        controller.settings.copyWith(autoLockMinutes: 30),
      ),
      throwsA(isA<Exception>()),
    );
    expect(controller.settings.autoLockMinutes, before); // rolled back
  });
}

/// Marker exception injected by [_ArmableFailingStore].
class _InjectedWriteError implements Exception {
  const _InjectedWriteError();
}

/// Wraps a real [VaultStore] but, once [failWrites] is armed, throws on every
/// `writeNoteBlob`. Lets a controller test drive a restore that fails partway
/// through writing, exercising the fail-closed reset path.
class _ArmableFailingStore implements VaultStore {
  _ArmableFailingStore(this._inner);

  final VaultStore _inner;
  bool failWrites = false;

  @override
  Future<void> writeNoteBlob(String id, Uint8List blob) async {
    if (failWrites) throw const _InjectedWriteError();
    return _inner.writeNoteBlob(id, blob);
  }

  @override
  Future<bool> vaultExists() => _inner.vaultExists();
  @override
  Future<void> writeMetadata(VaultMetadata meta) => _inner.writeMetadata(meta);
  @override
  Future<VaultMetadata> readMetadata() => _inner.readMetadata();
  @override
  Future<List<String>> listNoteIds() => _inner.listNoteIds();
  @override
  Future<Uint8List> readNoteBlob(String id) => _inner.readNoteBlob(id);
  @override
  Future<void> deleteNoteBlob(String id) => _inner.deleteNoteBlob(id);
  @override
  Future<void> deleteEverything() => _inner.deleteEverything();
  @override
  String get description => _inner.description;
}

/// A [SettingsStore] whose [save] can be made to fail on demand, to exercise
/// the rollback path in [AppController.updateSettings].
class _ThrowingSettingsStore extends SettingsStore {
  _ThrowingSettingsStore(super.file);

  bool failSaves = false;

  @override
  Future<void> save(AppSettings settings) async {
    if (failSaves) throw Exception('simulated settings write failure');
    return super.save(settings);
  }
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
