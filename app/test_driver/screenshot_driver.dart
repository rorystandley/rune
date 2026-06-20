import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Host-side driver: receives screenshot bytes from screenshots_test.dart and
/// writes them to disk. The capture scripts set SCREENSHOT_OUT to a per-device
/// folder (e.g. screenshots/ios/6.9-inch).
Future<void> main() async {
  final outDir = Platform.environment['SCREENSHOT_OUT'] ?? 'screenshots/output';
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('$outDir/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      stdout.writeln('saved $outDir/$name.png');
      return true;
    },
  );
}
