import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:notes_core/notes_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late FileVaultStore store;
  late CryptoService crypto;
  late VaultService vault;

  KdfParams cheap() =>
      crypto.newKdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('notes_vault_test_');
    store = FileVaultStore(dir);
    crypto = CryptoService();
    vault = VaultService(store: store, crypto: crypto);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('no vault initially; not unlocked', () async {
    expect(await vault.vaultExists(), isFalse);
    expect(vault.isUnlocked, isFalse);
  });

  test('createVault creates an unlocked vault and writes metadata', () async {
    await vault.createVault('correct horse', kdfParams: cheap());
    expect(vault.isUnlocked, isTrue);
    expect(await vault.vaultExists(), isTrue);
    expect(await File('${dir.path}/vault.json').exists(), isTrue);
  });

  test('createVault throws if a vault already exists', () async {
    await vault.createVault('pw', kdfParams: cheap());
    final v2 = VaultService(store: store, crypto: crypto);
    expect(
      () => v2.createVault('pw2', kdfParams: cheap()),
      throwsA(isA<VaultAlreadyExistsException>()),
    );
  });

  test('unlock with correct passphrase succeeds', () async {
    await vault.createVault('s3cret', kdfParams: cheap());
    vault.lock();
    expect(vault.isUnlocked, isFalse);
    await vault.unlock('s3cret');
    expect(vault.isUnlocked, isTrue);
  });

  test('unlock with WRONG passphrase throws and stays locked', () async {
    await vault.createVault('s3cret', kdfParams: cheap());
    vault.lock();
    expect(
        () => vault.unlock('wrong'), throwsA(isA<WrongPassphraseException>()));
    expect(vault.isUnlocked, isFalse);
  });

  test('platform cached DEK unlocks without storing the passphrase', () async {
    await vault.createVault('s3cret', kdfParams: cheap());
    final sealed = await vault.sealNote(utf8.encode('cached unlock note'));
    final cachedDek = vault.exportDekForPlatformUnlockCache();
    vault.lock();

    final fresh = VaultService(store: FileVaultStore(dir));
    await fresh.unlockWithPlatformCachedDek(cachedDek);

    expect(fresh.isUnlocked, isTrue);
    expect(await fresh.openNote(sealed),
        equals(Uint8List.fromList(utf8.encode('cached unlock note'))));
  });

  test('exported cached DEK is a defensive copy', () async {
    await vault.createVault('s3cret', kdfParams: cheap());
    final cachedDek = vault.exportDekForPlatformUnlockCache();
    cachedDek.fillRange(0, cachedDek.length, 0);

    final sealed = await vault.sealNote(utf8.encode('still unlocked'));

    expect(await vault.openNote(sealed),
        equals(Uint8List.fromList(utf8.encode('still unlocked'))));
  });

  test('platform cached DEK rejects malformed key length', () async {
    await vault.createVault('s3cret', kdfParams: cheap());
    vault.lock();

    expect(
      () => vault.unlockWithPlatformCachedDek([1, 2, 3]),
      throwsA(isA<UnsupportedVaultException>()),
    );
    expect(vault.isUnlocked, isFalse);
  });

  test('a fresh service instance can unlock an existing vault', () async {
    await vault.createVault('s3cret', kdfParams: cheap());
    final fresh = VaultService(store: FileVaultStore(dir));
    expect(await fresh.vaultExists(), isTrue);
    await fresh.unlock('s3cret');
    expect(fresh.isUnlocked, isTrue);
  });

  test('sealNote/openNote round-trip while unlocked', () async {
    await vault.createVault('pw', kdfParams: cheap());
    final msg = utf8.encode('note bytes');
    expect(await vault.openNote(await vault.sealNote(msg)),
        equals(Uint8List.fromList(msg)));
  });

  test('sealNote throws VaultLockedException when locked', () async {
    await vault.createVault('pw', kdfParams: cheap());
    vault.lock();
    expect(
        () => vault.sealNote([1, 2, 3]), throwsA(isA<VaultLockedException>()));
  });

  test('changePassphrase: old stops working, new works', () async {
    await vault.createVault('old-pass', kdfParams: cheap());
    await vault.changePassphrase('old-pass', 'new-pass');
    vault.lock();
    expect(() => vault.unlock('old-pass'),
        throwsA(isA<WrongPassphraseException>()));
    await vault.unlock('new-pass');
    expect(vault.isUnlocked, isTrue);
  });

  test('changePassphrase with wrong current throws', () async {
    await vault.createVault('old-pass', kdfParams: cheap());
    expect(
      () => vault.changePassphrase('nope', 'new'),
      throwsA(isA<WrongPassphraseException>()),
    );
  });

  test('notes remain decryptable after a passphrase change', () async {
    await vault.createVault('old', kdfParams: cheap());
    final sealed = await vault.sealNote(utf8.encode('persistent'));
    await vault.changePassphrase('old', 'new');
    expect(await vault.openNote(sealed),
        equals(Uint8List.fromList(utf8.encode('persistent'))));
  });

  test('production-default KDF params work end-to-end', () async {
    await vault.createVault('production-pass'); // 64 MiB / 3 passes
    vault.lock();
    await vault.unlock('production-pass');
    expect(vault.isUnlocked, isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
