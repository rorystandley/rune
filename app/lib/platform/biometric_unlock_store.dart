import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class BiometricUnlockAvailability {
  const BiometricUnlockAvailability._({
    required this.isAvailable,
    required this.label,
    this.reason,
  });

  const BiometricUnlockAvailability.available(String label)
    : this._(isAvailable: true, label: label);

  const BiometricUnlockAvailability.unavailable(String reason)
    : this._(isAvailable: false, label: 'Biometric unlock', reason: reason);

  final bool isAvailable;
  final String label;
  final String? reason;
}

abstract class BiometricUnlockStore {
  Future<BiometricUnlockAvailability> checkAvailability();

  Future<void> saveCachedDek({
    required String vaultBinding,
    required Uint8List dek,
  });

  Future<Uint8List?> readCachedDek({required String vaultBinding});

  Future<void> clearCachedDek();
}

class DisabledBiometricUnlockStore implements BiometricUnlockStore {
  const DisabledBiometricUnlockStore();

  @override
  Future<BiometricUnlockAvailability> checkAvailability() async =>
      const BiometricUnlockAvailability.unavailable(
        'Biometric unlock is not available in this build.',
      );

  @override
  Future<void> clearCachedDek() async {}

  @override
  Future<Uint8List?> readCachedDek({required String vaultBinding}) async =>
      null;

  @override
  Future<void> saveCachedDek({
    required String vaultBinding,
    required Uint8List dek,
  }) async {}
}

class PlatformBiometricUnlockStore implements BiometricUnlockStore {
  PlatformBiometricUnlockStore({
    FlutterSecureStorage? storage,
    LocalAuthentication? auth,
    this.debugPlatform,
  }) : _storage = storage ?? _defaultStorage,
       _auth = auth ?? LocalAuthentication();

  static const String _cacheKey = 'rune.platform_unlock_cache.v1';

  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions.biometric(
      enforceBiometrics: true,
      biometricType: AndroidBiometricType.strongBiometricOnly,
      storageNamespace: 'rune_biometric_unlock',
      biometricPromptTitle: 'Unlock Rune',
      biometricPromptSubtitle: 'Use your biometric credential',
      biometricPromptNegativeButton: 'Use passphrase',
    ),
    iOptions: IOSOptions(
      accountName: 'rune-biometric-unlock',
      accessibility: KeychainAccessibility.unlocked_this_device,
      accessControlFlags: [AccessControlFlag.biometryCurrentSet],
      synchronizable: false,
      label: 'Rune vault unlock key',
      useSecureEnclave: true,
    ),
    mOptions: MacOsOptions(
      accountName: 'rune-biometric-unlock',
      accessibility: KeychainAccessibility.unlocked_this_device,
      accessControlFlags: [AccessControlFlag.biometryCurrentSet],
      synchronizable: false,
      label: 'Rune vault unlock key',
      usesDataProtectionKeychain: true,
      useSecureEnclave: true,
    ),
    wOptions: WindowsOptions(),
  );

  final FlutterSecureStorage _storage;
  final LocalAuthentication _auth;
  final TargetPlatform? debugPlatform;

  TargetPlatform get _platform => debugPlatform ?? defaultTargetPlatform;

  @override
  Future<BiometricUnlockAvailability> checkAvailability() async {
    if (kIsWeb) {
      return const BiometricUnlockAvailability.unavailable(
        'Biometric unlock is not available on web.',
      );
    }

    try {
      return switch (_platform) {
        TargetPlatform.android => await _mobileBiometricAvailability(
          label: 'Biometric unlock',
          requireStrong: true,
        ),
        TargetPlatform.iOS => await _mobileBiometricAvailability(
          label: 'Face ID / Touch ID',
        ),
        TargetPlatform.macOS => await _mobileBiometricAvailability(
          label: 'Touch ID',
        ),
        TargetPlatform.windows => await _windowsHelloAvailability(),
        TargetPlatform.linux ||
        TargetPlatform.fuchsia => const BiometricUnlockAvailability.unavailable(
          'This platform does not provide a supported biometric keystore.',
        ),
      };
    } catch (_) {
      return const BiometricUnlockAvailability.unavailable(
        'Biometric unlock is not configured on this device.',
      );
    }
  }

  @override
  Future<void> saveCachedDek({
    required String vaultBinding,
    required Uint8List dek,
  }) async {
    await _authenticateWindowsHelloIfNeeded();
    final payload = <String, Object?>{
      'version': 1,
      'vaultBinding': vaultBinding,
      'dekB64': base64Encode(dek),
    };
    await _storage.write(key: _cacheKey, value: jsonEncode(payload));
  }

  @override
  Future<Uint8List?> readCachedDek({required String vaultBinding}) async {
    await _authenticateWindowsHelloIfNeeded();
    final encoded = await _storage.read(key: _cacheKey);
    if (encoded == null) return null;

    try {
      final payload = jsonDecode(encoded) as Map<String, dynamic>;
      if (payload['version'] != 1 ||
          (payload['vaultBinding'] as String?) != vaultBinding) {
        return null;
      }
      final bytes = base64Decode(payload['dekB64'] as String);
      return Uint8List.fromList(bytes);
    } on FormatException {
      await clearCachedDek();
      return null;
    } on TypeError {
      await clearCachedDek();
      return null;
    }
  }

  @override
  Future<void> clearCachedDek() => _storage.delete(key: _cacheKey);

  Future<BiometricUnlockAvailability> _mobileBiometricAvailability({
    required String label,
    bool requireStrong = false,
  }) async {
    final canCheck = await _auth.canCheckBiometrics;
    final enrolled = await _auth.getAvailableBiometrics();
    if (!canCheck || enrolled.isEmpty) {
      return const BiometricUnlockAvailability.unavailable(
        'No biometric credential is enrolled on this device.',
      );
    }
    if (requireStrong && enrolled.every((type) => type == BiometricType.weak)) {
      return const BiometricUnlockAvailability.unavailable(
        'A strong biometric credential is required on Android.',
      );
    }
    return BiometricUnlockAvailability.available(label);
  }

  Future<BiometricUnlockAvailability> _windowsHelloAvailability() async {
    final supported = await _auth.isDeviceSupported();
    if (!supported) {
      return const BiometricUnlockAvailability.unavailable(
        'Windows Hello is not configured on this device.',
      );
    }
    return const BiometricUnlockAvailability.available('Windows Hello');
  }

  Future<void> _authenticateWindowsHelloIfNeeded() async {
    if (_platform != TargetPlatform.windows) return;
    final ok = await _auth.authenticate(
      localizedReason: 'Use Windows Hello to unlock Rune.',
      persistAcrossBackgrounding: true,
    );
    if (!ok) {
      throw const BiometricUnlockException('Windows Hello was canceled.');
    }
  }
}

class BiometricUnlockException implements Exception {
  const BiometricUnlockException(this.message);

  final String message;

  @override
  String toString() => message;
}
