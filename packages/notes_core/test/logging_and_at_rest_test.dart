import 'dart:async';
import 'dart:io';

import 'package:notes_core/notes_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  const passphrase = 'pa55phrase-do-not-log';
  const secret = 'diary-entry-confidential-987';

  KdfParams cheap(CryptoService c) =>
      c.newKdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('notes_log_test_');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('core operations never print the passphrase or note content', () async {
    final captured = StringBuffer();
    await runZoned(
      () async {
        final store = FileVaultStore(dir);
        final crypto = CryptoService();
        final vault = VaultService(store: store, crypto: crypto);
        await vault.createVault(passphrase, kdfParams: cheap(crypto));
        final repo = NotesRepository(vault: vault, store: store);
        await repo.loadAll();
        final n = await repo.createNote(title: 'Secret', body: secret);
        await repo.updateNote(n.id, body: '$secret extended');
        repo.search(secret);
        vault.lock();
        await vault.unlock(passphrase);
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => captured.writeln(line),
      ),
    );
    final out = captured.toString();
    expect(out.contains(passphrase), isFalse);
    expect(out.contains(secret), isFalse);
  });

  test('encryption at rest: no plaintext in vault.json or note files', () async {
    final store = FileVaultStore(dir);
    final crypto = CryptoService();
    final vault = VaultService(store: store, crypto: crypto);
    await vault.createVault(passphrase, kdfParams: cheap(crypto));
    final repo = NotesRepository(vault: vault, store: store);
    await repo.loadAll();
    await repo.createNote(title: 'SecretTitle', body: secret);

    final vaultJson = await File('${dir.path}/vault.json').readAsString();
    expect(vaultJson.contains(passphrase), isFalse);
    expect(vaultJson.contains(secret), isFalse);

    final files =
        Directory('${dir.path}/notes').listSync().whereType<File>().toList();
    expect(files, isNotEmpty);
    for (final f in files) {
      final asText = String.fromCharCodes(await f.readAsBytes());
      expect(asText.contains(secret), isFalse);
      expect(asText.contains('SecretTitle'), isFalse);
    }
  });
}
