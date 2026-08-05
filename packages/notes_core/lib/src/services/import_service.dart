import 'dart:convert';
import 'dart:typed_data';

import '../crypto/crypto_service.dart';
import '../crypto/errors.dart';
import '../models/note.dart';
import '../models/vault_metadata.dart';
import '../storage/vault_store.dart';
import '../util/secure_bytes.dart';
import 'export_service.dart';
import 'notes_repository.dart';

/// A parsed, validated encrypted backup: the vault header plus every note as
/// its raw ciphertext blob. Contains no plaintext — the blobs stay sealed until
/// something with the right key decrypts them.
class BackupBundle {
  const BackupBundle({required this.vault, required this.notes});

  /// The backup's own vault header (KDF params, salt, cipher, wrapped DEK).
  final VaultMetadata vault;

  /// Note id → sealed blob (`nonce || ciphertext || mac`), exactly as stored.
  final Map<String, Uint8List> notes;
}

/// The inverse of [ExportService]: reads a `.notesbak` bundle back in.
///
/// Two paths, matching the two real situations:
///
///  - [restoreAsNewVault] — a fresh device with no vault. Adopts the backup
///    wholesale by copying its (already encrypted) header and note blobs to
///    storage. Nothing is decrypted; only ciphertext is written, and the user
///    unlocks afterwards with the backup's passphrase.
///  - [mergeIntoUnlockedVault] — a vault that already has notes. Decrypts each
///    backup note with the backup's passphrase (in memory only), then re-seals
///    it under the *current* vault's key with a fresh id. No note is ever
///    overwritten, and no plaintext is written to disk.
class ImportService {
  ImportService({required this.store});

  final VaultStore store;

  /// The same conservative shape [FileVaultStore] enforces for on-disk note
  /// filenames. Validated here too so a crafted backup can never smuggle an id
  /// that escapes the notes directory, and so a bad id fails fast — before any
  /// partial write — with a clean [FormatException].
  static final RegExp _safeId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  /// Parses and validates a backup produced by [ExportService]. Throws a
  /// [FormatException] for anything that is not a well-formed backup of a
  /// supported version, and [UnsupportedVaultException] for an unknown cipher.
  BackupBundle parse(String jsonString) {
    final Object? decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup is not a JSON object');
    }

    final format = decoded['format'];
    if (format != ExportService.backupFormat) {
      throw FormatException('Not a Rune backup (format=$format)');
    }

    final version = decoded['version'];
    if (version is! int) {
      throw const FormatException('Backup is missing a numeric version');
    }
    if (version > ExportService.backupVersion) {
      throw FormatException(
          'Backup version $version is newer than this app supports '
          '(${ExportService.backupVersion})');
    }

    final vaultJson = decoded['vault'];
    if (vaultJson is! Map<String, dynamic>) {
      throw const FormatException('Backup is missing its vault header');
    }
    final meta = VaultMetadata.fromJson(vaultJson);
    // The header is untrusted: reject abusive Argon2id costs before they can
    // reach the KDF (a huge memoryKiB would otherwise try to allocate gigabytes
    // when the backup is unlocked or merged).
    meta.kdfParams.validateCost();

    final notesJson = decoded['notes'];
    if (notesJson is! Map<String, dynamic>) {
      throw const FormatException('Backup is missing its notes');
    }

    final notes = <String, Uint8List>{};
    notesJson.forEach((id, value) {
      if (!_safeId.hasMatch(id)) {
        throw FormatException('Backup contains an invalid note id: $id');
      }
      if (value is! String) {
        throw FormatException('Note $id is not a base64 string');
      }
      try {
        notes[id] = Uint8List.fromList(base64.decode(value));
      } on FormatException {
        throw FormatException('Note $id is not valid base64');
      }
    });

    return BackupBundle(vault: meta, notes: notes);
  }

  /// Restores a backup onto storage as a brand-new vault, copying the encrypted
  /// header and note blobs verbatim. Nothing is decrypted here, so the backup's
  /// passphrase is not needed until the subsequent unlock.
  ///
  /// Refuses to clobber an existing vault unless [overwriteExisting] is set —
  /// replacing a vault destroys whatever is currently stored, so callers must
  /// opt in explicitly (the UI confirms first). Returns the number of notes
  /// written.
  ///
  /// The backup is fully parsed and validated *before* anything is deleted, so
  /// a malformed file never touches existing data. The note blobs are then
  /// written *before* the vault header (the file whose presence marks a vault
  /// as existing). That ordering makes an interrupted restore fail closed: a
  /// crash or write error mid-restore leaves no readable vault at all, rather
  /// than a vault whose header loads but whose notes are truncated. (Replacing
  /// still isn't transactional — the previous vault is gone once deletion
  /// succeeds; staged-swap restore is noted as future hardening in SECURITY.md.)
  Future<int> restoreAsNewVault(
    String jsonString, {
    bool overwriteExisting = false,
  }) async {
    final bundle = parse(jsonString);
    if (await store.vaultExists() && !overwriteExisting) {
      throw const VaultAlreadyExistsException();
    }
    if (overwriteExisting) {
      await store.deleteEverything();
    }
    for (final entry in bundle.notes.entries) {
      await store.writeNoteBlob(entry.key, entry.value);
    }
    // Header last: only now does the vault "exist", and by then every blob is
    // already on disk.
    await store.writeMetadata(bundle.vault);
    return bundle.notes.length;
  }

  /// Merges a backup's notes into the already-unlocked vault behind
  /// [repository]. Requires the passphrase the backup was made with (which may
  /// differ from the current vault's).
  ///
  /// Each note is decrypted with the backup's key in memory, given a fresh id,
  /// and re-sealed under the current vault's key — so existing notes are never
  /// touched and duplicates simply coexist. Throws [WrongPassphraseException]
  /// if [backupPassphrase] is wrong, and [DecryptionFailedException] if any note
  /// blob fails authentication. In both failure cases **nothing is imported**:
  /// every blob is decrypted first, and notes are persisted only once all of
  /// them succeed, so a tampered blob part-way through can't leave a partial
  /// import behind. Returns the number of notes imported.
  Future<int> mergeIntoUnlockedVault(
    String jsonString, {
    required String backupPassphrase,
    required NotesRepository repository,
  }) async {
    final bundle = parse(jsonString);
    final crypto = CryptoService(cipher: bundle.vault.cipher);
    final kek = await crypto.deriveKek(backupPassphrase, bundle.vault.kdfParams);
    Uint8List? backupDek;
    try {
      // A wrong passphrase fails here, before anything is imported.
      backupDek = await crypto.unwrapDek(bundle.vault.wrappedKey, kek);
      zeroBytes(kek);
      // Decrypt everything up front: a blob that fails authentication must
      // abort the whole import, not leave a partial one behind. The ciphertext
      // is already fully in memory, so this adds no meaningful cost.
      final decoded = <Note>[];
      for (final blob in bundle.notes.values) {
        final plaintext =
            await crypto.open(blob, backupDek, label: 'imported note');
        decoded.add(Note.fromEncodedBytes(plaintext));
      }
      for (final note in decoded) {
        await repository.addImportedNote(note);
      }
      return decoded.length;
    } finally {
      zeroBytes(kek);
      if (backupDek != null) zeroBytes(backupDek);
    }
  }
}
