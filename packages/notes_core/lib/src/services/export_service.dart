import 'dart:convert';
import 'dart:io';

import '../crypto/errors.dart';
import '../models/note.dart';
import '../storage/vault_store.dart';
import 'notes_repository.dart';

/// Two export paths, deliberately asymmetric in safety:
///
///  - [exportEncryptedBackup] — the safe default. A self-contained, fully
///    encrypted bundle. No plaintext leaves the vault.
///  - [exportPlaintext] — the dangerous escape hatch. Writes DECRYPTED notes
///    and refuses to run without explicit confirmation.
class ExportService {
  ExportService({required this.store});

  final VaultStore store;

  static const String backupFormat = 'notes-encrypted-backup';
  static const int backupVersion = 1;

  /// Writes a fully-encrypted, self-contained backup to [target].
  ///
  /// Bundles the vault header (KDF params, salt, wrapped key) and every
  /// encrypted note blob. Contains NO plaintext — it can only be opened with
  /// the same passphrase. Does not require the vault to be unlocked.
  Future<File> exportEncryptedBackup(File target) async {
    final meta = await store.readMetadata();
    final notes = <String, String>{};
    for (final id in await store.listNoteIds()) {
      notes[id] = base64.encode(await store.readNoteBlob(id));
    }
    final payload = <String, dynamic>{
      'format': backupFormat,
      'version': backupVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'vault': meta.toJson(),
      'notes': notes,
    };
    await target.parent.create(recursive: true);
    await target.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    return target;
  }

  /// DANGER: writes DECRYPTED note content to [targetDir] as Markdown files,
  /// one per note. Requires [confirmed] == true (the UI must show an explicit
  /// warning first); otherwise throws [PlaintextExportNotConfirmedException].
  ///
  /// The vault must be unlocked and notes loaded into [repository].
  Future<Directory> exportPlaintext(
    Directory targetDir,
    NotesRepository repository, {
    required bool confirmed,
  }) async {
    if (!confirmed) throw const PlaintextExportNotConfirmedException();
    await targetDir.create(recursive: true);
    final usedNames = <String>{};
    for (final note in repository.listNotes()) {
      final file = File('${targetDir.path}/${_fileName(note, usedNames)}');
      await file.writeAsString(_toMarkdown(note), flush: true);
    }
    return targetDir;
  }

  String _toMarkdown(Note note) => (StringBuffer()
        ..writeln('# ${note.displayTitle}')
        ..writeln()
        ..writeln('<!-- created: ${note.createdAt.toIso8601String()} -->')
        ..writeln('<!-- updated: ${note.updatedAt.toIso8601String()} -->')
        ..writeln()
        ..write(note.body))
      .toString();

  String _fileName(Note note, Set<String> used) {
    var base = note.displayTitle
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (base.isEmpty) base = 'note';
    if (base.length > 50) base = base.substring(0, 50);
    var name = '$base.md';
    var n = 1;
    while (used.contains(name)) {
      name = '$base-${n++}.md';
    }
    used.add(name);
    return name;
  }
}
