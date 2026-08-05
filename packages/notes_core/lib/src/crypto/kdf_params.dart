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

  /// Upper bounds on the cost parameters, used to reject abusive values that
  /// arrive in an *untrusted* header (e.g. an imported backup). Without a cap, a
  /// crafted `memoryKiB` of, say, 64 GiB would make Argon2id try to allocate
  /// that much and take the app down when the header is used to derive a key.
  /// The ceilings sit far above any sane production setting (default is 64 MiB /
  /// 3 passes) so they never reject a legitimately-configured vault.
  static const int maxMemoryKiB = 1 << 20; // 1 GiB
  static const int maxIterations = 4096;
  static const int maxParallelism = 255;

  /// Throws [FormatException] if any cost parameter is out of the supported
  /// range. Call this on parameters parsed from untrusted input before handing
  /// them to the KDF. Bounds are inclusive.
  void validateCost() {
    if (memoryKiB < 8 || memoryKiB > maxMemoryKiB) {
      throw FormatException(
          'Argon2id memory cost out of range: $memoryKiB KiB');
    }
    if (iterations < 1 || iterations > maxIterations) {
      throw FormatException('Argon2id iterations out of range: $iterations');
    }
    if (parallelism < 1 || parallelism > maxParallelism) {
      throw FormatException('Argon2id parallelism out of range: $parallelism');
    }
  }

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
