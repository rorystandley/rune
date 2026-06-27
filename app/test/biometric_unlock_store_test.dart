import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:notes_app/platform/biometric_unlock_store.dart';

void main() {
  group('platform availability', () {
    test('Android accepts an enrolled strong biometric', () async {
      final auth = FakeLocalAuthentication(
        canCheckBiometricsResult: true,
        enrolledBiometrics: const [BiometricType.weak, BiometricType.strong],
      );
      final store = buildStore(TargetPlatform.android, auth: auth);

      final availability = await store.checkAvailability();

      expect(availability.isAvailable, isTrue);
      expect(availability.label, 'Biometric unlock');
    });

    test('Android rejects weak-only biometrics', () async {
      final auth = FakeLocalAuthentication(
        canCheckBiometricsResult: true,
        enrolledBiometrics: const [BiometricType.weak],
      );
      final store = buildStore(TargetPlatform.android, auth: auth);

      final availability = await store.checkAvailability();

      expect(availability.isAvailable, isFalse);
      expect(
        availability.reason,
        'A strong biometric credential is required on Android.',
      );
    });

    test('Android rejects devices without an enrolled biometric', () async {
      final auth = FakeLocalAuthentication(
        canCheckBiometricsResult: true,
        enrolledBiometrics: const [],
      );
      final store = buildStore(TargetPlatform.android, auth: auth);

      final availability = await store.checkAvailability();

      expect(availability.isAvailable, isFalse);
      expect(
        availability.reason,
        'No biometric credential is enrolled on this device.',
      );
    });

    test('Windows requires Windows Hello to be configured', () async {
      final auth = FakeLocalAuthentication(isDeviceSupportedResult: false);
      final store = buildStore(TargetPlatform.windows, auth: auth);

      final availability = await store.checkAvailability();

      expect(availability.isAvailable, isFalse);
      expect(
        availability.reason,
        'Windows Hello is not configured on this device.',
      );
    });

    test('Windows reports Windows Hello when configured', () async {
      final auth = FakeLocalAuthentication(isDeviceSupportedResult: true);
      final store = buildStore(TargetPlatform.windows, auth: auth);

      final availability = await store.checkAvailability();

      expect(availability.isAvailable, isTrue);
      expect(availability.label, 'Windows Hello');
    });

    test('Linux fails closed without querying platform plugins', () async {
      final events = <String>[];
      final store = buildStore(
        TargetPlatform.linux,
        auth: FakeLocalAuthentication(events: events),
        storage: FakeSecureStorage(events: events),
      );

      final availability = await store.checkAvailability();

      expect(availability.isAvailable, isFalse);
      expect(
        availability.reason,
        'This platform does not provide a supported biometric keystore.',
      );
      expect(events, isEmpty);
    });

    test('plugin errors are reported as unavailable', () async {
      final auth = FakeLocalAuthentication(
        canCheckError: StateError('plugin unavailable'),
      );
      final store = buildStore(TargetPlatform.android, auth: auth);

      final availability = await store.checkAvailability();

      expect(availability.isAvailable, isFalse);
      expect(
        availability.reason,
        'Biometric unlock is not configured on this device.',
      );
    });
  });

  group('platform credential access', () {
    test('Windows authenticates before writing the cached DEK', () async {
      final events = <String>[];
      final storage = FakeSecureStorage(events: events);
      final auth = FakeLocalAuthentication(
        authenticateResult: true,
        events: events,
      );
      final store = buildStore(
        TargetPlatform.windows,
        auth: auth,
        storage: storage,
      );

      await store.saveCachedDek(
        vaultBinding: 'vault-a',
        dek: Uint8List.fromList([1, 2, 3]),
      );

      expect(events, ['authenticate', 'write']);
      expect(storage.values, hasLength(1));
    });

    test('Windows cancellation prevents a cached DEK write', () async {
      final events = <String>[];
      final storage = FakeSecureStorage(events: events);
      final store = buildStore(
        TargetPlatform.windows,
        auth: FakeLocalAuthentication(
          authenticateResult: false,
          events: events,
        ),
        storage: storage,
      );

      await expectLater(
        store.saveCachedDek(
          vaultBinding: 'vault-a',
          dek: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(isA<BiometricUnlockException>()),
      );

      expect(events, ['authenticate']);
      expect(storage.values, isEmpty);
    });

    test('Windows authenticates before reading the cached DEK', () async {
      final events = <String>[];
      final storage = FakeSecureStorage(events: events);
      final auth = FakeLocalAuthentication(
        authenticateResult: true,
        events: events,
      );
      final store = buildStore(
        TargetPlatform.windows,
        auth: auth,
        storage: storage,
      );
      await store.saveCachedDek(
        vaultBinding: 'vault-a',
        dek: Uint8List.fromList([1, 2, 3]),
      );
      events.clear();

      final dek = await store.readCachedDek(vaultBinding: 'vault-a');

      expect(events, ['authenticate', 'read']);
      expect(dek, [1, 2, 3]);
    });

    test('a cache bound to another vault is not returned', () async {
      final storage = FakeSecureStorage();
      final store = buildStore(TargetPlatform.android, storage: storage);
      await store.saveCachedDek(
        vaultBinding: 'vault-a',
        dek: Uint8List.fromList([1, 2, 3]),
      );

      final dek = await store.readCachedDek(vaultBinding: 'vault-b');

      expect(dek, isNull);
    });

    test('malformed cache data is deleted', () async {
      final events = <String>[];
      final storage = FakeSecureStorage(events: events)
        ..values['rune.platform_unlock_cache.v1'] = 'not-json';
      final store = buildStore(TargetPlatform.android, storage: storage);

      final dek = await store.readCachedDek(vaultBinding: 'vault-a');

      expect(dek, isNull);
      expect(events, ['read', 'delete']);
      expect(storage.values, isEmpty);
    });

    test('non-Windows storage relies on the keystore authentication', () async {
      final events = <String>[];
      final store = buildStore(
        TargetPlatform.android,
        auth: FakeLocalAuthentication(events: events),
        storage: FakeSecureStorage(events: events),
      );

      await store.saveCachedDek(
        vaultBinding: 'vault-a',
        dek: Uint8List.fromList([1, 2, 3]),
      );

      expect(events, ['write']);
    });
  });
}

PlatformBiometricUnlockStore buildStore(
  TargetPlatform platform, {
  FakeLocalAuthentication? auth,
  FakeSecureStorage? storage,
}) => PlatformBiometricUnlockStore(
  debugPlatform: platform,
  auth: auth ?? FakeLocalAuthentication(),
  storage: storage ?? FakeSecureStorage(),
);

class FakeLocalAuthentication extends LocalAuthentication {
  FakeLocalAuthentication({
    this.canCheckBiometricsResult = false,
    this.enrolledBiometrics = const [],
    this.isDeviceSupportedResult = false,
    this.authenticateResult = false,
    this.canCheckError,
    this.events,
  });

  final bool canCheckBiometricsResult;
  final List<BiometricType> enrolledBiometrics;
  final bool isDeviceSupportedResult;
  final bool authenticateResult;
  final Object? canCheckError;
  final List<String>? events;

  @override
  Future<bool> get canCheckBiometrics async {
    events?.add('canCheckBiometrics');
    if (canCheckError case final error?) throw error;
    return canCheckBiometricsResult;
  }

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async {
    events?.add('getAvailableBiometrics');
    return enrolledBiometrics;
  }

  @override
  Future<bool> isDeviceSupported() async {
    events?.add('isDeviceSupported');
    return isDeviceSupportedResult;
  }

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object> authMessages = const <Object>[],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    events?.add('authenticate');
    return authenticateResult;
  }
}

class FakeSecureStorage extends FlutterSecureStorage {
  FakeSecureStorage({this.events});

  final Map<String, String> values = {};
  final List<String>? events;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    events?.add('write');
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    events?.add('read');
    return values[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    events?.add('delete');
    values.remove(key);
  }
}
