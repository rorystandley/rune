import 'dart:convert';
import 'dart:typed_data';

import 'package:notes_core/notes_core.dart';
import 'package:test/test.dart';

void main() {
  group('CryptoService', () {
    final crypto = CryptoService();

    KdfParams cheap() =>
        crypto.newKdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);

    test('defaults to XChaCha20-Poly1305', () {
      expect(crypto.cipher, VaultCipher.xchacha20poly1305);
    });

    test('randomBytes has requested length and varies', () {
      final a = crypto.randomBytes(32);
      final b = crypto.randomBytes(32);
      expect(a.length, 32);
      expect(a, isNot(equals(b)));
      expect(a.any((x) => x != 0), isTrue);
    });

    test('Argon2id is deterministic for same passphrase + salt', () async {
      final params = cheap();
      final k1 = await crypto.deriveKek('hunter2', params);
      final k2 = await crypto.deriveKek('hunter2', params);
      expect(k1, equals(k2));
      expect(k1.length, 32);
    });

    test('different passphrase derives a different key', () async {
      final params = cheap();
      expect(
        await crypto.deriveKek('hunter2', params),
        isNot(equals(await crypto.deriveKek('hunter3', params))),
      );
    });

    test('different salt derives a different key', () async {
      expect(
        await crypto.deriveKek('hunter2', cheap()),
        isNot(equals(await crypto.deriveKek('hunter2', cheap()))),
      );
    });

    test('seal/open round-trips', () async {
      final key = crypto.generateDek();
      final msg = utf8.encode('the quick brown fox');
      final opened = await crypto.open(await crypto.seal(msg, key), key);
      expect(opened, equals(Uint8List.fromList(msg)));
    });

    test('seal uses a fresh nonce each call (ciphertexts differ)', () async {
      final key = crypto.generateDek();
      final msg = utf8.encode('same message');
      expect(await crypto.seal(msg, key), isNot(equals(await crypto.seal(msg, key))));
    });

    test('open with the wrong key throws DecryptionFailedException', () async {
      final key = crypto.generateDek();
      final sealed = await crypto.seal(utf8.encode('secret'), key);
      expect(
        () => crypto.open(sealed, crypto.generateDek()),
        throwsA(isA<DecryptionFailedException>()),
      );
    });

    test('tampered ciphertext fails authentication', () async {
      final key = crypto.generateDek();
      final sealed = await crypto.seal(utf8.encode('secret'), key);
      sealed[sealed.length - 1] ^= 0xff; // flip a MAC byte
      expect(() => crypto.open(sealed, key), throwsA(isA<DecryptionFailedException>()));
    });

    test('wrap/unwrap DEK round-trips', () async {
      final dek = crypto.generateDek();
      final kek = crypto.randomBytes(32);
      expect(await crypto.unwrapDek(await crypto.wrapDek(dek, kek), kek), equals(dek));
    });

    test('unwrap DEK with wrong KEK throws WrongPassphraseException', () async {
      final dek = crypto.generateDek();
      final wrapped = await crypto.wrapDek(dek, crypto.randomBytes(32));
      expect(
        () => crypto.unwrapDek(wrapped, crypto.randomBytes(32)),
        throwsA(isA<WrongPassphraseException>()),
      );
    });

    test('AES-256-GCM cipher also round-trips', () async {
      final aes = CryptoService(cipher: VaultCipher.aes256gcm);
      final key = aes.generateDek();
      final msg = utf8.encode('hello aes');
      expect(await aes.open(await aes.seal(msg, key), key),
          equals(Uint8List.fromList(msg)));
    });
  });
}
