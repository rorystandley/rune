# On-device transcription with whisper.cpp

Rune routes all speech-to-text through `TranscriptionService` in
`packages/notes_core/lib/src/transcription/transcription_service.dart`:

```dart
abstract class TranscriptionService {
  String get engineName;
  bool get isLocal; // must be true
  Future<bool> isAvailable();
  Future<TranscriptionResult> transcribe(TranscriptionRequest request);
}
```

The product rule is unchanged: transcription must run fully on-device. Do not
put a cloud or remote API behind this interface.

## Current status

- macOS uses `WhisperTranscriptionService`, a Dart FFI service backed by a small
  native bridge around whisper.cpp. Recording already produces 16 kHz mono WAV,
  and the service decodes that PCM16 WAV directly into `Float32List` samples.
- Android and iOS still fall back to `StubTranscriptionService` until their
  native build/linking PRs land.
- Windows and Linux intentionally keep `StubTranscriptionService`.

The app factory is `app/lib/platform/transcription_factory.dart`. It copies the
bundled Flutter model asset into the application-support directory on first run
because native whisper.cpp needs a real file path, not an asset URI.

## Pinned inputs

- whisper.cpp source: `ggml-org/whisper.cpp` commit
  `43d78af5be58f41d6ffbc227d608f104577741ea`.
- Model asset: `app/assets/models/ggml-tiny.en-q5_1.bin`.
- Model source: `https://huggingface.co/ggerganov/whisper.cpp`, revision
  `5359861c739e955e79d9a303bcbc70fb988958b1`, file
  `ggml-tiny.en-q5_1.bin`.
- Model SHA-256:
  `c77c5766f1cef09b6b7d47f21b546cbddd4157886b3b5d6d4f709e91e66c7c2b`.
- Licenses: whisper.cpp is MIT licensed by the ggml authors. The bundled model
  is an OpenAI Whisper model converted to ggml format; the Hugging Face model
  repo is marked MIT, and OpenAI documents Whisper code and weights as MIT.

## macOS build

The macOS Xcode project runs `tool/whisper/build_macos.sh` as a build phase. The
script:

1. Uses `third_party/whisper.cpp` if it exists and is exactly at the pinned
   commit.
2. Otherwise fetches the pinned commit into `app/build/whisper/src/whisper.cpp`.
3. Builds `native/whisper/rune_whisper_bridge.cc` and whisper.cpp from source
   with CMake.
4. Copies `librune_whisper.dylib` into the app bundle's `Contents/Frameworks`.

Install `cmake` before building the macOS app locally. No prebuilt native
library is committed.

## Tests

CI-safe tests cover:

- 16 kHz mono PCM16 WAV decoding.
- `WhisperTranscriptionService.isLocal == true`.
- Graceful unavailability when the model/native library is absent.

The real native transcription path is represented by a skipped integration test
in `app/integration_test/whisper_transcription_test.dart`. To run it manually,
build the native bridge, then provide:

```bash
RUNE_RUN_WHISPER_TEST=1 \
RUNE_WHISPER_LIBRARY="$PWD/build/macos/Build/Products/Debug/Rune.app/Contents/Frameworks/librune_whisper.dylib" \
flutter test integration_test/whisper_transcription_test.dart
```

Only claim a platform works after that platform has transcribed a real WAV.

## Follow-ups

- Android: add the NDK/CMake build for `arm64-v8a`, `armeabi-v7a`, and `x86_64`,
  bundle the `.so`, and extend `tool/reproducibility/build_release_apk.sh` so
  whisper's native library stays deterministic.
- iOS: build a static library or xcframework and load it with
  `DynamicLibrary.process()`.
- F-Droid: update the separate fdroiddata recipe for the NDK build and bundled
  MIT-licensed model asset.
