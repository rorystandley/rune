#!/usr/bin/env bash
set -euo pipefail

WHISPER_CPP_COMMIT="43d78af5be58f41d6ffbc227d608f104577741ea"
ANDROID_NDK_VERSION="${ANDROID_NDK_VERSION:-28.2.13676358}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-24}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null 2>&1 && pwd -P)"
APP_DIR="$ROOT_DIR/app"
ANDROID_DIR="$APP_DIR/android"
SOURCE_DIR="${WHISPER_CPP_SOURCE_DIR:-$ROOT_DIR/third_party/whisper.cpp}"

if ! command -v cmake >/dev/null 2>&1; then
  echo "error: cmake is required to build whisper.cpp from source." >&2
  exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
  echo "error: missing whisper.cpp checkout at $SOURCE_DIR." >&2
  echo "Run 'git submodule update --init --recursive third_party/whisper.cpp'." >&2
  exit 1
fi

if ! git -C "$SOURCE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  echo "error: $SOURCE_DIR is not a git checkout." >&2
  exit 1
fi

actual_commit="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
if [ "$actual_commit" != "$WHISPER_CPP_COMMIT" ]; then
  echo "error: $SOURCE_DIR is at $actual_commit, expected $WHISPER_CPP_COMMIT." >&2
  exit 1
fi

read_local_property() {
  local key="$1"
  local file="$ANDROID_DIR/local.properties"
  if [ ! -f "$file" ]; then
    return 1
  fi
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

resolve_android_sdk_dir() {
  if [ -n "${ANDROID_HOME:-}" ]; then
    printf '%s\n' "$ANDROID_HOME"
    return
  fi
  if [ -n "${ANDROID_SDK_ROOT:-}" ]; then
    printf '%s\n' "$ANDROID_SDK_ROOT"
    return
  fi
  read_local_property "sdk.dir"
}

resolve_ndk_dir() {
  if [ -n "${ANDROID_NDK_HOME:-}" ]; then
    printf '%s\n' "$ANDROID_NDK_HOME"
    return
  fi
  if [ -n "${ANDROID_NDK_ROOT:-}" ]; then
    printf '%s\n' "$ANDROID_NDK_ROOT"
    return
  fi
  local sdk_dir
  sdk_dir="$(resolve_android_sdk_dir || true)"
  if [ -n "$sdk_dir" ]; then
    printf '%s\n' "$sdk_dir/ndk/$ANDROID_NDK_VERSION"
  fi
}

NDK_DIR="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [ -z "$NDK_DIR" ]; then
  NDK_DIR="$(resolve_ndk_dir || true)"
fi

if [ -z "$NDK_DIR" ] || [ ! -d "$NDK_DIR" ]; then
  echo "error: Android NDK $ANDROID_NDK_VERSION not found." >&2
  echo "Set ANDROID_NDK_HOME or install it under the Android SDK ndk directory." >&2
  exit 1
fi

TOOLCHAIN_FILE="$NDK_DIR/build/cmake/android.toolchain.cmake"
if [ ! -f "$TOOLCHAIN_FILE" ]; then
  echo "error: missing Android CMake toolchain file at $TOOLCHAIN_FILE." >&2
  exit 1
fi

CONFIG="${CONFIGURATION:-Release}"
BUILD_DIR="$APP_DIR/build/whisper/android"
ABIS="${ANDROID_ABIS:-arm64-v8a armeabi-v7a x86_64}"
REPRO_FLAGS="-ffile-prefix-map=$SOURCE_DIR=third_party/whisper.cpp -ffile-prefix-map=$ROOT_DIR=. -no-canonical-prefixes"
GENERATOR_NAME=""
if command -v ninja >/dev/null 2>&1; then
  GENERATOR_NAME="Ninja"
fi

for abi in $ABIS; do
  CMAKE_DIR="$BUILD_DIR/$abi/cmake"

  if [ -n "$GENERATOR_NAME" ]; then
    cmake \
      -G "$GENERATOR_NAME" \
      -S "$ROOT_DIR/native/whisper" \
      -B "$CMAKE_DIR" \
      -DCMAKE_BUILD_TYPE="$CONFIG" \
      -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
      -DANDROID_ABI="$abi" \
      -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
      -DANDROID_STL=c++_shared \
      -DWHISPER_CPP_SOURCE_DIR="$SOURCE_DIR" \
      -DCMAKE_C_FLAGS="$REPRO_FLAGS" \
      -DCMAKE_CXX_FLAGS="$REPRO_FLAGS" \
      -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--build-id=none"
  else
    cmake \
      -S "$ROOT_DIR/native/whisper" \
      -B "$CMAKE_DIR" \
      -DCMAKE_BUILD_TYPE="$CONFIG" \
      -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
      -DANDROID_ABI="$abi" \
      -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
      -DANDROID_STL=c++_shared \
      -DWHISPER_CPP_SOURCE_DIR="$SOURCE_DIR" \
      -DCMAKE_C_FLAGS="$REPRO_FLAGS" \
      -DCMAKE_CXX_FLAGS="$REPRO_FLAGS" \
      -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--build-id=none"
  fi

  cmake --build "$CMAKE_DIR" --config "$CONFIG" --target rune_whisper --parallel

  mkdir -p "$BUILD_DIR/$abi"
  cp "$CMAKE_DIR/bin/librune_whisper.so" "$BUILD_DIR/$abi/librune_whisper.so"
  echo "Built $BUILD_DIR/$abi/librune_whisper.so"
done
