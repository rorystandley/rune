import 'dart:convert';
import 'dart:io';

/// Non-sensitive application preferences.
///
/// Stored UNENCRYPTED in `settings.json` because it contains no secrets — only
/// a lock timeout and a couple of toggles. This is documented in PRIVACY.md so
/// the choice is explicit rather than hidden.
class AppSettings {
  const AppSettings({
    this.autoLockMinutes = 5,
    this.lockOnBackground = true,
    this.keepAudioByDefault = false,
  });

  /// Inactivity timeout before auto-lock. 0 disables the timer.
  final int autoLockMinutes;

  /// Lock when the app is sent to the background.
  final bool lockOnBackground;

  /// Whether to keep the raw audio file after transcription. Defaults to false
  /// (privacy-first: discard the recording).
  final bool keepAudioByDefault;

  AppSettings copyWith({
    int? autoLockMinutes,
    bool? lockOnBackground,
    bool? keepAudioByDefault,
  }) =>
      AppSettings(
        autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
        lockOnBackground: lockOnBackground ?? this.lockOnBackground,
        keepAudioByDefault: keepAudioByDefault ?? this.keepAudioByDefault,
      );

  Map<String, dynamic> toJson() => {
        'autoLockMinutes': autoLockMinutes,
        'lockOnBackground': lockOnBackground,
        'keepAudioByDefault': keepAudioByDefault,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        autoLockMinutes: (json['autoLockMinutes'] as int?) ?? 5,
        lockOnBackground: (json['lockOnBackground'] as bool?) ?? true,
        keepAudioByDefault: (json['keepAudioByDefault'] as bool?) ?? false,
      );
}

/// Reads/writes [AppSettings] to a JSON file. Tolerant of a missing/corrupt
/// file (falls back to defaults) so a bad settings file can never lock the
/// user out of their notes.
class SettingsStore {
  SettingsStore(this.file);

  final File file;

  Future<AppSettings> load() async {
    try {
      if (!await file.exists()) return const AppSettings();
      return AppSettings.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
  }
}
