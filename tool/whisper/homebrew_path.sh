#!/usr/bin/env bash
# Shared PATH setup for the whisper.cpp build scripts (build_ios.sh,
# build_macos.sh, build_android.sh). Sourced, not executed directly.
#
# Xcode.app / Android Studio GUI build phases run with a minimal PATH
# (/usr/bin:/bin:/usr/sbin:/sbin) that omits Homebrew, so a Homebrew-installed
# cmake/ninja isn't found even though a terminal `flutter build` works. Prepend
# the common Homebrew bin dirs (Apple Silicon + Intel); on Linux/CI these dirs
# don't exist and are harmlessly ignored. Keep this the single place to maintain
# the Homebrew bin-dir setup.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
