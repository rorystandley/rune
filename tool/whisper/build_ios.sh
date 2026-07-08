#!/usr/bin/env bash
set -euo pipefail

WHISPER_CPP_COMMIT="43d78af5be58f41d6ffbc227d608f104577741ea"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null 2>&1 && pwd -P)"
APP_DIR="$ROOT_DIR/app"
SOURCE_DIR="${WHISPER_CPP_SOURCE_DIR:-$ROOT_DIR/third_party/whisper.cpp}"

# Put Homebrew's cmake/ninja on PATH for GUI build phases (see the helper).
source "$(dirname "${BASH_SOURCE[0]}")/homebrew_path.sh"

if ! command -v cmake >/dev/null 2>&1; then
  echo "error: cmake is required to build whisper.cpp from source." >&2
  echo "Install cmake, then rebuild the iOS app." >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "error: xcrun is required to locate the iOS SDK." >&2
  echo "Install Xcode, then rebuild the iOS app." >&2
  exit 1
fi

LIBTOOL="${LIBTOOL:-/usr/bin/libtool}"
if [ ! -x "$LIBTOOL" ]; then
  echo "error: libtool is required to combine the iOS static archives." >&2
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

normalize_sdk() {
  local value="$1"
  local name
  name="$(basename "$value" .sdk | tr '[:upper:]' '[:lower:]')"

  case "$name" in
    iphoneos*)
      printf '%s\n' "iphoneos"
      ;;
    iphonesimulator*)
      printf '%s\n' "iphonesimulator"
      ;;
    *)
      echo "error: unsupported iOS SDK '$value'." >&2
      echo "Expected iphoneos or iphonesimulator." >&2
      exit 1
      ;;
  esac
}

resolve_sdks() {
  if [ -n "${SDKROOT:-}" ]; then
    normalize_sdk "$SDKROOT"
    return
  fi

  printf '%s\n' ${IOS_SDKS:-iphoneos iphonesimulator}
}

CONFIG="${CONFIGURATION:-Release}"
ARCHS="${RUNE_WHISPER_IOS_ARCHS:-arm64}"
DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-${IOS_DEPLOYMENT_TARGET:-13.0}}"
BUILD_ROOT="$APP_DIR/build/whisper/ios"
GENERATOR_NAME=""
if command -v ninja >/dev/null 2>&1; then
  GENERATOR_NAME="Ninja"
fi

for sdk in $(resolve_sdks); do
  sdk="$(normalize_sdk "$sdk")"
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  platform_name="-$sdk"
  output_dir="$BUILD_ROOT/$CONFIG$platform_name"
  cmake_dir="$output_dir/cmake"

  cmake_args=(
    -S "$ROOT_DIR/native/whisper"
    -B "$cmake_dir"
    -DCMAKE_BUILD_TYPE="$CONFIG"
    -DCMAKE_SYSTEM_NAME=iOS
    -DCMAKE_OSX_ARCHITECTURES="$ARCHS"
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
    -DCMAKE_OSX_SYSROOT="$sdk_path"
    -DWHISPER_CPP_SOURCE_DIR="$SOURCE_DIR"
  )

  if [ -n "$GENERATOR_NAME" ]; then
    cmake_args=(-G "$GENERATOR_NAME" "${cmake_args[@]}")
  fi

  cmake "${cmake_args[@]}"
  cmake --build "$cmake_dir" --config "$CONFIG" --target rune_whisper --parallel

  archives=()
  while IFS= read -r archive; do
    archives+=("$archive")
  done < <(find "$cmake_dir" -type f -name '*.a' | sort)

  if [ "${#archives[@]}" -eq 0 ]; then
    echo "error: no static archives were produced under $cmake_dir." >&2
    exit 1
  fi

  mkdir -p "$output_dir"
  rm -f "$output_dir/librune_whisper.a" "$output_dir/librune_whisper.a.tmp"
  "$LIBTOOL" -static -o "$output_dir/librune_whisper.a.tmp" "${archives[@]}"
  mv "$output_dir/librune_whisper.a.tmp" "$output_dir/librune_whisper.a"

  echo "Built $output_dir/librune_whisper.a"
done
