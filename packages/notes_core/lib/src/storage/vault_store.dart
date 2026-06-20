import 'dart:typed_data';

import '../models/vault_metadata.dart';

/// Persistence boundary for a vault. Implementations only ever see ciphertext
/// (note blobs) and the non-secret [VaultMetadata]; they never see plaintext or
/// keys. This keeps storage decoupled from crypto and trivially testable.
abstract class VaultStore {
  /// Whether a vault already exists at this location.
  Future<bool> vaultExists();

  Future<void> writeMetadata(VaultMetadata meta);
  Future<VaultMetadata> readMetadata();

  /// Ids of all stored notes (the encrypted blobs).
  Future<List<String>> listNoteIds();

  Future<Uint8List> readNoteBlob(String id);
  Future<void> writeNoteBlob(String id, Uint8List blob);
  Future<void> deleteNoteBlob(String id);

  /// Removes the entire vault (used for reset / tests).
  Future<void> deleteEverything();

  /// Non-secret description of where the vault lives (e.g. a path), for the UI.
  String get description;
}
