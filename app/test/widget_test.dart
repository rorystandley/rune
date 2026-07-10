import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/app.dart';
import 'package:notes_app/platform/audio_recorder.dart';
import 'package:notes_app/platform/biometric_unlock_store.dart';
import 'package:notes_app/state/app_controller.dart';
import 'package:notes_app/state/app_scope.dart';
import 'package:notes_app/state/app_settings.dart';
import 'package:notes_app/ui/widgets/note_editor.dart';
import 'package:notes_core/notes_core.dart';

// NOTE: anything that touches the filesystem (createTemp, settings load,
// vault init, crypto) must run inside `tester.runAsync` — real I/O futures
// never complete under the widget tester's fake-async clock.

AppController _newController(
  Directory root, {
  BiometricUnlockStore? biometricUnlockStore,
}) {
  final store = SettingsStore(File('${root.path}/settings.json'));
  return AppController(
    vaultDir: Directory('${root.path}/vault'),
    audioTempDir: Directory('${root.path}/audio'),
    exportsDir: Directory('${root.path}/exports'),
    settingsStore: store,
    transcription: const StubTranscriptionService(),
    recorder: const UnavailableAudioRecorder(),
    biometricUnlockStore: biometricUnlockStore,
    createKdfParams: CryptoService().newKdfParams(
      memoryKiB: 256,
      iterations: 1,
      parallelism: 1,
    ),
  );
}

void main() {
  testWidgets('first launch shows the create-vault screen with the warning', (
    tester,
  ) async {
    late Directory root;
    late AppController controller;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('notes_widget_test_');
      controller = _newController(root);
      await controller.settingsStore.save(
        const AppSettings(autoLockMinutes: 0),
      );
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
      await controller.settingsStore.save(
        const AppSettings(autoLockMinutes: 0),
      );
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

  testWidgets('tapping the new-note button creates a visible note', (
    tester,
  ) async {
    late Directory root;
    late AppController controller;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('notes_widget_test_');
      controller = _newController(root);
      await controller.settingsStore.save(
        const AppSettings(autoLockMinutes: 0),
      );
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
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
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

  testWidgets('pinning a note surfaces a Pinned section at the top', (
    tester,
  ) async {
    late Directory root;
    late AppController controller;
    late Note pinned;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('notes_pin_test_');
      controller = _newController(root);
      await controller.settingsStore.save(
        const AppSettings(autoLockMinutes: 0),
      );
      await controller.init();
      await controller.createVault('passphrase123');
      pinned = await controller.newNote();
      await controller.saveNote(pinned.id, title: 'Keep me', body: '');
      final other = await controller.newNote();
      await controller.saveNote(other.id, title: 'Ordinary', body: '');
    });

    // Force the wide two-pane layout so the sidebar list is visible.
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(NotesApp(controller: controller));
    await tester.pumpAndSettle();

    // No section headers until something is pinned.
    expect(find.text('PINNED'), findsNothing);

    await tester.runAsync(() => controller.togglePinned(pinned.id));
    await tester.pumpAndSettle();

    expect(find.text('PINNED'), findsOneWidget);
    expect(find.text('NOTES'), findsOneWidget);
    expect(controller.visibleNotes.first.id, pinned.id);

    controller.dispose();
    await tester.runAsync(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  });

  testWidgets('deleting a note shows an Undo snackbar that restores it', (
    tester,
  ) async {
    late Directory root;
    late AppController controller;
    late Note note;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('notes_undo_test_');
      controller = _newController(root);
      await controller.settingsStore.save(
        const AppSettings(autoLockMinutes: 0),
      );
      await controller.init();
      await controller.createVault('passphrase123');
      note = await controller.newNote();
      await controller.saveNote(note.id, title: 'Delete me', body: 'body');
    });

    // Wide layout so the editor toolbar (with its delete button) is on screen.
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(NotesApp(controller: controller));
    await tester.pumpAndSettle();

    // Select the note, then delete it.
    await tester.tap(find.text('Delete me').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete note'));
    for (var i = 0; i < 40 && controller.deletedNotes.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    // Let the snackbar finish sliding in so its action is hit-testable.
    await tester.pumpAndSettle();

    // Soft-deleted, and the Undo affordance is shown.
    expect(controller.deletedNotes.length, 1);
    expect(controller.visibleNotes, isEmpty);
    expect(find.text('Note deleted'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    // Undo brings it back.
    await tester.tap(find.text('Undo'));
    for (var i = 0; i < 40 && controller.deletedNotes.isNotEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(controller.deletedNotes, isEmpty);
    expect(controller.visibleNotes.single.title, 'Delete me');

    controller.dispose();
    await tester.runAsync(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  });

  testWidgets('Recently Deleted footer opens the view and restores a note', (
    tester,
  ) async {
    late Directory root;
    late AppController controller;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('notes_trash_test_');
      controller = _newController(root);
      await controller.settingsStore.save(
        const AppSettings(autoLockMinutes: 0),
      );
      await controller.init();
      await controller.createVault('passphrase123');
      final n = await controller.newNote();
      await controller.saveNote(n.id, title: 'Trashed', body: '');
      await controller.deleteNote(n.id);
    });

    await tester.pumpWidget(NotesApp(controller: controller));
    await tester.pumpAndSettle();

    // The footer surfaces because a note is in Recently Deleted.
    expect(find.byKey(const Key('recently-deleted-entry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('recently-deleted-entry')));
    await tester.pumpAndSettle();
    expect(find.text('Recently Deleted'), findsWidgets);
    expect(find.text('Trashed'), findsOneWidget);

    // Open the note's actions and restore it.
    await tester.tap(find.text('Trashed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    for (var i = 0; i < 40 && controller.deletedNotes.isNotEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(controller.deletedNotes, isEmpty);
    expect(controller.visibleNotes.single.title, 'Trashed');

    controller.dispose();
    await tester.runAsync(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  });

  testWidgets('Recently Deleted: Delete forever and Empty purge permanently', (
    tester,
  ) async {
    late Directory root;
    late AppController controller;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('notes_purge_test_');
      controller = _newController(root);
      await controller.settingsStore.save(
        const AppSettings(autoLockMinutes: 0),
      );
      await controller.init();
      await controller.createVault('passphrase123');
      final a = await controller.newNote();
      await controller.saveNote(a.id, title: 'Alpha', body: '');
      final b = await controller.newNote();
      await controller.saveNote(b.id, title: 'Beta', body: '');
      await controller.deleteNote(a.id);
      await controller.deleteNote(b.id);
    });

    await tester.pumpWidget(NotesApp(controller: controller));
    await tester.pumpAndSettle();

    // Open Recently Deleted (both notes are in the bin).
    await tester.tap(find.byKey(const Key('recently-deleted-entry')));
    await tester.pumpAndSettle();
    expect(controller.deletedNotes.length, 2);

    // Delete one forever: tile action -> confirm dialog -> Delete.
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete forever'));
    await tester.pumpAndSettle();
    expect(find.text('Delete forever?'), findsOneWidget); // confirm shown
    await tester.tap(find.text('Delete'));
    for (var i = 0; i < 40 && controller.deletedNotes.length == 2; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(controller.deletedNotes.single.title, 'Beta'); // Alpha gone for good

    // Empty the rest: app-bar action -> confirm dialog -> Delete All.
    await tester.tap(find.text('Empty'));
    await tester.pumpAndSettle();
    expect(find.text('Empty Recently Deleted?'), findsOneWidget);
    await tester.tap(find.text('Delete All'));
    for (var i = 0; i < 40 && controller.deletedNotes.isNotEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(controller.deletedNotes, isEmpty);
    expect(controller.visibleNotes, isEmpty); // nothing resurrected

    controller.dispose();
    await tester.runAsync(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  });

  testWidgets('enabled biometric unlock runs automatically when locked', (
    tester,
  ) async {
    late Directory root;
    late AppController controller;
    final biometrics = WidgetBiometricUnlockStore();
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('notes_biometric_test_');
      controller = _newController(root, biometricUnlockStore: biometrics);
      await controller.settingsStore.save(
        const AppSettings(autoLockMinutes: 0),
      );
      await controller.init();
      await controller.createVault('passphrase123');
      final note = await controller.newNote();
      await controller.saveNote(note.id, title: 'Automatic', body: 'unlock');
      expect(await controller.enableBiometricUnlock(), isTrue);
      controller.lock();
    });

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(NotesApp(controller: controller));
    await tester.pump();

    for (var i = 0; i < 40 && controller.phase != AppPhase.unlocked; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(biometrics.readCount, 1);
    expect(controller.phase, AppPhase.unlocked);
    expect(find.text('Automatic'), findsWidgets);

    controller.dispose();
    await tester.runAsync(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  });

  testWidgets('automatic biometric failure does not create a prompt loop', (
    tester,
  ) async {
    late Directory root;
    late AppController controller;
    final biometrics = WidgetBiometricUnlockStore();
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('notes_biometric_test_');
      controller = _newController(root, biometricUnlockStore: biometrics);
      await controller.settingsStore.save(
        const AppSettings(autoLockMinutes: 0),
      );
      await controller.init();
      await controller.createVault('passphrase123');
      expect(await controller.enableBiometricUnlock(), isTrue);
      biometrics.failReads = true;
      controller.lock();
    });

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(NotesApp(controller: controller));
    await tester.pump();

    for (var i = 0; i < 40 && controller.busy; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(biometrics.readCount, 1);
    expect(controller.phase, AppPhase.locked);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(biometrics.readCount, 1);
    expect(find.byKey(const Key('biometric-unlock-button')), findsOneWidget);
    expect(find.byKey(const Key('unlock-pass')), findsOneWidget);

    controller.dispose();
    await tester.runAsync(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  });

  testWidgets('Appearance: theme toggle drives the MaterialApp theme mode', (
    tester,
  ) async {
    late Directory root;
    late AppController controller;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('notes_theme_test_');
      controller = _newController(root);
      await controller.settingsStore.save(
        const AppSettings(autoLockMinutes: 0),
      );
      await controller.init();
      await controller.createVault('passphrase123');
    });

    await tester.pumpWidget(NotesApp(controller: controller));
    await tester.pumpAndSettle();

    // Follows the OS by default.
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );

    // Open Settings and force Dark from the theme segmented control.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Text size'), findsOneWidget); // Appearance section shown
    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await tester.pumpAndSettle();

    expect(controller.settings.themeMode, ThemeMode.dark);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );

    controller.dispose();
    await tester.runAsync(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  });

  testWidgets('Appearance: text-size slider scales the app text', (
    tester,
  ) async {
    late Directory root;
    late AppController controller;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('notes_textsize_test_');
      controller = _newController(root);
      await controller.settingsStore.save(
        const AppSettings(autoLockMinutes: 0),
      );
      await controller.init();
      await controller.createVault('passphrase123');
    });

    // Pin a known surface so the slider geometry (and thus the drag) is
    // deterministic regardless of any view size a prior test left behind.
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(NotesApp(controller: controller));
    await tester.pumpAndSettle();

    // Open Settings and drive the real text-size slider (its onChangeEnd wires
    // through to updateSettings). Reading the scaler off a Settings element
    // proves the app-wide MediaQuery composition, since it wraps every route.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    double appTextScale() => MediaQuery.textScalerOf(
      tester.element(find.text('Text size')),
    ).scale(10);
    final before = appTextScale();

    // Drag well past the track end; the slider clamps to the maximum preference.
    await tester.drag(find.byType(Slider), const Offset(2000, 0));
    await tester.pumpAndSettle();

    expect(controller.settings.textScale, AppSettings.maxTextScale);
    expect(appTextScale(), greaterThan(before));

    controller.dispose();
    await tester.runAsync(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  });

  testWidgets('editor insert handle appends a transcript into the open note', (
    tester,
  ) async {
    late Directory root;
    late AppController controller;
    late Note note;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('notes_editor_test_');
      controller = _newController(root);
      await controller.settingsStore.save(
        const AppSettings(autoLockMinutes: 0),
      );
      await controller.init();
      await controller.createVault('passphrase123');
      note = await controller.newNote();
      await controller.saveNote(note.id, title: 'T', body: 'first line');
      note = controller.repo.getNote(note.id)!;
    });

    final handle = EditorInsertHandle();
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          home: Scaffold(
            body: NoteEditorView(note: note, insertHandle: handle),
          ),
        ),
      ),
    );
    await tester.pump();

    // The mounted editor wired itself to the handle, and an inserted transcript
    // lands in the open note's body on its own line — not in a new note.
    expect(handle.isAttached, isTrue);
    handle.insert('dictated words');
    await tester.pump();

    expect(find.text('first line\ndictated words'), findsOneWidget);
    expect(controller.repo.count, 1); // no extra note was created

    controller.dispose();
    await tester.runAsync(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  });

  testWidgets('editor centres its content within a reading measure when wide', (
    tester,
  ) async {
    late Directory root;
    late AppController controller;
    late Note note;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('notes_measure_test_');
      controller = _newController(root);
      await controller.settingsStore.save(
        const AppSettings(autoLockMinutes: 0),
      );
      await controller.init();
      await controller.createVault('passphrase123');
      note = await controller.newNote();
      note = controller.repo.getNote(note.id)!;
    });

    Future<double> titleInsetAt(double width) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        AppScope(
          controller: controller,
          child: MaterialApp(
            home: Scaffold(body: NoteEditorView(note: note)),
          ),
        ),
      );
      await tester.pump();
      return tester.getTopLeft(find.byKey(const Key('editor-title'))).dx;
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Narrow: edge-to-edge with only the base 20px gutter.
    expect(await titleInsetAt(400), closeTo(20, 0.5));
    // Wide: the width beyond the 720 measure + its two 20px gutters is split
    // into side padding, so the content column is exactly 720 and stays centred.
    expect(await titleInsetAt(1400), closeTo(20 + (1400 - 720 - 40) / 2, 0.5));

    controller.dispose();
    await tester.runAsync(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  });

  testWidgets('desktop shortcuts: focus search, Esc clears, ⌘L locks', (
    tester,
  ) async {
    // Reset in `finally` rather than `addTearDown`: this global is checked by
    // the framework's end-of-body invariant assertion, which runs *before*
    // teardowns — so a leaked override would fail the check. `finally` also
    // restores it if an `expect` throws early.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    late Directory root;
    late AppController controller;
    try {
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('notes_shortcut_test_');
        controller = _newController(root);
        await controller.settingsStore.save(
          const AppSettings(autoLockMinutes: 0),
        );
        await controller.init();
        await controller.createVault('passphrase123');
        final n = await controller.newNote();
        await controller.saveNote(n.id, title: 'Findable', body: '');
      });

      // Wide two-pane layout, where the desktop shortcuts live.
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(NotesApp(controller: controller));
      await tester.pumpAndSettle();

      final searchField =
          tester.widget<TextField>(find.byKey(const Key('search-field')));
      expect(searchField.focusNode!.hasFocus, isFalse);

      // ⌘F focuses the search field.
      await _sendCmd(tester, LogicalKeyboardKey.keyF);
      expect(searchField.focusNode!.hasFocus, isTrue);

      // Type a query, then Esc clears it and drops focus.
      await tester.enterText(find.byKey(const Key('search-field')), 'Findable');
      await tester.pumpAndSettle();
      expect(controller.search, 'Findable');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(controller.search, isEmpty);
      expect(searchField.controller!.text, isEmpty);
      expect(searchField.focusNode!.hasFocus, isFalse);

      // ⌘L locks the vault.
      await _sendCmd(tester, LogicalKeyboardKey.keyL);
      expect(controller.phase, AppPhase.locked);

      controller.dispose();
      await tester.runAsync(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop shortcuts: ⌘N creates a note and ⌘⌫ soft-deletes it', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    late Directory root;
    late AppController controller;
    try {
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('notes_shortcut_cud_test_');
        controller = _newController(root);
        await controller.settingsStore.save(
          const AppSettings(autoLockMinutes: 0),
        );
        await controller.init();
        await controller.createVault('passphrase123');
      });

      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(NotesApp(controller: controller));
      await tester.pumpAndSettle();
      expect(controller.repo.count, 0);

      // ⌘N creates a note and selects it.
      await _sendCmd(tester, LogicalKeyboardKey.keyN);
      for (var i = 0; i < 40 && controller.repo.count == 0; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(controller.repo.count, 1);
      expect(controller.selectedId, isNotNull);

      // ⌘⌫ soft-deletes the selected note into Recently Deleted (focus is on
      // the home node, not a text field, so the delete action is enabled).
      await _sendCmd(tester, LogicalKeyboardKey.backspace);
      for (var i = 0; i < 40 && controller.deletedNotes.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(controller.deletedNotes.length, 1);
      expect(controller.visibleNotes, isEmpty);
      expect(controller.selectedId, isNull);
      expect(find.text('Note deleted'), findsOneWidget); // Undo snackbar shown

      controller.dispose();
      await tester.runAsync(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop shortcuts use Ctrl on non-Apple platforms', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    late Directory root;
    late AppController controller;
    try {
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('notes_shortcut_ctrl_test_');
        controller = _newController(root);
        await controller.settingsStore.save(
          const AppSettings(autoLockMinutes: 0),
        );
        await controller.init();
        await controller.createVault('passphrase123');
      });

      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(NotesApp(controller: controller));
      await tester.pumpAndSettle();
      expect(controller.repo.count, 0);

      // Ctrl+N is the non-mac binding — it creates and selects a note.
      await _sendCtrl(tester, LogicalKeyboardKey.keyN);
      for (var i = 0; i < 40 && controller.repo.count == 0; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(controller.repo.count, 1);

      // Ctrl+F focuses the search field.
      final searchField =
          tester.widget<TextField>(find.byKey(const Key('search-field')));
      expect(searchField.focusNode!.hasFocus, isFalse);
      await _sendCtrl(tester, LogicalKeyboardKey.keyF);
      expect(searchField.focusNode!.hasFocus, isTrue);

      controller.dispose();
      await tester.runAsync(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('⌘⌫ does not delete the note while the editor is focused', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    late Directory root;
    late AppController controller;
    late Note note;
    try {
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('notes_shortcut_edit_test_');
        controller = _newController(root);
        await controller.settingsStore.save(
          const AppSettings(autoLockMinutes: 0),
        );
        await controller.init();
        await controller.createVault('passphrase123');
        note = await controller.newNote();
        await controller.saveNote(note.id, title: 'Editing', body: 'body');
      });

      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(NotesApp(controller: controller));
      await tester.pumpAndSettle();

      // Open the note and put focus into the editor's title field.
      await tester.tap(find.text('Editing').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor-title')));
      await tester.pumpAndSettle();

      // With a text field focused the delete action stands aside, so ⌘⌫ is the
      // editor's delete-to-line-start — the note itself must survive.
      await _sendCmd(tester, LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(controller.deletedNotes, isEmpty);
      expect(controller.visibleNotes.single.id, note.id);

      controller.dispose();
      await tester.runAsync(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('wide search field seeds from the active query', (
    tester,
  ) async {
    late Directory root;
    late AppController controller;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('notes_search_seed_test_');
      controller = _newController(root);
      await controller.settingsStore.save(
        const AppSettings(autoLockMinutes: 0),
      );
      await controller.init();
      await controller.createVault('passphrase123');
      final n = await controller.newNote();
      await controller.saveNote(n.id, title: 'Findable', body: '');
    });

    // A query is already active (as it would be after searching in the narrow
    // layout) before the wide layout builds.
    controller.setSearch('Findable');

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(NotesApp(controller: controller));
    await tester.pumpAndSettle();

    // The wide sidebar field reflects the query rather than sitting blank over
    // a filtered list.
    final searchField =
        tester.widget<TextField>(find.byKey(const Key('search-field')));
    expect(searchField.controller!.text, 'Findable');

    controller.dispose();
    await tester.runAsync(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  });

  testWidgets('search field shows a clear button that empties the query', (
    tester,
  ) async {
    late Directory root;
    late AppController controller;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('notes_clearbtn_test_');
      controller = _newController(root);
      await controller.settingsStore.save(
        const AppSettings(autoLockMinutes: 0),
      );
      await controller.init();
      await controller.createVault('passphrase123');
      final n = await controller.newNote();
      await controller.saveNote(n.id, title: 'Keep', body: '');
    });

    await tester.pumpWidget(NotesApp(controller: controller));
    await tester.pumpAndSettle();

    // No clear button until there is a query.
    expect(find.byKey(const Key('search-clear')), findsNothing);

    await tester.enterText(find.byKey(const Key('search-field')), 'zzz');
    await tester.pumpAndSettle();
    expect(controller.search, 'zzz');
    expect(find.byKey(const Key('search-clear')), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-clear')));
    await tester.pumpAndSettle();
    expect(controller.search, isEmpty);
    expect(find.byKey(const Key('search-clear')), findsNothing);
    expect(controller.visibleNotes.single.title, 'Keep');

    controller.dispose();
    await tester.runAsync(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  });
}

/// Sends a Cmd+[key] chord (macOS modifier) and settles the frame.
Future<void> _sendCmd(WidgetTester tester, LogicalKeyboardKey key) =>
    _sendChord(tester, LogicalKeyboardKey.meta, key);

/// Sends a Ctrl+[key] chord (Windows/Linux modifier) and settles the frame.
Future<void> _sendCtrl(WidgetTester tester, LogicalKeyboardKey key) =>
    _sendChord(tester, LogicalKeyboardKey.control, key);

Future<void> _sendChord(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

class WidgetBiometricUnlockStore implements BiometricUnlockStore {
  String? _vaultBinding;
  Uint8List? _dek;
  int readCount = 0;
  bool failReads = false;

  @override
  Future<BiometricUnlockAvailability> checkAvailability() async =>
      const BiometricUnlockAvailability.available('Test biometrics');

  @override
  Future<void> clearCachedDek() async {
    _vaultBinding = null;
    _dek = null;
  }

  @override
  Future<Uint8List?> readCachedDek({required String vaultBinding}) async {
    readCount++;
    if (failReads) throw StateError('Biometric prompt canceled.');
    final dek = _dek;
    if (_vaultBinding != vaultBinding || dek == null) return null;
    return Uint8List.fromList(dek);
  }

  @override
  Future<void> saveCachedDek({
    required String vaultBinding,
    required Uint8List dek,
  }) async {
    _vaultBinding = vaultBinding;
    _dek = Uint8List.fromList(dek);
  }
}
