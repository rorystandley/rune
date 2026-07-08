// Generates `app/lib/app_version.g.dart` from the `version:` in
// `app/pubspec.yaml`, so the version shown in Settings has a single source of
// truth and never drifts from the pubspec that CI/F-Droid/the stores build from.
//
// Run from the repo root after bumping the version:
//
//     dart run tool/gen_app_version.dart
//
// CI regenerates and fails if the committed file is stale, so a forgotten
// regeneration can never ship a wrong version string.
//
// Pure `dart:io` on purpose — no package dependency, so it runs with just the
// Dart SDK and adds nothing to the app's dependency tree.
import 'dart:io';

void main() {
  final pubspec = File('app/pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln(
      'gen_app_version: app/pubspec.yaml not found — run from the repo root.',
    );
    exit(1);
  }

  final match = RegExp(
    r'^version:\s*(\d+\.\d+\.\d+)(?:\+(\d+))?',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  if (match == null) {
    stderr.writeln(
      'gen_app_version: no `version: X.Y.Z[+N]` line in app/pubspec.yaml.',
    );
    exit(1);
  }

  final version = match.group(1)!;
  final build = match.group(2); // may be null if there is no `+N` suffix
  final display = build == null ? version : '$version (build $build)';

  final out = File('app/lib/app_version.g.dart');
  out.writeAsStringSync('''
// GENERATED FILE — DO NOT EDIT.
//
// Written by tool/gen_app_version.dart from the `version:` in app/pubspec.yaml,
// so Settings never carries a hand-maintained copy of the version. Regenerate
// after bumping the version: `dart run tool/gen_app_version.dart`. CI fails if
// this file is out of sync with the pubspec.
//
// kAppBuildNumber is deliberately nullable (a pubspec version may omit `+N`),
// so ignore the lint when the current value happens to be non-null.
// ignore_for_file: unnecessary_nullable_for_final_variable_declarations

/// Semantic version, e.g. "0.3.0".
const String kAppVersion = '$version';

/// Build number (the `+N` suffix), or null when the pubspec has none.
const String? kAppBuildNumber = ${build == null ? 'null' : "'$build'"};

/// Human-readable version shown in Settings, e.g. "0.3.0 (build 3)".
const String kAppVersionDisplay = '$display';
''');

  stdout.writeln('gen_app_version: wrote ${out.path} ($display)');
}
