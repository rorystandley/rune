import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:notes_core/notes_core.dart';
import 'package:test/test.dart';

/// A body string used to detect decrypted notes left in memory or on disk.
const _secret = 'visible-body-4e9c1a';

void main() {
  group('writes that finish after lock', () {
    late Directory dir;
    late _PausingVaultStore store;
    late VaultService vault;
    late NotesRepository repo;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('notes_lock_write_');
      final crypto = CryptoService();
      store = _PausingVaultStore(FileVaultStore(dir));
      vault = VaultService(store: store, crypto: crypto);
      await vault.createVault(
        'pw',
        kdfParams: crypto.newKdfParams(
          memoryKiB: 256,
          iterations: 1,
          parallelism: 1,
        ),
      );
      repo = NotesRepository(vault: vault, store: store);
      await repo.loadAll();
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('updateNote still stores the note when the session stays open',
        () async {
      final created = await repo.createNote(title: 'before', body: 'old');
      store.pauseNoteWrites();

      final pending = repo.updateNote(created.id, body: _secret);
      await store.entered;
      store.release();
      final updated = await pending;

      expect(updated.body, _secret);
      expect(repo.getNote(created.id)!.body, _secret);
      expect(vault.isUnlocked, isTrue);
      await _expectCiphertextOnly(dir, created.id);
    });

    test('updateNote finishing after lock exposes no notes and stays locked',
        () async {
      final created = await repo.createNote(title: 'before', body: 'old');
      store.pauseNoteWrites();

      final pending = repo.updateNote(created.id, body: _secret);
      await store.entered;
      _lock(repo, vault);
      store.release();
      await pending;

      _expectSealed(repo, vault);
      await _expectCiphertextOnly(dir, created.id);
      await _reopen(vault, repo);
      expect(repo.getNote(created.id)!.body, _secret);
    });

    test('setPinned finishing after lock exposes no notes and stays locked',
        () async {
      final created = await repo.createNote(title: 'pin me', body: _secret);
      store.pauseNoteWrites();

      final pending = repo.setPinned(created.id, true);
      await store.entered;
      _lock(repo, vault);
      store.release();
      await pending;

      _expectSealed(repo, vault);
      await _expectCiphertextOnly(dir, created.id);
      await _reopen(vault, repo);
      expect(repo.getNote(created.id)!.pinned, isTrue);
      expect(repo.getNote(created.id)!.body, _secret);
    });

    test('deleteNote finishing after lock exposes no notes and stays locked',
        () async {
      final created = await repo.createNote(title: 'trash', body: _secret);
      store.pauseNoteWrites();

      final pending = repo.deleteNote(created.id);
      await store.entered;
      _lock(repo, vault);
      store.release();
      await pending;

      _expectSealed(repo, vault);
      await _expectCiphertextOnly(dir, created.id);
      await _reopen(vault, repo);
      expect(repo.getNote(created.id), isNull);
      expect(repo.listDeleted().single.body, _secret);
    });

    test('restoreNote finishing after lock exposes no notes and stays locked',
        () async {
      final created = await repo.createNote(title: 'restore', body: _secret);
      await repo.deleteNote(created.id);
      store.pauseNoteWrites();

      final pending = repo.restoreNote(created.id);
      await store.entered;
      _lock(repo, vault);
      store.release();
      await pending;

      _expectSealed(repo, vault);
      await _expectCiphertextOnly(dir, created.id);
      await _reopen(vault, repo);
      expect(repo.getNote(created.id)!.body, _secret);
      expect(repo.listDeleted(), isEmpty);
    });

    test('createNote finishing after lock exposes no notes and stays locked',
        () async {
      store.pauseNoteWrites();

      final pending = repo.createNote(title: 'fresh', body: _secret);
      await store.entered;
      _lock(repo, vault);
      store.release();
      final created = await pending;

      _expectSealed(repo, vault);
      await _expectCiphertextOnly(dir, created.id);
      await _reopen(vault, repo);
      expect(repo.getNote(created.id)!.body, _secret);
    });

    test(
        'addImportedNote finishing after lock exposes no notes and stays locked',
        () async {
      store.pauseNoteWrites();

      final pending = repo.addImportedNote(Note(
        id: 'source-id',
        title: 'imported',
        body: _secret,
        createdAt: DateTime.utc(2024),
        updatedAt: DateTime.utc(2024, 2),
      ));
      await store.entered;
      _lock(repo, vault);
      store.release();
      final imported = await pending;

      _expectSealed(repo, vault);
      await _expectCiphertextOnly(dir, imported.id);
      await _reopen(vault, repo);
      expect(repo.getNote(imported.id)!.body, _secret);
    });

    test(
        'changePassphrase finishing after lock does not republish the data key',
        () async {
      store.pauseMetadataWrites();

      final pending = vault.changePassphrase('pw', 'new-passphrase');
      await store.entered;
      _lock(repo, vault);
      store.release();
      await pending;

      _expectSealed(repo, vault);

      await vault.unlock('new-passphrase');
      expect(vault.isUnlocked, isTrue);
      vault.lock();
      expect(
        () => vault.unlock('pw'),
        throwsA(isA<WrongPassphraseException>()),
      );
      expect(vault.isUnlocked, isFalse);
    });
  });
}

/// Matches the app lock sequence: drop decrypted notes, then the data key.
void _lock(NotesRepository repo, VaultService vault) {
  repo.clear();
  vault.lock();
}

Future<void> _reopen(VaultService vault, NotesRepository repo) async {
  await vault.unlock('pw');
  await repo.loadAll();
}

void _expectSealed(NotesRepository repo, VaultService vault) {
  expect(vault.isUnlocked, isFalse);
  expect(() => vault.sealNote(const [1, 2, 3]),
      throwsA(isA<VaultLockedException>()));
  expect(
    () => vault.exportDekForPlatformUnlockCache(),
    throwsA(isA<VaultLockedException>()),
  );
  expect(repo.isLoaded, isFalse);
  expect(repo.count, 0);
  expect(repo.deletedCount, 0);
  expect(repo.listNotes(), isEmpty);
  expect(repo.listDeleted(), isEmpty);
  expect(repo.search(_secret), isEmpty);
  for (final note in [...repo.listNotes(), ...repo.listDeleted()]) {
    expect(note.title.contains(_secret), isFalse);
    expect(note.body.contains(_secret), isFalse);
  }
}

Future<void> _expectCiphertextOnly(Directory dir, String id) async {
  final file = File('${dir.path}/notes/$id.note');
  expect(await file.exists(), isTrue);
  final bytes = await file.readAsBytes();
  expect(String.fromCharCodes(bytes).contains(_secret), isFalse);
}

/// Holds one store write open so a test can lock while it is in flight.
class _PausingVaultStore implements VaultStore {
  _PausingVaultStore(this._inner);

  final VaultStore _inner;
  var _pauseNotes = false;
  var _pauseMetadata = false;
  final Completer<void> _entered = Completer<void>();
  final Completer<void> _release = Completer<void>();

  void pauseNoteWrites() => _pauseNotes = true;

  void pauseMetadataWrites() => _pauseMetadata = true;

  Future<void> get entered =>
      _entered.future.timeout(const Duration(seconds: 5));

  void release() {
    if (!_release.isCompleted) _release.complete();
  }

  Future<void> _maybePause({required bool enabled}) async {
    if (!enabled) return;
    if (!_entered.isCompleted) _entered.complete();
    await _release.future;
  }

  @override
  String get description => _inner.description;

  @override
  Future<bool> vaultExists() => _inner.vaultExists();

  @override
  Future<void> writeMetadata(VaultMetadata meta) async {
    await _maybePause(enabled: _pauseMetadata);
    await _inner.writeMetadata(meta);
  }

  @override
  Future<VaultMetadata> readMetadata() => _inner.readMetadata();

  @override
  Future<List<String>> listNoteIds() => _inner.listNoteIds();

  @override
  Future<Uint8List> readNoteBlob(String id) => _inner.readNoteBlob(id);

  @override
  Future<void> writeNoteBlob(String id, Uint8List blob) async {
    await _maybePause(enabled: _pauseNotes);
    await _inner.writeNoteBlob(id, blob);
  }

  @override
  Future<void> deleteNoteBlob(String id) => _inner.deleteNoteBlob(id);

  @override
  Future<void> deleteEverything() => _inner.deleteEverything();
}
