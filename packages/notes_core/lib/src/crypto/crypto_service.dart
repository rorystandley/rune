import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'errors.dart';
import 'kdf_params.dart';

/// Authenticated-encryption ciphers supported by the vault.
enum VaultCipher {
  /// XChaCha20-Poly1305 (192-bit nonce). Default. The large random nonce makes
  /// nonce reuse vanishingly unlikely without needing a counter.
  xchacha20poly1305('xchacha20poly1305'),

  /// AES-256-GCM (96-bit nonce). Offered as an alternative (e.g. for hardware
  /// acceleration). Random 96-bit nonces are only safe for a bounded number of
  /// messages per key; that bound is irrelevant at note volumes, but
  /// XChaCha20-Poly1305 is preferred and is the default.
  aes256gcm('aes256gcm');

  const VaultCipher(this.id);

  /// Stable identifier persisted in `vault.json`.
  final String id;

  static VaultCipher fromId(String id) => VaultCipher.values.firstWhere(
        (c) => c.id == id,
        orElse: () => throw UnsupportedVaultException('Unknown cipher: $id'),
      );

  Cipher algorithm() => switch (this) {
        VaultCipher.xchacha20poly1305 => Xchacha20.poly1305Aead(),
        VaultCipher.aes256gcm => AesGcm.with256bits(),
      };
}

/// All cryptographic operations live here. This is a thin, auditable wrapper
/// over the `cryptography` package — we do not implement any primitive
/// ourselves.
///
/// Design: passphrase --Argon2id--> KEK; a random 32-byte DEK is generated once
/// per vault and "wrapped" (encrypted) under the KEK. Notes are encrypted with
/// the DEK. Changing the passphrase only re-wraps the DEK; notes are never
/// re-encrypted.
class CryptoService {
  CryptoService({this.cipher = VaultCipher.xchacha20poly1305});

  static const int dekLength = 32;

  final VaultCipher cipher;

  /// Cryptographically secure RNG (delegates to the platform CSPRNG).
  final Random _random = Random.secure();

  Cipher get _aead => cipher.algorithm();

  /// Returns `length` bytes from the secure RNG.
  Uint8List randomBytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  /// A fresh random 32-byte data-encryption key.
  Uint8List generateDek() => randomBytes(dekLength);

  /// Fresh KDF parameters with a new random salt. Production defaults are used
  /// unless overridden (tests use cheap params for speed).
  KdfParams newKdfParams({
    int memoryKiB = KdfParams.defaultMemoryKiB,
    int iterations = KdfParams.defaultIterations,
    int parallelism = KdfParams.defaultParallelism,
  }) =>
      KdfParams(
        memoryKiB: memoryKiB,
        iterations: iterations,
        parallelism: parallelism,
        salt: randomBytes(KdfParams.saltLength),
      );

  /// Derives a 32-byte key-encryption key (KEK) from [passphrase] via Argon2id.
  ///
  /// Note: [passphrase] is a Dart [String] and therefore immutable; we cannot
  /// reliably wipe it from memory (documented in SECURITY.md).
  Future<Uint8List> deriveKek(String passphrase, KdfParams params) async {
    final kdf = Argon2id(
      parallelism: params.parallelism,
      memory: params.memoryKiB,
      iterations: params.iterations,
      hashLength: 32,
    );
    final derived = await kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: params.salt,
    );
    final bytes = await derived.extractBytes();
    return Uint8List.fromList(bytes);
  }

  /// Encrypts [plaintext] under [key] and returns `nonce || ciphertext || mac`.
  /// A fresh random nonce is generated for every call by the AEAD.
  Future<Uint8List> seal(List<int> plaintext, List<int> key) async {
    final box = await _aead.encrypt(plaintext, secretKey: SecretKey(key));
    return Uint8List.fromList(box.concatenation());
  }

  /// Decrypts data produced by [seal]. Throws [DecryptionFailedException] when
  /// authentication fails (wrong key or tampering).
  Future<Uint8List> open(List<int> sealed, List<int> key,
      {String? label}) async {
    final box = SecretBox.fromConcatenation(
      sealed,
      nonceLength: _aead.nonceLength,
      macLength: _aead.macAlgorithm.macLength,
    );
    try {
      final clear = await _aead.decrypt(box, secretKey: SecretKey(key));
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw DecryptionFailedException(label);
    }
  }

  /// Wraps (encrypts) the DEK under the KEK.
  Future<Uint8List> wrapDek(List<int> dek, List<int> kek) => seal(dek, kek);

  /// Unwraps the DEK. A MAC failure here specifically means the passphrase was
  /// wrong, so it is translated to [WrongPassphraseException].
  Future<Uint8List> unwrapDek(List<int> wrapped, List<int> kek) async {
    final box = SecretBox.fromConcatenation(
      wrapped,
      nonceLength: _aead.nonceLength,
      macLength: _aead.macAlgorithm.macLength,
    );
    try {
      final dek = await _aead.decrypt(box, secretKey: SecretKey(kek));
      return Uint8List.fromList(dek);
    } on SecretBoxAuthenticationError {
      throw const WrongPassphraseException();
    }
  }
}
