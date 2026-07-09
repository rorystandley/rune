import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;

const Object _unchanged = Object();

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
    this.biometricUnlockEnabled = false,
    this.biometricUnlockVaultBinding,
    this.themeMode = ThemeMode.system,
    this.textScale = 1.0,
  });

  /// Bounds for the in-app reading text size. Kept modest so the layout stays
  /// intact at either extreme.
  static const double minTextScale = 0.85;
  static const double maxTextScale = 1.40;

  /// Inactivity timeout before auto-lock. 0 disables the timer.
  final int autoLockMinutes;

  /// Lock when the app is sent to the background.
  final bool lockOnBackground;

  /// Whether to keep the raw audio file after transcription. Defaults to false
  /// (privacy-first: discard the recording).
  final bool keepAudioByDefault;

  /// Opt-in toggle for caching the vault DEK behind platform authentication.
  final bool biometricUnlockEnabled;

  /// Non-secret binding for the vault header the cached DEK belongs to.
  final String? biometricUnlockVaultBinding;

  /// Light / Dark / System app theme. Defaults to following the OS.
  final ThemeMode themeMode;

  /// Reading text-size multiplier applied app-wide, in
  /// [minTextScale]..[maxTextScale]. 1.0 is the default size.
  final double textScale;

  AppSettings copyWith({
    int? autoLockMinutes,
    bool? lockOnBackground,
    bool? keepAudioByDefault,
    bool? biometricUnlockEnabled,
    Object? biometricUnlockVaultBinding = _unchanged,
    ThemeMode? themeMode,
    double? textScale,
  }) => AppSettings(
    autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
    lockOnBackground: lockOnBackground ?? this.lockOnBackground,
    keepAudioByDefault: keepAudioByDefault ?? this.keepAudioByDefault,
    biometricUnlockEnabled:
        biometricUnlockEnabled ?? this.biometricUnlockEnabled,
    biometricUnlockVaultBinding:
        identical(biometricUnlockVaultBinding, _unchanged)
        ? this.biometricUnlockVaultBinding
        : biometricUnlockVaultBinding as String?,
    themeMode: themeMode ?? this.themeMode,
    textScale: textScale == null
        ? this.textScale
        : textScale.clamp(minTextScale, maxTextScale),
  );

  Map<String, dynamic> toJson() => {
    'autoLockMinutes': autoLockMinutes,
    'lockOnBackground': lockOnBackground,
    'keepAudioByDefault': keepAudioByDefault,
    'biometricUnlockEnabled': biometricUnlockEnabled,
    'biometricUnlockVaultBinding': biometricUnlockVaultBinding,
    'themeMode': themeMode.name,
    'textScale': textScale,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    autoLockMinutes: (json['autoLockMinutes'] as int?) ?? 5,
    lockOnBackground: (json['lockOnBackground'] as bool?) ?? true,
    keepAudioByDefault: (json['keepAudioByDefault'] as bool?) ?? false,
    biometricUnlockEnabled: (json['biometricUnlockEnabled'] as bool?) ?? false,
    biometricUnlockVaultBinding: json['biometricUnlockVaultBinding'] as String?,
    themeMode: _themeModeFromName(json['themeMode'] as String?),
    textScale: ((json['textScale'] as num?)?.toDouble() ?? 1.0).clamp(
      minTextScale,
      maxTextScale,
    ),
  );

  static ThemeMode _themeModeFromName(String? name) {
    for (final mode in ThemeMode.values) {
      if (mode.name == name) return mode;
    }
    return ThemeMode.system;
  }
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
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
  }
}
