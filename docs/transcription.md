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
- Android builds and bundles the same native bridge as `librune_whisper.so` for
  `arm64-v8a`, `armeabi-v7a`, and `x86_64`. It uses the whisper service when
  the bundled library and model are available, then falls back to
  `StubTranscriptionService` if native loading fails. Verified on a physical
  device (Samsung Galaxy A53, Android 15 / arm64-v8a): the gated integration
  test transcribes the bundled JFK sample with the expected words.
- iOS builds the same bridge into a static `librune_whisper.a`, force-loads it
  into the Runner binary, and resolves FFI symbols with
  `DynamicLibrary.process()`. This wiring is implemented; physical-device
  transcription verification is pending.
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

## Native source

The pinned whisper.cpp source is a git submodule at `third_party/whisper.cpp`.
Initialize it before native builds:

```bash
git submodule update --init --recursive third_party/whisper.cpp
```

The native bridge lives in `native/whisper/rune_whisper_bridge.cc`; the shared
CMake project in `native/whisper/CMakeLists.txt` builds it against the pinned
whisper.cpp checkout for every supported native target. macOS and Android build
shared libraries, while iOS builds a static archive for the app binary.

## macOS build

The macOS Xcode project runs `tool/whisper/build_macos.sh` as a build phase. The
script validates that `third_party/whisper.cpp` is exactly at the pinned commit,
builds `native/whisper/rune_whisper_bridge.cc` and whisper.cpp from source with
CMake, then copies `librune_whisper.dylib` into the app bundle's
`Contents/Frameworks`.

Install `cmake` before building the macOS app locally. No prebuilt native
library is committed.

## Android build

The Android Gradle project uses `externalNativeBuild` to run the shared CMake
project during `flutter build apk`. The release APK remains a single universal
APK; Gradle packages `lib/<abi>/librune_whisper.so` for `arm64-v8a`,
`armeabi-v7a`, and `x86_64`.

For local native-only builds outside Gradle:

```bash
tool/whisper/build_android.sh
```

Android release builds pass `-ffile-prefix-map` and `-no-canonical-prefixes` to
the native compiler, plus `-Wl,--build-id=none` to the linker, so whisper.cpp
does not embed checkout-specific absolute paths or GNU build-ids in the APK.

## iOS build

iOS cannot load an arbitrary app-bundled dynamic library with `dlopen` in the
same way macOS and Android can. Instead, the Runner Xcode target runs
`tool/whisper/build_ios.sh` before linking. The script validates the pinned
whisper.cpp submodule, configures CMake for iOS (`CMAKE_SYSTEM_NAME=iOS`,
`arm64`, and the active `iphoneos` or `iphonesimulator` SDK), builds the static
whisper.cpp/ggml/bridge libraries, and combines them with `libtool -static`
into:

```text
app/build/whisper/ios/<Configuration><EffectivePlatformName>/librune_whisper.a
```

Runner links that archive with `-force_load` in `OTHER_LDFLAGS`. This is
required because the `rune_whisper_*` C symbols are reached only through Dart
FFI lookups at runtime; without `-force_load`, the linker can dead-strip them
from the static archive. The Dart loader therefore uses
`DynamicLibrary.process()` on iOS, and the `RUNE_WHISPER_LIBRARY` path is unused
there.

## Tests

CI-safe tests cover:

- 16 kHz mono PCM16 WAV decoding.
- `WhisperTranscriptionService.isLocal == true`.
- Graceful unavailability when the model/native library is absent.

The real native transcription path is represented by a skipped integration test
in `app/integration_test/whisper_transcription_test.dart`. To run it manually on
macOS, build the native bridge, then provide:

```bash
RUNE_RUN_WHISPER_TEST=1 \
RUNE_WHISPER_LIBRARY="$PWD/build/macos/Build/Products/Debug/Rune.app/Contents/Frameworks/librune_whisper.dylib" \
flutter test integration_test/whisper_transcription_test.dart
```

To run the same gated test on a connected Android device or emulator, pass the
flag as a `--dart-define` — on-device test processes do not inherit the host
environment, so the `RUNE_RUN_WHISPER_TEST` env var alone would skip the test:

```bash
flutter test -d <android-device-id> \
  --dart-define=RUNE_RUN_WHISPER_TEST=true \
  integration_test/whisper_transcription_test.dart
```

The native library is bundled in the APK, so no `RUNE_WHISPER_LIBRARY` override
is needed. A debug-built engine is slow on mobile CPUs (the gated test allows
several minutes); release builds are far faster.

To run the same gated test on a connected iPhone or iOS simulator:

```bash
flutter test -d <iphone-id> \
  --dart-define=RUNE_RUN_WHISPER_TEST=true \
  integration_test/whisper_transcription_test.dart
```

The expected on-device result is `isStub == false` and a transcript containing
`ask not` and `country`.

Only claim a platform works after that platform has transcribed a real WAV.

## Follow-ups

- F-Droid: update the separate fdroiddata recipe for the NDK build and bundled
  MIT-licensed model asset.
