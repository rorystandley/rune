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

  /// How long a soft-deleted note stays in Recently Deleted before it is purged
  /// permanently. Kept deliberately generous — there is no cloud to recover
  /// from, so the safety net should be forgiving.
  static const Duration recentlyDeletedRetention = Duration(days: 30);

  final VaultService vault;
  final VaultStore store;

  final Map<String, Note> _notes = {};
  final Random _random = Random.secure();
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Number of live (not soft-deleted) notes.
  int get count => _notes.values.where((n) => !n.isDeleted).length;

  /// Number of notes currently sitting in Recently Deleted.
  int get deletedCount => _notes.values.where((n) => n.isDeleted).length;

  /// Decrypts all stored notes into memory, then purges any whose retention
  /// window has elapsed. Call once after unlock.
  Future<void> loadAll() async {
    _notes.clear();
    for (final id in await store.listNoteIds()) {
      final blob = await store.readNoteBlob(id);
      final note = Note.fromEncodedBytes(await vault.openNote(blob));
      _notes[note.id] = note;
    }
    await _purgeExpired();
    _loaded = true;
  }

  /// Drops all decrypted notes from memory (called on lock).
  void clear() {
    _notes.clear();
    _loaded = false;
  }

  /// Live notes, pinned first, then most-recently-updated first within each
  /// group. Soft-deleted notes are excluded (see [listDeleted]). Pinning is
  /// metadata only and does not change a note's modified time.
  List<Note> listNotes() {
    final list = _notes.values.where((n) => !n.isDeleted).toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return list;
  }

  /// Soft-deleted notes, most-recently-deleted first — the Recently Deleted
  /// view. Pinning is ignored here; deletion order is what matters.
  List<Note> listDeleted() {
    final list = _notes.values.where((n) => n.isDeleted).toList()
      ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
    return list;
  }

  /// A live note by id, or null if it is unknown or soft-deleted. Callers that
  /// need to reach a soft-deleted note (restore/purge) address it by id.
  Note? getNote(String id) {
    final note = _notes[id];
    return (note == null || note.isDeleted) ? null : note;
  }

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
    final existing = getNote(id);
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

  /// Pins or unpins a note. Preserves the note's modified time — pinning is an
  /// organizing action, not an edit. No-op (returns the existing note) when the
  /// pin state is already what was requested.
  Future<Note> setPinned(String id, bool pinned) async {
    final existing = getNote(id);
    if (existing == null) {
      throw StateError('Cannot pin unknown note');
    }
    if (existing.pinned == pinned) return existing;
    final updated = existing.copyWith(pinned: pinned);
    await _persist(updated);
    _notes[id] = updated;
    return updated;
  }

  /// Soft-deletes a note: it moves to Recently Deleted and is hidden from the
  /// main list, but stays on disk (still encrypted) so it can be restored.
  /// No-op if the note is unknown or already deleted. Returns the deleted note,
  /// or null if there was nothing live to delete.
  Future<Note?> deleteNote(String id) async {
    final existing = getNote(id);
    if (existing == null) return null;
    final deleted = existing.copyWith(deletedAt: DateTime.now().toUtc());
    await _persist(deleted);
    _notes[id] = deleted;
    return deleted;
  }

  /// Restores a soft-deleted note back into the main list. No-op (returns null)
  /// if the note is unknown or already live.
  Future<Note?> restoreNote(String id) async {
    final existing = _notes[id];
    if (existing == null || !existing.isDeleted) return null;
    final restored = existing.copyWith(deletedAt: null);
    await _persist(restored);
    _notes[id] = restored;
    return restored;
  }

  /// Permanently removes a note and its on-disk blob. Used for "Delete forever"
  /// from Recently Deleted and by [_purgeExpired]; unlike [deleteNote] this is
  /// irreversible.
  Future<void> purgeNote(String id) async {
    await store.deleteNoteBlob(id);
    _notes.remove(id);
  }

  /// Permanently removes every soft-deleted note ("Empty Recently Deleted").
  Future<void> purgeAllDeleted() async {
    for (final note in listDeleted()) {
      await purgeNote(note.id);
    }
  }

  /// Purges soft-deleted notes whose retention window has elapsed. Called
  /// automatically on [loadAll]; compares against wall-clock now.
  Future<void> _purgeExpired() async {
    final cutoff = DateTime.now().toUtc().subtract(recentlyDeletedRetention);
    final expired = _notes.values
        .where((n) => n.isDeleted && n.deletedAt!.isBefore(cutoff))
        .map((n) => n.id)
        .toList();
    for (final id in expired) {
      await purgeNote(id);
    }
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
