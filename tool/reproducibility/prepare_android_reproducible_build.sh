#!/usr/bin/env bash
# Prepare Flutter/Android build inputs that are generated outside this repo for
# Rune's path-independent reproducible APK build.
#
# Flutter 3.44.2 already has frontend support for FileSystemRoots/FileSystemScheme
# (the mechanism that rewrites file:// source URIs to stable synthetic URIs), and
# its Android Gradle plugin already reads the matching Gradle properties. Two
# wiring gaps remain in this release: the Gradle helper does not forward those
# values to `flutter assemble`, and the compiler URI rewrite uses constructor
# defaults instead of the per-build roots. Patch the disposable pinned Flutter
# SDK to pass and use them.
#
# The Android package:jni native shim also emits a GNU build-id that differs across
# independent links even when the linked bytes are otherwise identical. Disable
# that build-id for Android's libdartjni.so.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <flutter-app-dir>" >&2
  exit 2
fi

APP_DIR="$1"
PACKAGE_CONFIG="$APP_DIR/.dart_tool/package_config.json"

if [ ! -f "$PACKAGE_CONFIG" ]; then
  echo "missing $PACKAGE_CONFIG; run 'flutter pub get' first" >&2
  exit 2
fi

resolve_flutter_root() {
  local flutter_bin
  flutter_bin="$(command -v flutter)"
  if [ -z "$flutter_bin" ]; then
    echo "flutter not found on PATH" >&2
    exit 2
  fi

  while [ -L "$flutter_bin" ]; do
    local dir target
    dir="$(cd -P "$(dirname "$flutter_bin")" && pwd)"
    target="$(readlink "$flutter_bin")"
    if [[ "$target" == /* ]]; then
      flutter_bin="$target"
    else
      flutter_bin="$dir/$target"
    fi
  done

  cd -P "$(dirname "$flutter_bin")/.." && pwd
}

FLUTTER_ROOT="$(resolve_flutter_root)"
FLUTTER_HELPER="$FLUTTER_ROOT/packages/flutter_tools/gradle/src/main/kotlin/tasks/BaseFlutterTaskHelper.kt"
FLUTTER_COMPILE="$FLUTTER_ROOT/packages/flutter_tools/lib/src/compile.dart"

python3 - "$FLUTTER_HELPER" "$FLUTTER_COMPILE" "$PACKAGE_CONFIG" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path
from urllib.parse import unquote, urljoin, urlparse

flutter_helper = Path(sys.argv[1])
flutter_compile = Path(sys.argv[2])
package_config = Path(sys.argv[3])

if not flutter_helper.exists():
    raise SystemExit(f"missing Flutter Gradle helper: {flutter_helper}")
if not flutter_compile.exists():
    raise SystemExit(f"missing Flutter compile.dart: {flutter_compile}")

helper_text = flutter_helper.read_text()
if '-dFileSystemRoots=' not in helper_text:
    needle = '''            baseFlutterTask.extraFrontEndOptions?.let {
                args("--ExtraFrontEndOptions=$it")
            }

'''
    replacement = '''            baseFlutterTask.extraFrontEndOptions?.let {
                args("--ExtraFrontEndOptions=$it")
            }
            baseFlutterTask.fileSystemRoots?.takeIf { it.isNotEmpty() }?.let {
                args("-dFileSystemRoots=${it.joinToString(",")}")
            }
            baseFlutterTask.fileSystemScheme?.let {
                args("-dFileSystemScheme=$it")
            }

'''
    if needle not in helper_text:
        raise SystemExit(
            "Flutter Gradle helper no longer matches the expected 3.44.2 shape; "
            "review the FileSystemRoots forwarding patch."
        )
    flutter_helper.write_text(helper_text.replace(needle, replacement))
    print(f"patched Flutter Gradle helper: {flutter_helper}")
else:
    print(f"Flutter Gradle helper already patched: {flutter_helper}")

compile_text = flutter_compile.read_text()
if "effectiveFileSystemRoots" not in compile_text:
    needle = '''    String? mainUri;
    if (mainPath != null) {
      final File mainFile = _fileSystem.file(mainPath);
      final Uri mainFileUri = mainFile.uri;
      if (packagesPath != null) {
        mainUri = packageConfig.toPackageUri(mainFileUri)?.toString();
      }
      mainUri ??= toMultiRootPath(
        mainFileUri,
        _fileSystemScheme,
        _fileSystemRoots,
        _fileSystem.path.separator == r'\\',
      );
    }
'''
    replacement = '''    final List<String> effectiveFileSystemRoots = fileSystemRoots ?? _fileSystemRoots;
    final String? effectiveFileSystemScheme = fileSystemScheme ?? _fileSystemScheme;

    String? mainUri;
    if (mainPath != null) {
      final File mainFile = _fileSystem.file(mainPath);
      final Uri mainFileUri = mainFile.uri;
      if (packagesPath != null) {
        mainUri = packageConfig.toPackageUri(mainFileUri)?.toString();
      }
      mainUri ??= toMultiRootPath(
        mainFileUri,
        effectiveFileSystemScheme,
        effectiveFileSystemRoots,
        _fileSystem.path.separator == r'\\',
      );
    }
'''
    if needle not in compile_text:
        raise SystemExit(
            "Flutter compile.dart no longer matches the expected 3.44.2 main URI shape; "
            "review the FileSystemRoots URI rewrite patch."
        )
    compile_text = compile_text.replace(needle, replacement)
    needle = '''          toMultiRootPath(
            dartPluginRegistrantFileUri,
            _fileSystemScheme,
            _fileSystemRoots,
            _fileSystem.path.separator == r'\\',
          );
'''
    replacement = '''          toMultiRootPath(
            dartPluginRegistrantFileUri,
            effectiveFileSystemScheme,
            effectiveFileSystemRoots,
            _fileSystem.path.separator == r'\\',
          );
'''
    if needle not in compile_text:
        raise SystemExit(
            "Flutter compile.dart no longer matches the expected 3.44.2 plugin "
            "registrant URI shape; review the FileSystemRoots URI rewrite patch."
        )
    flutter_compile.write_text(compile_text.replace(needle, replacement))
    print(f"patched Flutter compile URI rewrite: {flutter_compile}")
else:
    print(f"Flutter compile URI rewrite already patched: {flutter_compile}")

config = json.loads(package_config.read_text())
config_dir_uri = package_config.parent.resolve().as_uri() + "/"
jni_root_uri = None
for package in config.get("packages", []):
    if package.get("name") == "jni":
        jni_root_uri = package.get("rootUri")
        break

if not jni_root_uri:
    raise SystemExit("package:jni not found in package_config.json")

resolved = urljoin(config_dir_uri, jni_root_uri)
parsed = urlparse(resolved)
if parsed.scheme != "file":
    raise SystemExit(f"package:jni rootUri is not a file URI: {jni_root_uri}")

jni_root = Path(unquote(parsed.path))
jni_cmake = jni_root / "src" / "CMakeLists.txt"
if not jni_cmake.exists():
    raise SystemExit(f"missing package:jni CMakeLists.txt: {jni_cmake}")

cmake_text = jni_cmake.read_text()
if '"-Wl,--build-id=none"' not in cmake_text:
    needle = '''\tif (ANDROID)
\t\ttarget_link_libraries(jni log)
\t\ttarget_link_options(jni PRIVATE "-Wl,-z,max-page-size=16384")
'''
    replacement = '''\tif (ANDROID)
\t\ttarget_link_libraries(jni log)
\t\ttarget_link_options(jni PRIVATE "-Wl,-z,max-page-size=16384" "-Wl,--build-id=none")
'''
    if needle not in cmake_text:
        raise SystemExit(
            "package:jni CMakeLists.txt no longer matches the expected 1.0.0 shape; "
            "review the Android build-id patch."
        )
    jni_cmake.write_text(cmake_text.replace(needle, replacement))
    print(f"patched package:jni CMake: {jni_cmake}")
else:
    print(f"package:jni CMake already patched: {jni_cmake}")
PY

# The Flutter CLI runs from bin/cache/flutter_tools.snapshot. If any Flutter
# source was patched after that snapshot was built, the next `flutter build`
# would otherwise keep using the stale unpatched tool.
rm -f "$FLUTTER_ROOT/bin/cache/flutter_tools.snapshot" \
      "$FLUTTER_ROOT/bin/cache/flutter_tools.stamp"
echo "invalidated Flutter tool snapshot for patched reproducibility wiring"
