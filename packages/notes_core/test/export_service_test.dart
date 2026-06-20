import 'dart:convert';
import 'dart:io';

import 'package:notes_core/notes_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late FileVaultStore store;
  late NotesRepository repo;
  late ExportService exporter;

  const secretBody = 'TOPSECRET-pizza-recipe-12345';
  const secretTitle = 'Dinner';

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('notes_export_test_');
    store = FileVaultStore(dir);
    final crypto = CryptoService();
    final vault = VaultService(store: store, crypto: crypto);
    await vault.createVault('pw',
        kdfParams: crypto.newKdfParams(memoryKiB: 256, iterations: 1, parallelism: 1));
    repo = NotesRepository(vault: vault, store: store);
    await repo.loadAll();
    await repo.createNote(title: secretTitle, body: secretBody);
    exporter = ExportService(store: store);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('encrypted backup contains NO plaintext', () async {
    final out = File('${dir.path}/backup.notesbak');
    await exporter.exportEncryptedBackup(out);
    final contents = await out.readAsString();
    expect(contents.contains(secretBody), isFalse);
    expect(contents.contains(secretTitle), isFalse);
    expect(contents.contains(ExportService.backupFormat), isTrue);
  });

  test('encrypted backup carries the vault header + encrypted notes', () async {
    final out = File('${dir.path}/backup.notesbak');
    await exporter.exportEncryptedBackup(out);
    final json = jsonDecode(await out.readAsString()) as Map<String, dynamic>;
    expect((json['notes'] as Map<String, dynamic>).length, 1);
    // Header travels with the backup so the same passphrase can restore it.
    expect((json['vault'] as Map<String, dynamic>)['cipher'], 'xchacha20poly1305');
  });

  test('plaintext export WITHOUT confirmation throws and writes nothing', () async {
    final outDir = Directory('${dir.path}/plain');
    expect(
      () => exporter.exportPlaintext(outDir, repo, confirmed: false),
      throwsA(isA<PlaintextExportNotConfirmedException>()),
    );
    expect(await outDir.exists(), isFalse);
  });

  test('plaintext export WITH confirmation writes readable markdown', () async {
    final outDir = Directory('${dir.path}/plain');
    await exporter.exportPlaintext(outDir, repo, confirmed: true);
    final files = outDir.listSync().whereType<File>().toList();
    expect(files.length, 1);
    final text = await files.first.readAsString();
    expect(text.contains(secretBody), isTrue);
    expect(text.contains('# $secretTitle'), isTrue);
  });
}
