import 'dart:convert';
import 'dart:typed_data';

/// Parameters for the Argon2id key-derivation function.
///
/// These are stored *in clear* inside `vault.json`. They are not secret: the
/// salt only needs to be unique (not hidden), and the cost parameters must be
/// known to derive the same key on unlock. Storing them per-vault means the
/// cost can be raised for newly created vaults without breaking existing ones.
class KdfParams {
  const KdfParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    required this.salt,
  });

  /// Memory cost in kibibytes (KiB).
  final int memoryKiB;

  /// Number of passes over memory.
  final int iterations;

  /// Lanes / degree of parallelism.
  final int parallelism;

  /// Random per-vault salt. 16 bytes is the recommended minimum.
  final Uint8List salt;

  /// Production defaults for interactive unlock. 64 MiB / 3 passes lands around
  /// half a second with the pure-Dart implementation on a modern laptop, and is
  /// far faster with native acceleration (see SECURITY.md). Comfortably above
  /// the OWASP Argon2id minimum (19 MiB, 2 passes).
  static const int defaultMemoryKiB = 65536; // 64 MiB
  static const int defaultIterations = 3;
  static const int defaultParallelism = 1;
  static const int saltLength = 16;

  Map<String, dynamic> toJson() => {
        'algorithm': 'argon2id',
        'memoryKiB': memoryKiB,
        'iterations': iterations,
        'parallelism': parallelism,
        'saltB64': base64.encode(salt),
      };

  factory KdfParams.fromJson(Map<String, dynamic> json) {
    final algo = json['algorithm'];
    if (algo != 'argon2id') {
      throw FormatException('Unsupported KDF algorithm: $algo');
    }
    return KdfParams(
      memoryKiB: json['memoryKiB'] as int,
      iterations: json['iterations'] as int,
      parallelism: json['parallelism'] as int,
      salt: Uint8List.fromList(base64.decode(json['saltB64'] as String)),
    );
  }
}
