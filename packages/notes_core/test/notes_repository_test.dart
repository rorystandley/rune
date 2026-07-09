import 'dart:io';

import 'package:notes_core/notes_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late VaultService vault;
  late NotesRepository repo;
  late FileVaultStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('notes_repo_test_');
    final crypto = CryptoService();
    store = FileVaultStore(dir);
    vault = VaultService(store: store, crypto: crypto);
    await vault.createVault('pw',
        kdfParams: crypto.newKdfParams(memoryKiB: 256, iterations: 1, parallelism: 1));
    repo = NotesRepository(vault: vault, store: store);
    await repo.loadAll();
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('starts empty', () {
    expect(repo.listNotes(), isEmpty);
    expect(repo.count, 0);
  });

  test('create then get', () async {
    final n = await repo.createNote(title: 'Title', body: 'Body');
    expect(repo.count, 1);
    expect(repo.getNote(n.id)!.title, 'Title');
    expect(repo.getNote(n.id)!.body, 'Body');
  });

  test('update changes content', () async {
    final n = await repo.createNote(title: 'A', body: 'one');
    final before = n.updatedAt;
    await Future<void>.delayed(const Duration(milliseconds: 8));
    final u = await repo.updateNote(n.id, body: 'two');
    expect(u.body, 'two');
    expect(u.updatedAt.isAfter(before), isTrue);
    expect(repo.getNote(n.id)!.body, 'two');
  });

  test('delete soft-deletes: hidden from list, still on disk, recoverable',
      () async {
    final n = await repo.createNote(body: 'x');
    final deleted = await repo.deleteNote(n.id);

    expect(deleted, isNotNull);
    expect(deleted!.isDeleted, isTrue);
    // Hidden from the live list and getNote, but its blob is untouched.
    expect(repo.getNote(n.id), isNull);
    expect(repo.listNotes(), isEmpty);
    expect(repo.count, 0);
    expect(await File('${dir.path}/notes/${n.id}.note').exists(), isTrue);

    // Surfaced in Recently Deleted and restorable.
    expect(repo.listDeleted().single.id, n.id);
    expect(repo.deletedCount, 1);

    final restored = await repo.restoreNote(n.id);
    expect(restored!.isDeleted, isFalse);
    expect(repo.getNote(n.id)!.body, 'x');
    expect(repo.listDeleted(), isEmpty);
    expect(repo.count, 1);
  });

  test('listDeleted returns most-recently-deleted first; both recoverable',
      () async {
    final a = await repo.createNote(title: 'a');
    final b = await repo.createNote(title: 'b');
    await repo.deleteNote(a.id);
    await Future<void>.delayed(const Duration(milliseconds: 8));
    await repo.deleteNote(b.id);

    // Newest deletion (b) sorts first, regardless of creation order.
    expect(repo.listDeleted().map((n) => n.id).toList(), [b.id, a.id]);

    // Both remain recoverable.
    expect(await repo.restoreNote(a.id), isNotNull);
    expect(await repo.restoreNote(b.id), isNotNull);
    expect(repo.listDeleted(), isEmpty);
    expect(repo.count, 2);
  });

  test('purgeNote refuses to purge a live note', () async {
    final n = await repo.createNote(body: 'x');
    expect(() => repo.purgeNote(n.id), throwsStateError);
    // The note is untouched and still live.
    expect(repo.getNote(n.id), isNotNull);
    expect(await File('${dir.path}/notes/${n.id}.note').exists(), isTrue);
  });

  test('purge permanently removes a soft-deleted note and its file', () async {
    final n = await repo.createNote(body: 'x');
    await repo.deleteNote(n.id);
    await repo.purgeNote(n.id);

    expect(repo.getNote(n.id), isNull);
    expect(repo.listDeleted(), isEmpty);
    expect(await File('${dir.path}/notes/${n.id}.note').exists(), isFalse);
  });

  test('purgeAllDeleted empties Recently Deleted but keeps live notes',
      () async {
    final keep = await repo.createNote(title: 'keep');
    final a = await repo.createNote(title: 'a');
    final b = await repo.createNote(title: 'b');
    await repo.deleteNote(a.id);
    await repo.deleteNote(b.id);

    await repo.purgeAllDeleted();

    expect(repo.listDeleted(), isEmpty);
    expect(repo.listNotes().single.id, keep.id);
  });

  test('deleting an already-deleted note is a no-op', () async {
    final n = await repo.createNote(body: 'x');
    final first = await repo.deleteNote(n.id);
    final again = await repo.deleteNote(n.id);
    expect(again, isNull);
    // The original deletion timestamp is preserved.
    expect(repo.listDeleted().single.deletedAt, first!.deletedAt);
  });

  test('restoring a live note is a no-op', () async {
    final n = await repo.createNote(body: 'x');
    expect(await repo.restoreNote(n.id), isNull);
  });

  test('a soft-deleted note cannot be updated or pinned', () async {
    final n = await repo.createNote(body: 'x');
    await repo.deleteNote(n.id);
    expect(() => repo.updateNote(n.id, body: 'y'), throwsStateError);
    expect(() => repo.setPinned(n.id, true), throwsStateError);
  });

  test('loadAll purges notes past the retention window, keeps recent ones',
      () async {
    final old = await repo.createNote(title: 'old');
    final recent = await repo.createNote(title: 'recent');
    await repo.deleteNote(old.id);
    await repo.deleteNote(recent.id);

    // Backdate the "old" note's deletion beyond the retention window on disk,
    // writing straight through the vault/store to simulate an aged blob.
    final overdue = DateTime.now()
        .toUtc()
        .subtract(NotesRepository.recentlyDeletedRetention)
        .subtract(const Duration(days: 1));
    final aged =
        repo.listDeleted().firstWhere((n) => n.id == old.id).copyWith(
              deletedAt: overdue,
            );
    await store.writeNoteBlob(
        aged.id, await vault.sealNote(aged.toEncodedBytes()));

    vault.lock();
    repo.clear();
    await vault.unlock('pw');
    await repo.loadAll();

    expect(repo.getNote(old.id), isNull);
    expect(repo.listDeleted().any((n) => n.id == old.id), isFalse); // purged
    expect(await File('${dir.path}/notes/${old.id}.note').exists(), isFalse);
    expect(repo.listDeleted().single.id, recent.id); // still within window
  });

  test('soft-delete survives lock + reopen', () async {
    final n = await repo.createNote(title: 'trash me');
    await repo.deleteNote(n.id);
    vault.lock();
    repo.clear();

    final store2 = FileVaultStore(dir);
    final vault2 = VaultService(store: store2);
    await vault2.unlock('pw');
    final repo2 = NotesRepository(vault: vault2, store: store2);
    await repo2.loadAll();

    expect(repo2.listNotes(), isEmpty);
    expect(repo2.listDeleted().single.id, n.id);
  });

  test('list is sorted by updatedAt, newest first', () async {
    final a = await repo.createNote(title: 'a');
    await Future<void>.delayed(const Duration(milliseconds: 8));
    final b = await repo.createNote(title: 'b');
    final list = repo.listNotes();
    expect(list.first.id, b.id);
    expect(list.last.id, a.id);
  });

  test('pinned notes sort above unpinned, newest-first within each group',
      () async {
    final a = await repo.createNote(title: 'a');
    await Future<void>.delayed(const Duration(milliseconds: 8));
    final b = await repo.createNote(title: 'b');
    await Future<void>.delayed(const Duration(milliseconds: 8));
    final c = await repo.createNote(title: 'c');

    // Pin the oldest note; it should jump to the top.
    await repo.setPinned(a.id, true);

    final ids = repo.listNotes().map((n) => n.id).toList();
    expect(ids, [a.id, c.id, b.id]);
  });

  test('setPinned preserves the note modified time', () async {
    final n = await repo.createNote(title: 'a', body: 'body');
    final before = repo.getNote(n.id)!.updatedAt;
    await Future<void>.delayed(const Duration(milliseconds: 8));

    final pinned = await repo.setPinned(n.id, true);
    expect(pinned.pinned, isTrue);
    expect(pinned.updatedAt, before);
  });

  test('setPinned is a no-op when already in the requested state', () async {
    final n = await repo.createNote(title: 'a');
    final same = await repo.setPinned(n.id, false);
    expect(identical(same, n) || same.pinned == false, isTrue);
    expect(same.pinned, isFalse);
  });

  test('setPinned throws for an unknown note', () async {
    expect(() => repo.setPinned('nope', true), throwsStateError);
  });

  test('pinned state persists across lock + reopen', () async {
    final n = await repo.createNote(title: 'keep me up top');
    await repo.setPinned(n.id, true);
    vault.lock();
    repo.clear();

    final store2 = FileVaultStore(dir);
    final vault2 = VaultService(store: store2);
    await vault2.unlock('pw');
    final repo2 = NotesRepository(vault: vault2, store: store2);
    await repo2.loadAll();

    expect(repo2.getNote(n.id)!.pinned, isTrue);
  });

  test('search matches title and body, case-insensitively', () async {
    await repo.createNote(title: 'Groceries', body: 'milk and EGGS');
    await repo.createNote(title: 'Work', body: 'standup notes');
    expect(repo.search('grocer').length, 1);
    expect(repo.search('eggs').length, 1);
    expect(repo.search('NOTES').length, 1);
    expect(repo.search('zzz'), isEmpty);
    expect(repo.search('').length, 2);
  });

  test('notes persist and decrypt after lock + reopen with fresh objects', () async {
    await repo.createNote(title: 'Persisted', body: 'survives reload');
    vault.lock();
    repo.clear();

    final store2 = FileVaultStore(dir);
    final vault2 = VaultService(store: store2);
    await vault2.unlock('pw');
    final repo2 = NotesRepository(vault: vault2, store: store2);
    await repo2.loadAll();

    expect(repo2.count, 1);
    expect(repo2.listNotes().first.title, 'Persisted');
    expect(repo2.listNotes().first.body, 'survives reload');
  });
}
