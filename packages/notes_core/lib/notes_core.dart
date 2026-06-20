/// notes_core — a pure-Dart, local-first, encrypted notes engine.
///
/// Contains all crypto, storage, and note logic. It has **no** dependency on
/// Flutter, makes **no** network calls, and does **no** logging of secrets.
/// The Flutter app is a thin UI layer over this package.
library;

export 'src/crypto/crypto_service.dart';
export 'src/crypto/errors.dart';
export 'src/crypto/kdf_params.dart';
export 'src/models/note.dart';
export 'src/models/vault_metadata.dart';
export 'src/services/export_service.dart';
export 'src/services/notes_repository.dart';
export 'src/services/vault_service.dart';
export 'src/storage/file_vault_store.dart';
export 'src/storage/vault_store.dart';
export 'src/transcription/stub_transcription_service.dart';
export 'src/transcription/transcription_service.dart';
export 'src/util/redaction.dart';
