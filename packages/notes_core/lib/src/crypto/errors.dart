/// Domain exceptions for the notes vault.
///
/// IMPORTANT: none of these messages ever contain secret material — no
/// passphrases, keys, or note content. They are safe to log and to surface in
/// the UI.
class VaultException implements Exception {
  const VaultException(this.message);
  final String message;

  @override
  String toString() => 'VaultException: $message';
}

/// Thrown when unwrapping the data key fails authentication, which means the
/// passphrase was wrong (or the metadata was tampered with).
class WrongPassphraseException extends VaultException {
  const WrongPassphraseException()
      : super('Incorrect passphrase, or the vault data has been tampered with.');
}

/// Thrown when an encrypted record fails authentication during decryption.
class DecryptionFailedException extends VaultException {
  const DecryptionFailedException([String? what])
      : super('Failed to decrypt ${what ?? 'data'}: authentication failed.');
}

/// Thrown when creating a vault where one already exists.
class VaultAlreadyExistsException extends VaultException {
  const VaultAlreadyExistsException()
      : super('A vault already exists at this location.');
}

/// Thrown when unlocking/reading a vault that does not exist.
class VaultNotFoundException extends VaultException {
  const VaultNotFoundException()
      : super('No vault exists at this location.');
}

/// Thrown when an operation requires an unlocked vault but it is locked.
class VaultLockedException extends VaultException {
  const VaultLockedException() : super('The vault is locked.');
}

/// Thrown when a plaintext export is attempted without explicit confirmation.
class PlaintextExportNotConfirmedException extends VaultException {
  const PlaintextExportNotConfirmedException()
      : super('Plaintext export requires explicit confirmation.');
}

/// Thrown when a vault uses a format/version/cipher this build does not support.
class UnsupportedVaultException extends VaultException {
  const UnsupportedVaultException(super.message);
}
