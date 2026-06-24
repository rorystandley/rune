#!/usr/bin/env bash
set -euo pipefail

WHISPER_CPP_COMMIT="43d78af5be58f41d6ffbc227d608f104577741ea"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null 2>&1 && pwd -P)"
APP_DIR="$ROOT_DIR/app"
SOURCE_DIR="${WHISPER_CPP_SOURCE_DIR:-$ROOT_DIR/third_party/whisper.cpp}"

if ! command -v cmake >/dev/null 2>&1; then
  echo "error: cmake is required to build whisper.cpp from source." >&2
  echo "Install cmake, then rebuild the macOS app." >&2
  exit 1
fi

if [ -d "$SOURCE_DIR/.git" ]; then
  actual_commit="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
  if [ "$actual_commit" != "$WHISPER_CPP_COMMIT" ]; then
    echo "error: $SOURCE_DIR is at $actual_commit, expected $WHISPER_CPP_COMMIT." >&2
    exit 1
  fi
else
  SOURCE_DIR="$APP_DIR/build/whisper/src/whisper.cpp"
  if [ ! -d "$SOURCE_DIR/.git" ]; then
    git clone https://github.com/ggml-org/whisper.cpp.git "$SOURCE_DIR"
  fi
  git -C "$SOURCE_DIR" fetch --depth 1 origin "$WHISPER_CPP_COMMIT"
  git -C "$SOURCE_DIR" checkout --detach "$WHISPER_CPP_COMMIT"
fi

CONFIG="${CONFIGURATION:-Release}"
BUILD_DIR="$APP_DIR/build/whisper/macos"
CMAKE_DIR="$BUILD_DIR/cmake"

cmake \
  -S "$ROOT_DIR/native/whisper" \
  -B "$CMAKE_DIR" \
  -DCMAKE_BUILD_TYPE="$CONFIG" \
  -DWHISPER_CPP_SOURCE_DIR="$SOURCE_DIR" \
  ${MACOSX_DEPLOYMENT_TARGET:+-DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET"}

cmake --build "$CMAKE_DIR" --config "$CONFIG" --target rune_whisper --parallel

LIBRARY="$CMAKE_DIR/bin/librune_whisper.dylib"
mkdir -p "$BUILD_DIR"
cp "$LIBRARY" "$BUILD_DIR/librune_whisper.dylib"

if [ -n "${BUILT_PRODUCTS_DIR:-}" ] && [ -n "${FRAMEWORKS_FOLDER_PATH:-}" ]; then
  mkdir -p "$BUILT_PRODUCTS_DIR/$FRAMEWORKS_FOLDER_PATH"
  cp "$LIBRARY" "$BUILT_PRODUCTS_DIR/$FRAMEWORKS_FOLDER_PATH/librune_whisper.dylib"
fi

echo "Built $LIBRARY"
