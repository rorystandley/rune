# Wiring in on-device transcription (whisper.cpp)

This build ships a **stub** transcriber so the whole voice-note flow works
end-to-end without pretending to have transcribed anything. This document
explains exactly how to replace the stub with real **on-device** speech-to-text.

## The seam

All transcription goes through one interface in `notes_core`:

```dart
abstract class TranscriptionService {
  String get engineName;
  bool get isLocal;                 // MUST be true — no cloud transcribers
  Future<bool> isAvailable();
  Future<TranscriptionResult> transcribe(TranscriptionRequest request);
}
```

- `TranscriptionRequest.audioFilePath` points at a recorded file. The app records
  **16 kHz mono WAV** (`AudioEncoder.wav`) precisely because that is what
  whisper.cpp expects — no resampling needed.
- The app already does the rest: recording, calling `transcribe(...)`, inserting
  the returned text into a note, and deleting the audio by default.

To switch engines you implement `TranscriptionService` once and pass it into
`AppController(... transcription: YourEngine())` in `app/lib/main.dart`. **No UI
changes are required.**

> Contract: any implementation **must run fully on-device**. Do not implement
> this interface with a cloud API — that would break the app's core promise.

## Option A — whisper.cpp via Dart FFI (recommended for desktop)

1. Build whisper.cpp as a shared library:
   ```bash
   git clone https://github.com/ggerganov/whisper.cpp
   cd whisper.cpp
   cmake -B build -DBUILD_SHARED_LIBS=ON
   cmake --build build --config Release
   # produces libwhisper.{dylib,so,dll}
   ```
2. Download a model (ggml format), e.g. `ggml-base.en.bin`:
   ```bash
   ./models/download-ggml-model.sh base.en
   ```
   Ship the model with the app or let the user pick one. Keep it on-device.
3. Add a Dart FFI binding (e.g. with `package:ffi` + `ffigen`) that calls
   `whisper_init_from_file`, `whisper_full`, and reads the segments back out.
4. Implement the interface:
   ```dart
   class WhisperCppTranscriptionService implements TranscriptionService {
     WhisperCppTranscriptionService({required this.modelPath});
     final String modelPath;

     @override String get engineName => 'whisper.cpp (base.en)';
     @override bool get isLocal => true;
     @override Future<bool> isAvailable() async => File(modelPath).existsSync();

     @override
     Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
       // 1. Read 16 kHz mono PCM from request.audioFilePath (WAV → Float32List).
       // 2. Run whisper_full() via FFI (ideally inside Isolate.run to avoid
       //    blocking the UI thread).
       // 3. Concatenate segment texts.
       return TranscriptionResult(text: text, engine: engineName);
     }
   }
   ```
5. Wire it up in `app/lib/main.dart`:
   ```dart
   transcription: WhisperCppTranscriptionService(modelPath: modelFile.path),
   ```

## Option B — a packaged plugin

Packages such as `whisper_ggml` / `whisper_flutter_plus` wrap whisper.cpp for
Flutter (handy on Android/iOS where bundling native libs by hand is fiddly).
Implement `TranscriptionService` on top of the chosen package's API. Verify it
performs inference **locally** and bundles/loads the model from device storage.

## Performance notes

- Run inference off the UI isolate (`Isolate.run`) so the app stays responsive.
- `base.en` is a good speed/quality trade-off for note dictation; `tiny.en` is
  faster on low-end phones.
- The model file is large (tens to hundreds of MB). Decide whether to bundle it
  or download once on first use (a download *is* a network call, so make it
  explicit, opt-in, and one-time — consistent with PRIVACY.md).

## Tests

Add a unit test that feeds a short known WAV and asserts the transcript contains
expected words, plus a test asserting `isLocal == true`. The existing voice-note
UI flow needs no change.
