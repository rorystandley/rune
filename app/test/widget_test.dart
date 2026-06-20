import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/app.dart';
import 'package:notes_app/platform/audio_recorder.dart';
import 'package:notes_app/state/app_controller.dart';
import 'package:notes_app/state/app_settings.dart';
import 'package:notes_core/notes_core.dart';

// NOTE: anything that touches the filesystem (createTemp, settings load,
// vault init, crypto) must run inside `tester.runAsync` — real I/O futures
// never complete under the widget tester's fake-async clock.

AppController _newController(Directory root) {
  final store = SettingsStore(File('${root.path}/settings.json'));
  return AppController(
    vaultDir: Directory('${root.path}/vault'),
    audioTempDir: Directory('${root.path}/audio'),
    exportsDir: Directory('${root.path}/exports'),
    settingsStore: store,
    transcription: const StubTranscriptionService(),
    recorder: const UnavailableAudioRecorder(),
    createKdfParams:
        CryptoService().newKdfParams(memoryKiB: 256, iterations: 1, parallelism: 1),
  );
}

void main() {
  testWidgets('first launch shows the create-vault screen with the warning',
      (tester) async {
    late Directory root;
    late AppController controller;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('notes_widget_test_');
      controller = _newController(root);
      await controller.settingsStore.save(const AppSettings(autoLockMinutes: 0));
      await controller.init();
    });

    await tester.pumpWidget(NotesApp(controller: controller));
    await tester.pump();

    expect(find.text('Create your vault'), findsOneWidget);
    expect(find.text('There is no password reset'), findsOneWidget);
    expect(find.byKey(const Key('create-button')), findsOneWidget);

    controller.dispose();
    await tester.runAsync(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  });

  testWidgets('after creating a vault, the notes UI renders', (tester) async {
    late Directory root;
    late AppController controller;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('notes_widget_test_');
      controller = _newController(root);
      await controller.settingsStore.save(const AppSettings(autoLockMinutes: 0));
      await controller.init();
    });

    await tester.pumpWidget(NotesApp(controller: controller));
    await tester.pump();

    await tester.runAsync(() async {
      await controller.createVault('passphrase123');
      final note = await controller.newNote();
      await controller.saveNote(note.id, title: 'Hello', body: 'world');
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new-note-button')), findsOneWidget);
    expect(find.byKey(const Key('lock-button')), findsOneWidget);
    expect(find.text('Hello'), findsWidgets);

    controller.dispose();
    await tester.runAsync(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  });

  testWidgets('tapping the new-note button creates a visible note',
      (tester) async {
    late Directory root;
    late AppController controller;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('notes_widget_test_');
      controller = _newController(root);
      await controller.settingsStore.save(const AppSettings(autoLockMinutes: 0));
      await controller.init();
      await controller.createVault('passphrase123');
    });

    await tester.pumpWidget(NotesApp(controller: controller));
    await tester.pumpAndSettle();
    expect(controller.phase, AppPhase.unlocked);
    expect(controller.repo.count, 0);

    // Tap the new-note control and let the async create complete.
    await tester.tap(find.byKey(const Key('new-note-button')));
    // Let the async create (crypto + file write) settle, draining both the
    // real event loop and the test's fake-async queue.
    for (var i = 0; i < 40 && controller.repo.count == 0; i++) {
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(controller.repo.count, 1); // the tap actually created a note
    expect(find.text('New note'), findsWidgets); // and it renders

    controller.dispose();
    await tester.runAsync(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  });
}
