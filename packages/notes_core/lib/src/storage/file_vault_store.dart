import 'dart:io';
import 'dart:typed_data';

import '../crypto/errors.dart';
import '../models/vault_metadata.dart';
import 'vault_store.dart';

/// A [VaultStore] backed by a directory on disk:
///
/// - `<dir>/vault.json` — clear-text header (KDF params, wrapped key)
/// - `<dir>/notes/<id>.note` — one AEAD blob per note (nonce+ciphertext+mac)
///
/// Writes are atomic (temp file + rename) to avoid torn writes on crash.
/// Filenames are opaque random ids, never derived from note content.
class FileVaultStore implements VaultStore {
  FileVaultStore(this.directory);

  final Directory directory;

  // Note ids are generated internally (128-bit hex). We still validate the
  // shape defensively so a bad id can never escape the notes directory.
  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
  static const String _noteExt = '.note';

  File get _metaFile => File('${directory.path}/vault.json');
  Directory get _notesDir => Directory('${directory.path}/notes');

  @override
  String get description => directory.path;

  @override
  Future<bool> vaultExists() => _metaFile.exists();

  @override
  Future<void> writeMetadata(VaultMetadata meta) async {
    await directory.create(recursive: true);
    await _atomicWriteString(_metaFile, meta.encode());
  }

  @override
  Future<VaultMetadata> readMetadata() async {
    if (!await _metaFile.exists()) throw const VaultNotFoundException();
    return VaultMetadata.decode(await _metaFile.readAsString());
  }

  @override
  Future<List<String>> listNoteIds() async {
    if (!await _notesDir.exists()) return <String>[];
    final ids = <String>[];
    await for (final entity in _notesDir.list()) {
      if (entity is File && entity.path.endsWith(_noteExt)) {
        final name = entity.uri.pathSegments.last;
        ids.add(name.substring(0, name.length - _noteExt.length));
      }
    }
    return ids;
  }

  @override
  Future<Uint8List> readNoteBlob(String id) async =>
      Uint8List.fromList(await _noteFile(id).readAsBytes());

  @override
  Future<void> writeNoteBlob(String id, Uint8List blob) async {
    await _notesDir.create(recursive: true);
    await _atomicWriteBytes(_noteFile(id), blob);
  }

  @override
  Future<void> deleteNoteBlob(String id) async {
    final file = _noteFile(id);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> deleteEverything() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  File _noteFile(String id) {
    if (!_idPattern.hasMatch(id)) {
      throw ArgumentError('Invalid note id');
    }
    return File('${_notesDir.path}/$id$_noteExt');
  }

  Future<void> _atomicWriteString(File file, String contents) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(file.path);
  }

  Future<void> _atomicWriteBytes(File file, List<int> bytes) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }
}
