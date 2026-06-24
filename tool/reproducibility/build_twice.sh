#!/usr/bin/env bash
# Build the release APK twice from this working tree and diff the two builds,
# ignoring only the signature. This is the local equivalent of the
# `reproducibility` CI job (.github/workflows/reproducibility.yml) and the
# command referenced in RELEASE.md.
#
# It proves *self-consistency* (this toolchain builds the same bytes twice). The
# stronger property — that an independent rebuild on the pinned toolchain matches
# the published APK — is what an independent rebuilder verifies; the toolchain is
# pinned in RELEASE.md. If diffoscope is installed, a full human-readable diff
# is written alongside the APKs for inspecting any residual differences.
#
# Usage: build_twice.sh [output-dir]   (default: a fresh temp dir)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-$(mktemp -d -t rune-repro-XXXXXX)}"
mkdir -p "$OUT_DIR"
APK1="$OUT_DIR/build-1.apk"
APK2="$OUT_DIR/build-2.apk"

echo "==> Build 1 -> $APK1"
"$SCRIPT_DIR/build_release_apk.sh" "$APK1"

echo "==> Build 2 -> $APK2"
"$SCRIPT_DIR/build_release_apk.sh" "$APK2"

echo "==> Comparing (ignoring the signature)"
set +e
python3 "$SCRIPT_DIR/compare_apks.py" "$APK1" "$APK2"
RC=$?
set -e

# Best-effort deep diff for the report. diffoscope understands APK/ZIP structure
# and is what F-Droid uses; we never gate on it, only capture it when present.
if command -v diffoscope >/dev/null 2>&1; then
  echo "==> diffoscope report -> $OUT_DIR/diffoscope.txt"
  diffoscope "$APK1" "$APK2" --text "$OUT_DIR/diffoscope.txt" || true
fi

echo
echo "APKs and any report are in: $OUT_DIR"
exit $RC
