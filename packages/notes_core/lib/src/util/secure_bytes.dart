import 'dart:typed_data';

/// Overwrites [bytes] with zeros in place.
///
/// Used to wipe key material (KEK/DEK buffers) after use. This is a best-effort
/// measure: see SECURITY.md for the limits of memory wiping on managed
/// runtimes. Centralised so every path zeroes secrets the same, audited way.
void zeroBytes(Uint8List bytes) {
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = 0;
  }
}
