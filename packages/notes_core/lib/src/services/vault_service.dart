import 'dart:typed_data';

import '../crypto/crypto_service.dart';
import '../crypto/errors.dart';
import '../crypto/kdf_params.dart';
import '../models/vault_metadata.dart';
import '../storage/vault_store.dart';

/// Owns the unlocked-vault runtime state: the in-memory data key (DEK) and the
/// vault metadata. The DEK never leaves this object — callers encrypt/decrypt
/// note bytes via [sealNote] / [openNote].
///
/// Locking zeroes the DEK buffer (best effort; see SECURITY.md for the limits
/// of memory wiping on managed runtimes).
class VaultService {
  VaultService({required this.store, CryptoService? crypto})
      : _crypto = crypto ?? CryptoService();

  final VaultStore store;
  final CryptoService _crypto;

  Uint8List? _dek;
  VaultMetadata? _meta;

  bool get isUnlocked => _dek != null;
  Future<bool> vaultExists() => store.vaultExists();

  /// Creates a brand-new vault and leaves it unlocked. Throws
  /// [VaultAlreadyExistsException] if one already exists.
  Future<void> createVault(String passphrase, {KdfParams? kdfParams}) async {
    if (await store.vaultExists()) throw const VaultAlreadyExistsException();
    if (passphrase.isEmpty) {
      throw ArgumentError('Passphrase must not be empty');
    }
    final params = kdfParams ?? _crypto.newKdfParams();
    final kek = await _crypto.deriveKek(passphrase, params);
    final dek = _crypto.generateDek();
    final wrapped = await _crypto.wrapDek(dek, kek);
    _zero(kek);
    final meta = VaultMetadata(
      version: VaultMetadata.currentVersion,
      createdAt: DateTime.now().toUtc(),
      kdfParams: params,
      cipher: _crypto.cipher,
      wrappedKey: wrapped,
    );
    await store.writeMetadata(meta);
    _dek = dek;
    _meta = meta;
  }

  /// Unlocks an existing vault. Throws [WrongPassphraseException] on a bad
  /// passphrase (the wrapped-key MAC fails to verify).
  Future<void> unlock(String passphrase) async {
    final meta = await store.readMetadata();
    final crypto = _cryptoFor(meta.cipher);
    final kek = await crypto.deriveKek(passphrase, meta.kdfParams);
    final dek = await crypto.unwrapDek(meta.wrappedKey, kek);
    _zero(kek);
    _dek = dek;
    _meta = meta;
  }

  /// Drops and zeroes all in-memory secret state.
  void lock() {
    final dek = _dek;
    if (dek != null) _zero(dek);
    _dek = null;
    _meta = null;
  }

  /// Re-wraps the existing DEK under a key derived from [next]. Note content is
  /// never re-encrypted. Verifies [current] first (throws
  /// [WrongPassphraseException] if wrong). Leaves the vault unlocked.
  Future<void> changePassphrase(String current, String next) async {
    if (next.isEmpty) throw ArgumentError('Passphrase must not be empty');
    final meta = await store.readMetadata();
    final crypto = _cryptoFor(meta.cipher);

    final currentKek = await crypto.deriveKek(current, meta.kdfParams);
    final dek = await crypto.unwrapDek(meta.wrappedKey, currentKek);
    _zero(currentKek);

    final newParams = crypto.newKdfParams(
      memoryKiB: meta.kdfParams.memoryKiB,
      iterations: meta.kdfParams.iterations,
      parallelism: meta.kdfParams.parallelism,
    );
    final newKek = await crypto.deriveKek(next, newParams);
    final rewrapped = await crypto.wrapDek(dek, newKek);
    _zero(newKek);

    final newMeta = VaultMetadata(
      version: meta.version,
      createdAt: meta.createdAt,
      kdfParams: newParams,
      cipher: meta.cipher,
      wrappedKey: rewrapped,
    );
    await store.writeMetadata(newMeta);

    final previous = _dek;
    if (previous != null && !identical(previous, dek)) _zero(previous);
    _dek = dek;
    _meta = newMeta;
  }

  /// Encrypts note plaintext bytes with the in-memory DEK.
  Future<Uint8List> sealNote(List<int> plaintext) =>
      _cryptoForMeta().seal(plaintext, _requireDek());

  /// Decrypts a note blob with the in-memory DEK.
  Future<Uint8List> openNote(List<int> sealed) =>
      _cryptoForMeta().open(sealed, _requireDek(), label: 'note');

  Uint8List _requireDek() {
    final dek = _dek;
    if (dek == null) throw const VaultLockedException();
    return dek;
  }

  CryptoService _cryptoFor(VaultCipher cipher) =>
      cipher == _crypto.cipher ? _crypto : CryptoService(cipher: cipher);

  CryptoService _cryptoForMeta() {
    final meta = _meta;
    if (meta == null) throw const VaultLockedException();
    return _cryptoFor(meta.cipher);
  }

  void _zero(Uint8List bytes) {
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }
}
