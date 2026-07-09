import 'dart:io';

import 'package:notes_core/notes_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late VaultService vault;
  late NotesRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('notes_repo_test_');
    final crypto = CryptoService();
    final store = FileVaultStore(dir);
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

  test('delete removes the note and its file', () async {
    final n = await repo.createNote(body: 'x');
    await repo.deleteNote(n.id);
    expect(repo.getNote(n.id), isNull);
    expect(await File('${dir.path}/notes/${n.id}.note').exists(), isFalse);
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
