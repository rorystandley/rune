# Changelog

All notable changes to Rune are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.3.0] - 2026-06-29

### Added
- Optional biometric / OS unlock: users can opt in to cache the vault DEK behind
  Face ID, Touch ID, Android strong biometrics, or Windows Hello without storing
  the passphrase or changing the passphrase-only unlock path. Once enabled, the
  OS authentication prompt starts automatically on each locked session.

### Fixed
- macOS biometric setup now includes the Keychain Sharing entitlement and
  development signing required to store the Touch ID-protected vault key.
- Windows and Linux release builds now compile with the biometric unlock code.

## [0.2.0] - 2026-06-25

### Added
- **Real on-device speech-to-text** via whisper.cpp on **macOS, Android, and
  iOS** — voice notes are transcribed entirely on the device, with no network,
  using a bundled quantized English model. Verified transcribing real audio on
  a physical Android device and a physical iPhone. Windows and Linux keep a
  clearly-labelled stub until their native builds land.
- whisper.cpp is vendored as a pinned git submodule and built from source for
  each platform; the Android release APK stays byte-reproducible.

### Changed
- The microphone button **inside a note** now appends the transcription to the
  open note instead of creating a new one. The home/list microphone still
  creates a new voice note.

### Fixed
- Recordings using the `WAVE_FORMAT_EXTENSIBLE` WAV header (e.g. on macOS) now
  decode correctly instead of failing transcription.
- iOS release builds no longer silently fall back to the transcription stub
  (the native FFI symbols were being removed by the linker's dead-strip).

## [0.1.0] - 2026-06-24

First public build (MVP): encrypted local-first notes (Argon2id +
XChaCha20-Poly1305, only ciphertext at rest), create/edit/search/delete with
autosave, auto-lock and lock-on-background, encrypted backup export (plaintext
export behind an explicit warning), and local voice-note recording. Fully
offline — no network, no telemetry, no accounts. On-device transcription
shipped as a clearly-labelled stub. Not yet audited.

[Unreleased]: https://github.com/rorystandley/rune/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/rorystandley/rune/releases/tag/v0.3.0
[0.2.0]: https://github.com/rorystandley/rune/releases/tag/v0.2.0
[0.1.0]: https://github.com/rorystandley/rune/releases/tag/v0.1.0
