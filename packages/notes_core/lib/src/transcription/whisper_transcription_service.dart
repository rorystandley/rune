import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'transcription_service.dart';
import 'wav_decoder.dart';

const String _macosLibraryName = 'librune_whisper.dylib';

typedef WhisperLibraryPathResolver = String Function();

/// Returns the expected runtime path for the bundled whisper bridge library.
String defaultWhisperLibraryPath() {
  final override = Platform.environment['RUNE_WHISPER_LIBRARY'];
  if (override != null && override.isNotEmpty) return override;

  if (Platform.isMacOS) {
    final executable = File(Platform.resolvedExecutable);
    final frameworksPath = executable.parent.parent.path;
    final bundled = File('$frameworksPath/Frameworks/$_macosLibraryName');
    if (bundled.existsSync()) return bundled.path;

    for (final configuration in const ['Debug', 'Profile', 'Release']) {
      final testBundle = File(
        'build/macos/Build/Products/$configuration/'
        'Rune.app/Contents/Frameworks/$_macosLibraryName',
      );
      if (testBundle.existsSync()) return testBundle.path;
    }

    final localBuild = File('build/whisper/macos/$_macosLibraryName');
    if (localBuild.existsSync()) return localBuild.path;
  }

  return _macosLibraryName;
}

/// On-device whisper.cpp transcription backed by the repo's native FFI bridge.
class WhisperTranscriptionService
    implements TranscriptionService, DisposableTranscriptionService {
  WhisperTranscriptionService({
    required this.modelPath,
    this.engineName = 'whisper.cpp tiny.en-q5_1',
    WhisperLibraryPathResolver? libraryPathResolver,
    this.defaultLanguage = 'en',
  }) : _libraryPathResolver = libraryPathResolver ?? defaultWhisperLibraryPath;

  final String modelPath;
  final WhisperLibraryPathResolver _libraryPathResolver;
  final String defaultLanguage;

  _WhisperWorkerClient? _worker;
  Future<_WhisperWorkerClient>? _pendingWorker;
  bool _disposed = false;

  @override
  final String engineName;

  @override
  bool get isLocal => true;

  @override
  Future<bool> isAvailable() async {
    if (!await File(modelPath).exists()) return false;

    final libraryPath = _libraryPathResolver();
    try {
      return await Isolate.run(() => _canOpenWhisperLibrary(libraryPath));
    } catch (_) {
      return false;
    }
  }

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    final worker = await _getWorker();
    final text = await worker.transcribe(
      request.audioFilePath,
      language: _languageFor(request.languageHint),
    );
    return TranscriptionResult(text: text.trim(), engine: engineName);
  }

  @override
  void dispose() {
    _disposed = true;
    _worker?.dispose();
    _worker = null;

    final pending = _pendingWorker;
    if (pending != null) {
      unawaited(pending.then((worker) => worker.dispose()));
    }
  }

  Future<_WhisperWorkerClient> _getWorker() async {
    if (_disposed) {
      throw StateError('WhisperTranscriptionService has been disposed.');
    }

    final existing = _worker;
    if (existing != null) return existing;

    final pending = _pendingWorker;
    if (pending != null) return pending;

    final libraryPath = _libraryPathResolver();
    final created = _WhisperWorkerClient.start(
      modelPath: modelPath,
      libraryPath: libraryPath,
    );
    _pendingWorker = created;
    try {
      final worker = await created;
      if (_disposed) {
        worker.dispose();
        throw StateError('WhisperTranscriptionService has been disposed.');
      }
      _worker = worker;
      return worker;
    } finally {
      if (identical(_pendingWorker, created)) _pendingWorker = null;
    }
  }

  String _languageFor(String? hint) {
    final value =
        (hint == null || hint.trim().isEmpty) ? defaultLanguage : hint.trim();
    final primary = value.split(RegExp('[-_]')).first.toLowerCase();
    return primary.isEmpty ? defaultLanguage : primary;
  }
}

bool _canOpenWhisperLibrary(String libraryPath) {
  final bindings = _RuneWhisperBindings(DynamicLibrary.open(libraryPath));
  return bindings.version().toDartString().isNotEmpty;
}

class _WhisperWorkerClient {
  _WhisperWorkerClient({required this.isolate, required this.commands});

  final Isolate isolate;
  final SendPort commands;
  bool _disposed = false;

  static Future<_WhisperWorkerClient> start({
    required String modelPath,
    required String libraryPath,
  }) async {
    final readyPort = ReceivePort();
    final isolate = await Isolate.spawn(
      _whisperWorkerEntry,
      _WhisperWorkerStart(
        readyPort: readyPort.sendPort,
        modelPath: modelPath,
        libraryPath: libraryPath,
      ),
      debugName: 'Rune whisper.cpp worker',
      errorsAreFatal: true,
    );

    final ready = await readyPort.first.timeout(const Duration(seconds: 60));
    readyPort.close();

    if (ready is _WhisperWorkerReady &&
        ready.error == null &&
        ready.commands != null) {
      return _WhisperWorkerClient(isolate: isolate, commands: ready.commands!);
    }

    isolate.kill(priority: Isolate.immediate);
    final error = ready is _WhisperWorkerReady
        ? ready.error ?? 'Whisper worker did not provide a command port.'
        : 'Unexpected worker startup response: $ready';
    throw StateError(error);
  }

  Future<String> transcribe(String audioFilePath, {required String language}) {
    if (_disposed) {
      throw StateError('Whisper worker has been disposed.');
    }

    final replyPort = ReceivePort();
    commands.send(_WhisperTranscribeMessage(
      audioFilePath: audioFilePath,
      language: language,
      replyPort: replyPort.sendPort,
    ));

    return replyPort.first.timeout(const Duration(minutes: 5)).then((message) {
      replyPort.close();
      if (message is _WhisperTranscribeResult && message.error == null) {
        return message.text!;
      }
      final error = message is _WhisperTranscribeResult
          ? message.error ?? 'Whisper worker returned no transcript.'
          : 'Unexpected worker response: $message';
      throw StateError(error);
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    commands.send(const _WhisperCloseMessage());
    isolate.kill(priority: Isolate.beforeNextEvent);
  }
}

class _WhisperWorkerStart {
  const _WhisperWorkerStart({
    required this.readyPort,
    required this.modelPath,
    required this.libraryPath,
  });

  final SendPort readyPort;
  final String modelPath;
  final String libraryPath;
}

class _WhisperWorkerReady {
  const _WhisperWorkerReady({this.commands, this.error});

  final SendPort? commands;
  final String? error;
}

class _WhisperTranscribeMessage {
  const _WhisperTranscribeMessage({
    required this.audioFilePath,
    required this.language,
    required this.replyPort,
  });

  final String audioFilePath;
  final String language;
  final SendPort replyPort;
}

class _WhisperTranscribeResult {
  const _WhisperTranscribeResult({this.text, this.error});

  final String? text;
  final String? error;
}

class _WhisperCloseMessage {
  const _WhisperCloseMessage();
}

void _whisperWorkerEntry(_WhisperWorkerStart start) {
  final receivePort = ReceivePort();
  _RuneWhisperBindings? bindings;
  Pointer<Void> handle = nullptr;

  try {
    bindings = _RuneWhisperBindings(DynamicLibrary.open(start.libraryPath));
    final modelPath = start.modelPath.toNativeUtf8();
    try {
      handle = bindings.create(modelPath);
    } finally {
      calloc.free(modelPath);
    }

    if (handle == nullptr) {
      start.readyPort.send(_WhisperWorkerReady(
        error: _nativeError(bindings, handle),
      ));
      receivePort.close();
      return;
    }

    start.readyPort.send(_WhisperWorkerReady(
      commands: receivePort.sendPort,
    ));
  } catch (error, stackTrace) {
    start.readyPort.send(_WhisperWorkerReady(
      error: '$error\n$stackTrace',
    ));
    receivePort.close();
    return;
  }

  receivePort.listen((message) {
    if (message is _WhisperCloseMessage) {
      if (handle != nullptr) bindings!.destroy(handle);
      receivePort.close();
      return;
    }

    if (message is _WhisperTranscribeMessage) {
      try {
        final samples = decodePcm16MonoWavFile(message.audioFilePath);
        if (samples.isEmpty) {
          throw const FormatException('Cannot transcribe empty WAV audio.');
        }
        final text = _transcribeSamples(
          bindings!,
          handle,
          samples,
          language: message.language,
        );
        message.replyPort.send(_WhisperTranscribeResult(text: text));
      } catch (error, stackTrace) {
        message.replyPort.send(_WhisperTranscribeResult(
          error: '$error\n$stackTrace',
        ));
      }
    }
  });
}

String _transcribeSamples(
  _RuneWhisperBindings bindings,
  Pointer<Void> handle,
  Float32List samples, {
  required String language,
}) {
  final samplesPointer = calloc<Float>(samples.length);
  final languagePointer = language.toNativeUtf8();
  Pointer<Utf8> result = nullptr;

  try {
    samplesPointer.asTypedList(samples.length).setAll(0, samples);
    result = bindings.transcribe(
      handle,
      samplesPointer,
      samples.length,
      languagePointer,
    );
    if (result == nullptr) {
      throw StateError(_nativeError(bindings, handle));
    }
    return result.toDartString();
  } finally {
    if (result != nullptr) bindings.freeString(result);
    calloc.free(languagePointer);
    calloc.free(samplesPointer);
  }
}

String _nativeError(_RuneWhisperBindings bindings, Pointer<Void> handle) {
  final error = bindings.lastError(handle);
  if (error == nullptr) return 'Unknown whisper.cpp error.';
  return error.toDartString();
}

class _RuneWhisperBindings {
  _RuneWhisperBindings(DynamicLibrary library)
      : create = library.lookupFunction<_CreateNative, _CreateDart>(
          'rune_whisper_create',
        ),
        destroy = library.lookupFunction<_DestroyNative, _DestroyDart>(
          'rune_whisper_destroy',
        ),
        transcribe = library.lookupFunction<_TranscribeNative, _TranscribeDart>(
          'rune_whisper_transcribe',
        ),
        freeString = library.lookupFunction<_FreeStringNative, _FreeStringDart>(
          'rune_whisper_free_string',
        ),
        lastError = library.lookupFunction<_LastErrorNative, _LastErrorDart>(
          'rune_whisper_last_error',
        ),
        version = library.lookupFunction<_VersionNative, _VersionDart>(
          'rune_whisper_version',
        );

  final _CreateDart create;
  final _DestroyDart destroy;
  final _TranscribeDart transcribe;
  final _FreeStringDart freeString;
  final _LastErrorDart lastError;
  final _VersionDart version;
}

typedef _CreateNative = Pointer<Void> Function(Pointer<Utf8> modelPath);
typedef _CreateDart = Pointer<Void> Function(Pointer<Utf8> modelPath);

typedef _DestroyNative = Void Function(Pointer<Void> handle);
typedef _DestroyDart = void Function(Pointer<Void> handle);

typedef _TranscribeNative = Pointer<Utf8> Function(
  Pointer<Void> handle,
  Pointer<Float> samples,
  Int32 sampleCount,
  Pointer<Utf8> language,
);
typedef _TranscribeDart = Pointer<Utf8> Function(
  Pointer<Void> handle,
  Pointer<Float> samples,
  int sampleCount,
  Pointer<Utf8> language,
);

typedef _FreeStringNative = Void Function(Pointer<Utf8> value);
typedef _FreeStringDart = void Function(Pointer<Utf8> value);

typedef _LastErrorNative = Pointer<Utf8> Function(Pointer<Void> handle);
typedef _LastErrorDart = Pointer<Utf8> Function(Pointer<Void> handle);

typedef _VersionNative = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();
