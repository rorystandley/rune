import 'dart:convert';
import 'dart:typed_data';

import '../crypto/crypto_service.dart';
import '../crypto/kdf_params.dart';

/// The clear-text header for a vault, persisted as `vault.json`.
///
/// Everything here is intentionally NOT secret. It must be readable before a
/// passphrase is entered so the app knows how to derive the key. It contains:
///   - the KDF algorithm and cost parameters + salt,
///   - the AEAD cipher identifier,
///   - the *wrapped* (encrypted) data key.
///
/// It contains no note content and no key material that is usable without the
/// passphrase. See SECURITY.md for the full description of what this leaks.
class VaultMetadata {
  const VaultMetadata({
    required this.version,
    required this.createdAt,
    required this.kdfParams,
    required this.cipher,
    required this.wrappedKey,
  });

  static const String formatId = 'notes-vault';
  static const int currentVersion = 1;

  final int version;
  final DateTime createdAt;
  final KdfParams kdfParams;
  final VaultCipher cipher;

  /// The data key (DEK) encrypted under the KEK: `nonce || ciphertext || mac`.
  final Uint8List wrappedKey;

  Map<String, dynamic> toJson() => {
        'format': formatId,
        'version': version,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'kdf': kdfParams.toJson(),
        'cipher': cipher.id,
        'wrappedKeyB64': base64.encode(wrappedKey),
      };

  /// Pretty-printed so a curious user can read exactly what is stored.
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory VaultMetadata.fromJson(Map<String, dynamic> json) {
    final format = json['format'];
    if (format != formatId) {
      throw FormatException('Not a notes vault file (format=$format)');
    }
    final version = json['version'] as int;
    if (version > currentVersion) {
      throw FormatException(
          'Vault version $version is newer than this app supports ($currentVersion)');
    }
    return VaultMetadata(
      version: version,
      createdAt: DateTime.parse(json['createdAt'] as String),
      kdfParams: KdfParams.fromJson(json['kdf'] as Map<String, dynamic>),
      cipher: VaultCipher.fromId(json['cipher'] as String),
      wrappedKey:
          Uint8List.fromList(base64.decode(json['wrappedKeyB64'] as String)),
    );
  }

  factory VaultMetadata.decode(String jsonString) =>
      VaultMetadata.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
}
