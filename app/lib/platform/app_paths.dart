import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Resolves where vault data, settings, temp audio, and exports live on each
/// platform. The only place the app touches platform-specific directories.
class AppPaths {
  AppPaths({required this.base, required this.exportsBase});

  /// App-private data (vault, settings, temp audio).
  final Directory base;

  /// User-visible location for exports (Documents).
  final Directory exportsBase;

  static Future<AppPaths> resolve() async {
    final support = await getApplicationSupportDirectory();
    final docs = await getApplicationDocumentsDirectory();
    return AppPaths(
      base: Directory('${support.path}/notes_app'),
      exportsBase: Directory('${docs.path}/notes_app_exports'),
    );
  }

  Directory get vaultDir => Directory('${base.path}/vault');
  File get settingsFile => File('${base.path}/settings.json');
  Directory get tempAudioDir => Directory('${base.path}/audio_tmp');
  Directory get modelsDir => Directory('${base.path}/models');
}
