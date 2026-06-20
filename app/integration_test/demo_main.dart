import 'package:flutter/widgets.dart';
import 'package:notes_app/app.dart';

import 'demo_seed.dart';

/// Manual entry point for the seeded demo app. Useful for eyeballing or for
/// capturing screenshots on platforms where the automated driver can't (e.g.
/// take a desktop window shot):
///
///   flutter run -t integration_test/demo_main.dart -d macos
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await buildSeededController();
  runApp(NotesApp(controller: controller));
}
