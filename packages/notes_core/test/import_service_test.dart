import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:notes_core/notes_core.dart';
import 'package:test/test.dart';

/// Cheap KDF params so the tests are fast (never used for real vaults).
KdfParams _cheapParams() =>
    CryptoService().newKdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);

/// Spins up a fresh vault in a new temp dir, adds [notes], and returns the
/// pieces a test needs. Each entry in [notes] is (title, body).
Future<_Vault> _makeVault(
  String passphrase,
  List<(String, String)> notes,
) async {
  final dir = await Directory.systemTemp.createTemp('notes_import_test_');
  final store = FileVaultStore(dir);
  final vault = VaultService(store: store);
  await vault.createVault(passphrase, kdfParams: _cheapParams());
  final repo = NotesRepository(vault: vault, store: store);
  await repo.loadAll();
  for (final (title, body) in notes) {
    await repo.createNote(title: title, body: body);
  }
  return _Vault(dir: dir, store: store, vault: vault, repo: repo);
}

class _Vault {
  _Vault({
    required this.dir,
    required this.store,
    required this.vault,
    required this.repo,
  });
  final Directory dir;
  final FileVaultStore store;
  final VaultService vault;
  final NotesRepository repo;

  ImportService get importer => ImportService(store: store);
  ExportService get exporter => ExportService(store: store);

  Future<void> dispose() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

void main() {
  final temps = <_Vault>[];

  Future<_Vault> vaultWith(
    String passphrase,
    List<(String, String)> notes,
  ) async {
    final v = await _makeVault(passphrase, notes);
    temps.add(v);
    return v;
  }

  Future<File> exportOf(_Vault v) async {
    final out = File('${v.dir.path}/backup.notesbak');
    await v.exporter.exportEncryptedBackup(out);
    return out;
  }

  tearDown(() async {
    for (final v in temps) {
      await v.dispose();
    }
    temps.clear();
  });

  group('restoreAsNewVault', () {
    test('round-trips notes onto a brand-new device', () async {
      final source = await vaultWith('old-phone-pass', [
        ('Groceries', 'milk, eggs, bread'),
        ('Ideas', 'a private thought'),
      ]);
      final backup = await exportOf(source);

      // A pristine device: empty dir, no vault.
      final destDir = await Directory.systemTemp.createTemp('notes_dest_');
      addTearDown(() => destDir.delete(recursive: true));
      final destStore = FileVaultStore(destDir);

      final count = await ImportService(store: destStore)
          .restoreAsNewVault(await backup.readAsString());
      expect(count, 2);
      expect(await destStore.vaultExists(), isTrue);

      // Unlock with the OLD passphrase and read the notes straight back.
      final destVault = VaultService(store: destStore);
      await destVault.unlock('old-phone-pass');
      final destRepo = NotesRepository(vault: destVault, store: destStore);
      await destRepo.loadAll();

      final bodies =
          destRepo.listNotes().map((n) => '${n.title}:${n.body}').toSet();
      expect(bodies, {
        'Groceries:milk, eggs, bread',
        'Ideas:a private thought',
      });
    });

    test('refuses to clobber an existing vault without overwrite', () async {
      final source = await vaultWith('pass-a', [('A', 'aaa')]);
      final backup = await exportOf(source);

      final other = await vaultWith('pass-b', [('B', 'keep-me')]);
      await expectLater(
        other.importer.restoreAsNewVault(await backup.readAsString()),
        throwsA(isA<VaultAlreadyExistsException>()),
      );

      // The existing vault is untouched: still unlocks with its own pass and
      // still holds its own note.
      other.vault.lock();
      await other.vault.unlock('pass-b');
      await other.repo.loadAll();
      expect(other.repo.listNotes().single.body, 'keep-me');
    });

    test('overwriteExisting replaces the vault wholesale', () async {
      final source = await vaultWith('new-pass', [('Fresh', 'fresh-body')]);
      final backup = await exportOf(source);

      final other = await vaultWith('old-pass', [('Stale', 'stale-body')]);
      await other.importer.restoreAsNewVault(
        await backup.readAsString(),
        overwriteExisting: true,
      );

      // The old passphrase no longer works; the backup's does.
      await expectLater(
        VaultService(store: other.store).unlock('old-pass'),
        throwsA(isA<WrongPassphraseException>()),
      );
      final v = VaultService(store: other.store);
      await v.unlock('new-pass');
      final repo = NotesRepository(vault: v, store: other.store);
      await repo.loadAll();
      expect(repo.listNotes().single.body, 'fresh-body');
    });

    test('an interrupted restore writes no openable vault (fails closed)',
        () async {
      final source = await vaultWith('p', [
        ('a', '1'),
        ('b', '2'),
        ('c', '3'),
      ]);
      final backup = await exportOf(source);

      final destDir = await Directory.systemTemp.createTemp('notes_failclosed_');
      addTearDown(() => destDir.delete(recursive: true));
      // Fail on the second blob write, part-way through the restore.
      final failing =
          _FailOnNthBlobStore(FileVaultStore(destDir), failOnWrite: 2);

      await expectLater(
        ImportService(store: failing)
            .restoreAsNewVault(await backup.readAsString()),
        throwsA(isA<_InjectedIoError>()),
      );

      // The header is written last, so a mid-restore failure leaves nothing a
      // reader would recognise as a vault — no half-loaded, truncated note set.
      expect(await FileVaultStore(destDir).vaultExists(), isFalse);
    });
  });

  group('mergeIntoUnlockedVault', () {
    test('imports notes into an existing vault under its own key', () async {
      final source = await vaultWith('backup-pass', [
        ('Recipe', 'secret-sauce'),
        ('Todo', 'call the bank'),
      ]);
      final backup = await exportOf(source);

      final dest = await vaultWith('dest-pass', [('Mine', 'already here')]);
      final imported = await dest.importer.mergeIntoUnlockedVault(
        await backup.readAsString(),
        backupPassphrase: 'backup-pass',
        repository: dest.repo,
      );
      expect(imported, 2);
      expect(dest.repo.count, 3);

      // Re-open the destination with ITS passphrase: the imported notes are now
      // sealed under the destination key, not the backup's.
      dest.vault.lock();
      await dest.vault.unlock('dest-pass');
      await dest.repo.loadAll();
      final bodies = dest.repo.listNotes().map((n) => n.body).toSet();
      expect(bodies, {'already here', 'secret-sauce', 'call the bank'});
    });

    test('preserves timestamps and pin state', () async {
      final created = DateTime.utc(2021, 1, 2, 3, 4, 5);
      final updated = DateTime.utc(2022, 6, 7, 8, 9, 10);
      final source = await vaultWith('bp', <(String, String)>[]);
      // Craft a note with explicit timestamps + pinned by writing it directly.
      final note = Note(
        id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        title: 'Pinned',
        body: 'pin-body',
        createdAt: created,
        updatedAt: updated,
        pinned: true,
      );
      await source.store
          .writeNoteBlob(note.id, await source.vault.sealNote(note.toEncodedBytes()));
      final backup = await exportOf(source);

      final dest = await vaultWith('dp', <(String, String)>[]);
      await dest.importer.mergeIntoUnlockedVault(
        await backup.readAsString(),
        backupPassphrase: 'bp',
        repository: dest.repo,
      );
      final got = dest.repo.listNotes().single;
      expect(got.createdAt, created);
      expect(got.updatedAt, updated);
      expect(got.pinned, isTrue);
      // Fresh id, not the source's.
      expect(got.id, isNot(note.id));
    });

    test('a wrong backup passphrase imports nothing', () async {
      final source = await vaultWith('right-pass', [('X', 'xxx')]);
      final backup = await exportOf(source);

      final dest = await vaultWith('dest-pass', [('Mine', 'mmm')]);
      await expectLater(
        dest.importer.mergeIntoUnlockedVault(
          await backup.readAsString(),
          backupPassphrase: 'WRONG',
          repository: dest.repo,
        ),
        throwsA(isA<WrongPassphraseException>()),
      );
      expect(dest.repo.count, 1); // unchanged
    });

    test('merge writes only ciphertext — no plaintext hits disk', () async {
      const secret = 'TOPSECRET-merge-marker-98765';
      final source = await vaultWith('bp', [('Note', secret)]);
      final backup = await exportOf(source);

      final dest = await vaultWith('dp', <(String, String)>[]);
      await dest.importer.mergeIntoUnlockedVault(
        await backup.readAsString(),
        backupPassphrase: 'bp',
        repository: dest.repo,
      );

      // Scan every file under the destination vault dir for the plaintext.
      for (final entity in dest.dir.listSync(recursive: true)) {
        if (entity is File && entity.path != backup.path) {
          final bytes = await entity.readAsBytes();
          expect(utf8.decode(bytes, allowMalformed: true).contains(secret),
              isFalse,
              reason: 'plaintext leaked into ${entity.path}');
        }
      }
    });

    test('a tampered note blob fails authentication', () async {
      final source = await vaultWith('bp', [('N', 'body')]);
      final backup = await exportOf(source);
      final json =
          jsonDecode(await backup.readAsString()) as Map<String, dynamic>;
      final notes = json['notes'] as Map<String, dynamic>;
      final id = notes.keys.first;
      // Flip a byte in the ciphertext.
      final blob = base64.decode(notes[id] as String);
      blob[blob.length ~/ 2] ^= 0xFF;
      notes[id] = base64.encode(blob);

      final dest = await vaultWith('dp', <(String, String)>[]);
      await expectLater(
        dest.importer.mergeIntoUnlockedVault(
          jsonEncode(json),
          backupPassphrase: 'bp',
          repository: dest.repo,
        ),
        throwsA(isA<DecryptionFailedException>()),
      );
    });

    test('a tampered blob in a multi-note backup imports nothing', () async {
      final source = await vaultWith('bp', [
        ('One', '1'),
        ('Two', '2'),
        ('Three', '3'),
      ]);
      final backup = await exportOf(source);
      final json =
          jsonDecode(await backup.readAsString()) as Map<String, dynamic>;
      final notes = json['notes'] as Map<String, dynamic>;
      // Tamper the middle note, so the first is decrypted before the failure.
      final id = notes.keys.elementAt(1);
      final blob = base64.decode(notes[id] as String);
      blob[blob.length ~/ 2] ^= 0xFF;
      notes[id] = base64.encode(blob);

      final dest = await vaultWith('dp', [('Mine', 'keep')]);
      await expectLater(
        dest.importer.mergeIntoUnlockedVault(
          jsonEncode(json),
          backupPassphrase: 'bp',
          repository: dest.repo,
        ),
        throwsA(isA<DecryptionFailedException>()),
      );

      // Nothing was persisted: only the pre-existing note remains, both in
      // memory and on disk.
      expect(dest.repo.count, 1);
      dest.vault.lock();
      await dest.vault.unlock('dp');
      await dest.repo.loadAll();
      expect(dest.repo.listNotes().single.body, 'keep');
    });
  });

  group('parse validation', () {
    late ImportService importer;
    setUp(() async {
      final v = await vaultWith('p', <(String, String)>[]);
      importer = v.importer;
    });

    test('non-JSON throws FormatException', () {
      expect(() => importer.parse('not json {{{'),
          throwsA(isA<FormatException>()));
    });

    test('wrong format id throws FormatException', () {
      final bad = jsonEncode({'format': 'something-else', 'version': 1});
      expect(() => importer.parse(bad), throwsA(isA<FormatException>()));
    });

    test('a future version is rejected', () async {
      final v = await vaultWith('p', [('N', 'b')]);
      final out = File('${v.dir.path}/b.notesbak');
      await v.exporter.exportEncryptedBackup(out);
      final json = jsonDecode(await out.readAsString()) as Map<String, dynamic>;
      json['version'] = ExportService.backupVersion + 1;
      expect(() => importer.parse(jsonEncode(json)),
          throwsA(isA<FormatException>()));
    });

    test('an unsafe note id is rejected', () {
      final bad = jsonEncode({
        'format': ExportService.backupFormat,
        'version': ExportService.backupVersion,
        'vault': _dummyVaultHeader(),
        'notes': {'../escape': base64.encode([1, 2, 3])},
      });
      expect(() => importer.parse(bad), throwsA(isA<FormatException>()));
    });

    test('a non-string note value is rejected', () {
      final bad = jsonEncode({
        'format': ExportService.backupFormat,
        'version': ExportService.backupVersion,
        'vault': _dummyVaultHeader(),
        'notes': {'abcdef': 42},
      });
      expect(() => importer.parse(bad), throwsA(isA<FormatException>()));
    });

    test('a missing vault header is rejected', () {
      final bad = jsonEncode({
        'format': ExportService.backupFormat,
        'version': ExportService.backupVersion,
        'notes': <String, String>{},
      });
      expect(() => importer.parse(bad), throwsA(isA<FormatException>()));
    });

    test('an abusive Argon2id memory cost is rejected', () {
      final header = _dummyVaultHeader();
      (header['kdf'] as Map<String, dynamic>)['memoryKiB'] =
          KdfParams.maxMemoryKiB + 1;
      final bad = jsonEncode({
        'format': ExportService.backupFormat,
        'version': ExportService.backupVersion,
        'vault': header,
        'notes': <String, String>{},
      });
      expect(() => importer.parse(bad), throwsA(isA<FormatException>()));
    });

    test('an abusive Argon2id iteration count is rejected', () {
      final header = _dummyVaultHeader();
      (header['kdf'] as Map<String, dynamic>)['iterations'] =
          KdfParams.maxIterations + 1;
      final bad = jsonEncode({
        'format': ExportService.backupFormat,
        'version': ExportService.backupVersion,
        'vault': header,
        'notes': <String, String>{},
      });
      expect(() => importer.parse(bad), throwsA(isA<FormatException>()));
    });
  });
}

/// Marker exception injected by [_FailOnNthBlobStore] to simulate a write error
/// (disk full, permissions) part-way through a restore.
class _InjectedIoError implements Exception {
  const _InjectedIoError();
}

/// Wraps a real [FileVaultStore] but throws on the Nth `writeNoteBlob`, to
/// exercise a restore that is interrupted after some blobs are written.
class _FailOnNthBlobStore implements VaultStore {
  _FailOnNthBlobStore(this._inner, {required this.failOnWrite});

  final FileVaultStore _inner;
  final int failOnWrite;
  int _writes = 0;

  @override
  Future<void> writeNoteBlob(String id, Uint8List blob) async {
    _writes++;
    if (_writes == failOnWrite) throw const _InjectedIoError();
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

/// A syntactically valid vault header, for parser tests that never decrypt.
Map<String, dynamic> _dummyVaultHeader() {
  final crypto = CryptoService();
  final params = crypto.newKdfParams(
      memoryKiB: 256, iterations: 1, parallelism: 1);
  return VaultMetadata(
    version: VaultMetadata.currentVersion,
    createdAt: DateTime.utc(2024),
    kdfParams: params,
    cipher: crypto.cipher,
    wrappedKey: Uint8List.fromList(List.filled(60, 0)),
  ).toJson();
}
