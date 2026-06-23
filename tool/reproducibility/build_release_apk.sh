#!/usr/bin/env bash
# Build Rune's release APK deterministically and copy it to a chosen path.
#
# Used both by the local double-build helper (build_twice.sh) and by the
# reproducibility CI job, which calls this once per clean checkout. It pins the
# one build input that lives outside the toolchain — SOURCE_DATE_EPOCH, derived
# from the current commit's date — and otherwise relies on the versions recorded
# in RELEASE.md and docs/fdroid/co.rorystandley.rune.yml (Flutter, Gradle, AGP,
# NDK, compileSdk, Java 17). See RELEASE.md → "Reproducible / verifiable builds".
#
# Usage: build_release_apk.sh <output.apk>
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <output.apk>" >&2
  exit 2
fi
OUT="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_DIR="$REPO_ROOT/app"

# Honour SOURCE_DATE_EPOCH for any timestamped packaging. Derive it from the
# commit date so an independent rebuild of the same commit picks the same value.
if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
  SOURCE_DATE_EPOCH="$(git -C "$REPO_ROOT" log -1 --pretty=%ct)"
fi
export SOURCE_DATE_EPOCH
export TZ=UTC
echo "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH ($(date -u -r "$SOURCE_DATE_EPOCH" 2>/dev/null || date -u -d "@$SOURCE_DATE_EPOCH"))"

cd "$APP_DIR"
flutter --version
# A clean build removes any stale, possibly machine-specific intermediates so the
# result reflects the source alone.
flutter clean
flutter pub get
flutter build apk --release

SRC="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
mkdir -p "$(dirname "$OUT")"
cp "$SRC" "$OUT"
echo "wrote $OUT"
sha256sum "$OUT" 2>/dev/null || shasum -a 256 "$OUT"
