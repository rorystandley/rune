import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/state/app_settings.dart';

void main() {
  test('defaults: system theme, unscaled text', () {
    const s = AppSettings();
    expect(s.themeMode, ThemeMode.system);
    expect(s.textScale, 1.0);
  });

  test('themeMode and textScale round-trip through JSON', () {
    const s = AppSettings(themeMode: ThemeMode.dark, textScale: 1.25);
    final restored = AppSettings.fromJson(s.toJson());
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.textScale, 1.25);
  });

  test('fromJson tolerates a missing/unknown themeMode', () {
    expect(AppSettings.fromJson(const {}).themeMode, ThemeMode.system);
    expect(
      AppSettings.fromJson(const {'themeMode': 'chartreuse'}).themeMode,
      ThemeMode.system,
    );
  });

  test('textScale is clamped to the supported range', () {
    // Out-of-range values from a hand-edited/corrupt file are pulled back in.
    expect(
      AppSettings.fromJson(const {'textScale': 5.0}).textScale,
      AppSettings.maxTextScale,
    );
    expect(
      AppSettings.fromJson(const {'textScale': 0.1}).textScale,
      AppSettings.minTextScale,
    );
    // copyWith clamps too, so the UI can pass raw slider values safely.
    expect(
      const AppSettings().copyWith(textScale: 10).textScale,
      AppSettings.maxTextScale,
    );
  });

  test('copyWith leaves appearance fields untouched when omitted', () {
    const s = AppSettings(themeMode: ThemeMode.light, textScale: 1.15);
    final next = s.copyWith(autoLockMinutes: 15);
    expect(next.themeMode, ThemeMode.light);
    expect(next.textScale, 1.15);
  });
}
