import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:notes_app/app.dart';

import 'demo_seed.dart';

/// Drives the seeded app to each store-worthy screen and captures a screenshot.
/// Run via the capture scripts in tool/screenshots/, which point a driver
/// (test_driver/screenshot_driver.dart) at a specific simulator/emulator size.
Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Avoid pumpAndSettle: editor/search text fields have a blinking cursor that
  // never "settles", which would hang the test. Pump fixed frames instead.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  testWidgets('capture store screenshots', (tester) async {
    final controller = await buildSeededController();
    await tester.pumpWidget(NotesApp(controller: controller));
    await settle(tester);

    // Android renders to a surface that must be converted before capture.
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await settle(tester);
    }

    // 1) Home / library (two-pane on tablet & desktop, list on phone).
    await binding.takeScreenshot('01-home');

    // 2) Settings.
    final settings = find.byIcon(Icons.settings_outlined);
    if (settings.evaluate().isNotEmpty) {
      await tester.tap(settings.first);
      await settle(tester);
      await binding.takeScreenshot('02-settings');
      await tester.pageBack();
      await settle(tester);
    }

    // 3) A note open in the editor.
    final hero = find.text('Welcome to Notes');
    if (hero.evaluate().isNotEmpty) {
      await tester.tap(hero.first);
      await settle(tester);
      await binding.takeScreenshot('03-editor');
    }
  });
}
