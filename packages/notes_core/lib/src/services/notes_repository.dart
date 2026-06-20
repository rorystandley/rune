import 'dart:math';
import 'dart:typed_data';

import '../models/note.dart';
import '../storage/vault_store.dart';
import 'vault_service.dart';

/// In-memory view of decrypted notes, backed by an encrypted [VaultStore].
///
/// After unlock, call [loadAll] to decrypt every note into memory. All reads
/// (list/get/search) are served from memory and are fast. Writes encrypt and
/// persist immediately. Decrypted notes exist only here, only while unlocked;
/// [clear] drops them on lock.
class NotesRepository {
  NotesRepository({required this.vault, required this.store});

  final VaultService vault;
  final VaultStore store;

  final Map<String, Note> _notes = {};
  final Random _random = Random.secure();
  bool _loaded = false;

  bool get isLoaded => _loaded;
  int get count => _notes.length;

  /// Decrypts all stored notes into memory. Call once after unlock.
  Future<void> loadAll() async {
    _notes.clear();
    for (final id in await store.listNoteIds()) {
      final blob = await store.readNoteBlob(id);
      final note = Note.fromEncodedBytes(await vault.openNote(blob));
      _notes[note.id] = note;
    }
    _loaded = true;
  }

  /// Drops all decrypted notes from memory (called on lock).
  void clear() {
    _notes.clear();
    _loaded = false;
  }

  /// All notes, most-recently-updated first.
  List<Note> listNotes() {
    final list = _notes.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Note? getNote(String id) => _notes[id];

  Future<Note> createNote({String title = '', String body = ''}) async {
    final now = DateTime.now().toUtc();
    final note = Note(
      id: _newId(),
      title: title,
      body: body,
      createdAt: now,
      updatedAt: now,
    );
    await _persist(note);
    _notes[note.id] = note;
    return note;
  }

  Future<Note> updateNote(String id, {String? title, String? body}) async {
    final existing = _notes[id];
    if (existing == null) {
      throw StateError('Cannot update unknown note');
    }
    final updated = existing.copyWith(
      title: title,
      body: body,
      updatedAt: DateTime.now().toUtc(),
    );
    await _persist(updated);
    _notes[id] = updated;
    return updated;
  }

  Future<void> deleteNote(String id) async {
    await store.deleteNoteBlob(id);
    _notes.remove(id);
  }

  /// Case-insensitive substring search over title + body. Empty query returns
  /// all notes. Runs entirely in memory on already-decrypted content.
  List<Note> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return listNotes();
    return listNotes()
        .where((n) =>
            n.title.toLowerCase().contains(q) ||
            n.body.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _persist(Note note) async {
    final sealed = await vault.sealNote(note.toEncodedBytes());
    await store.writeNoteBlob(note.id, sealed);
  }

  /// 128-bit random, lowercase-hex id. Opaque; leaks nothing about content.
  String _newId() {
    final bytes = Uint8List(16);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    const hex = '0123456789abcdef';
    final sb = StringBuffer();
    for (final b in bytes) {
      sb
        ..write(hex[(b >> 4) & 0xf])
        ..write(hex[b & 0xf]);
    }
    return sb.toString();
  }
}
