import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/app.dart';
import 'package:notes_app/platform/audio_recorder.dart';
import 'package:notes_app/state/app_controller.dart';
import 'package:notes_app/state/app_settings.dart';
import 'package:notes_core/notes_core.dart';

/// Recorder whose permission or start step can be held open so a test can
/// dismiss the sheet while that step is still in flight.
class _FakeRecorder implements AudioRecorderPort {
  _FakeRecorder({this.permission});

  final Completer<bool>? permission;

  bool recording = false;
  String? path;
  int startCount = 0;
  int stopCount = 0;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> hasPermission() async {
    final gate = permission;
    if (gate == null) return true;
    return gate.future;
  }

  @override
  Future<void> start(String filePath) async {
    startCount++;
    final file = File(filePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('audio', flush: true);
    path = filePath;
    recording = true;
  }

  @override
  Future<String?> stop() async {
    stopCount++;
    if (!recording) return null;
    recording = false;
    final stopped = path;
    path = null;
    return stopped;
  }

  @override
  Future<bool> isRecording() async => recording;

  @override
  Future<void> dispose() async {
    recording = false;
  }
}

/// Transcription that stays in progress until [gate] completes.
class _HoldingTranscription implements TranscriptionService {
  final Completer<void> gate = Completer<void>();

  @override
  String get engineName => 'test';

  @override
  bool get isLocal => true;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) {
    return gate.future.then(
      (_) => const TranscriptionResult(text: 'transcript', engine: 'test'),
    );
  }
}

class _Harness {
  _Harness({
    required this.root,
    required this.audioDir,
    required this.controller,
    required this.recorder,
    this.transcription,
  });

  final Directory root;
  final Directory audioDir;
  final AppController controller;
  final _FakeRecorder recorder;
  final _HoldingTranscription? transcription;

  List<String> audioNames() {
    if (!audioDir.existsSync()) return const [];
    return audioDir
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .toList()
      ..sort();
  }

  Future<void> dispose() async {
    controller.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

Future<_Harness> _harness({
  Completer<bool>? permission,
  _HoldingTranscription? transcription,
  bool keepAudioByDefault = false,
}) async {
  final root = await Directory.systemTemp.createTemp('voice_sheet_');
  final audioDir = Directory('${root.path}/audio');
  await audioDir.create();
  final recorder = _FakeRecorder(permission: permission);
  final settings = SettingsStore(File('${root.path}/settings.json'));
  await settings.save(
    AppSettings(autoLockMinutes: 0, keepAudioByDefault: keepAudioByDefault),
  );
  final controller = AppController(
    vaultDir: Directory('${root.path}/vault'),
    audioTempDir: audioDir,
    exportsDir: Directory('${root.path}/exports'),
    settingsStore: settings,
    transcription: transcription ?? const StubTranscriptionService(),
    recorder: recorder,
    createKdfParams: CryptoService().newKdfParams(
      memoryKiB: 256,
      iterations: 1,
      parallelism: 1,
    ),
  );
  await controller.init();
  await controller.createVault('passphrase123');
  return _Harness(
    root: root,
    audioDir: audioDir,
    controller: controller,
    recorder: recorder,
    transcription: transcription,
  );
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Future<void> _openVoiceSheet(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Voice note'));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('Start recording'), findsOneWidget);
}

Future<void> _dismissSheet(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator)).pop();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> mount(WidgetTester tester, _Harness harness) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(NotesApp(controller: harness.controller));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'voice sheet dismissed while recording stops the recorder and leaves no temp audio',
    (tester) async {
      late _Harness harness;
      await tester.runAsync(() async {
        harness = await _harness();
      });
      await mount(tester, harness);

      await _openVoiceSheet(tester);
      await tester.tap(find.text('Start recording'));
      await _flush(tester);
      expect(find.text('Stop & transcribe'), findsOneWidget);
      expect(harness.recorder.recording, isTrue);
      expect(harness.audioNames(), isNotEmpty);

      await _dismissSheet(tester);
      await _flush(tester);

      expect(harness.recorder.recording, isFalse);
      expect(harness.recorder.stopCount, greaterThan(0));
      expect(harness.audioNames(), isEmpty);
      expect(find.byType(AlertDialog), findsNothing);

      await tester.runAsync(harness.dispose);
    },
  );

  testWidgets(
    'voice sheet dismissed during permission prompt does not start a recording',
    (tester) async {
      final permission = Completer<bool>();
      late _Harness harness;
      await tester.runAsync(() async {
        harness = await _harness(permission: permission);
      });
      await mount(tester, harness);

      await _openVoiceSheet(tester);
      await tester.tap(find.text('Start recording'));
      await tester.pump();
      expect(harness.recorder.startCount, 0);

      await _dismissSheet(tester);
      permission.complete(true);
      await _flush(tester);

      expect(harness.recorder.startCount, 0);
      expect(harness.recorder.recording, isFalse);
      expect(harness.audioNames(), isEmpty);
      expect(find.byType(AlertDialog), findsNothing);

      await tester.runAsync(harness.dispose);
    },
  );

  testWidgets(
    'voice sheet dismissed during transcription leaves no temp audio',
    (tester) async {
      final transcription = _HoldingTranscription();
      late _Harness harness;
      await tester.runAsync(() async {
        harness = await _harness(transcription: transcription);
      });
      await mount(tester, harness);

      try {
        await _openVoiceSheet(tester);
        await tester.tap(find.text('Start recording'));
        await _flush(tester);
        expect(find.text('Stop & transcribe'), findsOneWidget);

        await tester.tap(find.text('Stop & transcribe'));
        await _flush(tester);
        expect(find.text('Transcribing locally…'), findsOneWidget);
        expect(harness.recorder.recording, isFalse);
        expect(harness.audioNames(), isNotEmpty);

        await _dismissSheet(tester);
        await _flush(tester);

        expect(harness.recorder.recording, isFalse);
        expect(harness.audioNames(), isEmpty);
        expect(find.byType(AlertDialog), findsNothing);

        if (!transcription.gate.isCompleted) transcription.gate.complete();
        await _flush(tester);
        expect(harness.controller.visibleNotes, isEmpty);
      } finally {
        if (!transcription.gate.isCompleted) transcription.gate.complete();
        await _flush(tester);
        await tester.runAsync(harness.dispose);
      }
    },
  );

  testWidgets(
    'app lock while recording stops the recorder and leaves no temp audio',
    (tester) async {
      late _Harness harness;
      await tester.runAsync(() async {
        harness = await _harness();
      });
      await mount(tester, harness);

      await _openVoiceSheet(tester);
      await tester.tap(find.text('Start recording'));
      await _flush(tester);
      expect(find.text('Stop & transcribe'), findsOneWidget);
      expect(harness.recorder.recording, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _flush(tester);

      expect(harness.controller.phase, AppPhase.locked);
      expect(harness.recorder.recording, isFalse);
      expect(harness.recorder.stopCount, greaterThan(0));
      expect(harness.audioNames(), isEmpty);
      expect(find.text('Voice note'), findsNothing);
      expect(find.text('Rune is locked'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(Dialog), findsNothing);

      await tester.runAsync(harness.dispose);
    },
  );

  test('unlock removes leftover audio temp files', () async {
    final harness = await _harness();
    harness.controller.lock();
    final leftover = File('${harness.audioDir.path}/voice-orphan.wav');
    final kept = File('${harness.audioDir.path}/kept-voice-1.wav');
    await leftover.writeAsString('orphan', flush: true);
    await kept.writeAsString('kept', flush: true);

    expect(await harness.controller.unlock('passphrase123'), isTrue);

    expect(leftover.existsSync(), isFalse);
    expect(kept.existsSync(), isTrue);
    await harness.dispose();
  });

  test(
    'pre-upgrade voice files survive unlock and a later leftover is removed',
    () async {
      final root = await Directory.systemTemp.createTemp('voice_migrate_');
      final audioDir = Directory('${root.path}/audio');
      await audioDir.create();
      final pre = File('${audioDir.path}/voice-pre.wav');
      final also = File('${audioDir.path}/voice-also.wav');
      await pre.writeAsString('pre-upgrade', flush: true);
      await also.writeAsString('also-pre', flush: true);

      final settings = SettingsStore(File('${root.path}/settings.json'));
      await settings.save(const AppSettings(autoLockMinutes: 0));

      AppController build() => AppController(
        vaultDir: Directory('${root.path}/vault'),
        audioTempDir: audioDir,
        exportsDir: Directory('${root.path}/exports'),
        settingsStore: settings,
        transcription: const StubTranscriptionService(),
        recorder: _FakeRecorder(),
        createKdfParams: CryptoService().newKdfParams(
          memoryKiB: 256,
          iterations: 1,
          parallelism: 1,
        ),
      );

      final first = build();
      await first.init();
      await first.createVault('passphrase123');
      final keptPre = File('${audioDir.path}/kept-voice-pre.wav');
      final keptAlso = File('${audioDir.path}/kept-voice-also.wav');
      expect(await keptPre.readAsString(), 'pre-upgrade');
      expect(await keptAlso.readAsString(), 'also-pre');
      expect(pre.existsSync(), isFalse);
      expect(also.existsSync(), isFalse);

      first.lock();
      expect(await first.unlock('passphrase123'), isTrue);
      expect(await keptPre.readAsString(), 'pre-upgrade');
      expect(await keptAlso.readAsString(), 'also-pre');
      first.dispose();

      final abandoned = File('${audioDir.path}/voice-abandoned.wav');
      await abandoned.writeAsString('abandoned', flush: true);
      final second = build();
      await second.init();
      expect(second.phase, AppPhase.locked);
      expect(await second.unlock('passphrase123'), isTrue);
      expect(abandoned.existsSync(), isFalse);
      expect(
        File('${audioDir.path}/kept-voice-abandoned.wav').existsSync(),
        isFalse,
      );
      expect(await keptPre.readAsString(), 'pre-upgrade');
      expect(await keptAlso.readAsString(), 'also-pre');

      second.lock();
      expect(await second.unlock('passphrase123'), isTrue);
      expect(abandoned.existsSync(), isFalse);
      expect(await keptPre.readAsString(), 'pre-upgrade');
      expect(await keptAlso.readAsString(), 'also-pre');
      final marker = File(
        '${root.path}/${AppController.voiceAudioMigrationMarkerName}',
      );
      expect(await marker.readAsString(), isNot(contains('pre-upgrade')));
      expect(await marker.readAsString(), isNot(contains('abandoned')));
      second.dispose();
      await root.delete(recursive: true);
    },
  );

  testWidgets('kept audio remains after transcription and the next unlock', (
    tester,
  ) async {
    late _Harness harness;
    await tester.runAsync(() async {
      harness = await _harness(keepAudioByDefault: true);
    });
    await mount(tester, harness);

    await _openVoiceSheet(tester);
    await tester.tap(find.text('Start recording'));
    await _flush(tester);
    await tester.tap(find.text('Stop & transcribe'));
    for (var i = 0; i < 40; i++) {
      await _flush(tester);
      if (harness.audioNames().any((name) => name.startsWith('kept-')) &&
          harness.controller.visibleNotes.isNotEmpty) {
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 400));

    expect(harness.controller.visibleNotes, isNotEmpty);
    expect(
      harness.audioNames().where((name) => name.startsWith('voice-')),
      isEmpty,
    );
    expect(
      harness.audioNames().where((name) => name.startsWith('kept-')),
      isNotEmpty,
    );

    harness.controller.lock();
    await tester.pump();
    expect(
      await tester.runAsync(() => harness.controller.unlock('passphrase123')),
      isTrue,
    );
    await tester.pump();

    expect(
      harness.audioNames().where((name) => name.startsWith('kept-')),
      isNotEmpty,
    );
    expect(
      harness.audioNames().where((name) => !name.startsWith('kept-')),
      isEmpty,
    );

    // Let the "audio kept" snackbar timer finish.
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(harness.dispose);
  });
}
