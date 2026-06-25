# Testing

The point of these tests is to back the security claims with something runnable,
not just prose. They favour the crypto/storage/notes logic — the parts that, if
wrong, would quietly betray the user.

## How to run

```bash
# 1) Core security + logic tests — pure Dart, no device/emulator needed
cd packages/notes_core
dart pub get
dart test

# 2) App state-machine + widget tests
cd ../../app
flutter pub get
flutter test
```

Static analysis (lint + type checks), run in both packages:

```bash
dart analyze        # in packages/notes_core
flutter analyze     # in app
```

Both are expected to report **no issues**.

## What's covered

### `packages/notes_core/test/` (pure Dart)

**`crypto_service_test.dart`** — the cryptographic core:
- XChaCha20-Poly1305 is the default cipher.
- Secure random bytes have the right length and vary.
- Argon2id is deterministic for the same passphrase+salt, and differs for a
  different passphrase or a different salt.
- `seal`/`open` round-trip; a fresh nonce is used each call (same plaintext →
  different ciphertext).
- **Wrong key → `DecryptionFailedException`.**
- **Tampered ciphertext fails authentication** (flipped MAC byte is rejected).
- DEK wrap/unwrap round-trips; **unwrap with the wrong KEK →
  `WrongPassphraseException`**.
- AES-256-GCM also round-trips (alternative cipher works).

**`vault_service_test.dart`** — the vault lifecycle:
- Fresh state: no vault, locked.
- `createVault` creates and unlocks; writing metadata is persisted.
- Creating over an existing vault throws.
- Unlock with the correct passphrase succeeds; **unlock with the wrong
  passphrase throws and stays locked**.
- A brand-new service instance can unlock an existing vault (real persistence).
- `sealNote`/`openNote` round-trip while unlocked; throw `VaultLockedException`
  when locked.
- **Change passphrase**: the old one stops working, the new one works, a wrong
  current passphrase is rejected, and existing notes stay decryptable.
- The **production-default Argon2id parameters** (64 MiB / 3 passes) work
  end-to-end.

**`notes_repository_test.dart`** — notes CRUD & search:
- Starts empty; create/get; update changes content and `updatedAt`; delete
  removes the note **and its file**.
- List is sorted newest-first.
- Search matches title and body, case-insensitively; empty query returns all.
- **Notes persist and decrypt after lock + reopen** with fresh objects.

**`export_service_test.dart`** — export behaviour:
- Encrypted backup **contains no plaintext** (note title/body absent from the
  file bytes).
- Encrypted backup carries the vault header + encrypted notes (restorable).
- **Plaintext export without confirmation throws and writes nothing.**
- Plaintext export *with* confirmation writes readable Markdown.

**`logging_and_at_rest_test.dart`** — the "don't betray the user" tests:
- A full create/edit/search/lock/unlock cycle with `print` intercepted asserts
  the **passphrase and note body never appear in output** (no secret logging).
- **Encryption at rest:** `vault.json` and every `.note` file are scanned and
  asserted to contain **no plaintext** passphrase, title, or body.

### `app/test/` (Flutter)

**`app_controller_test.dart`** — the app state machine over the real core:
- First launch → `needsCreation`.
- `createVault` → `unlocked`.
- Create / save / search / delete a note through the controller.
- Lock; **wrong passphrase rejected (stays locked, sets error)**; correct
  passphrase unlocks and reloads notes.
- Encrypted backup export contains no plaintext.
- Plaintext export requires confirmation.

**`widget_test.dart`** — UI smoke + integration:
- First launch renders the **create-vault screen with the irreversibility
  warning**.
- After creating a vault (real crypto + storage), the notes UI renders with the
  new-note and lock controls and the created note visible.

## Test design notes

- Tests inject a temporary directory as the vault location, so they touch only
  scratch space and clean up afterwards. The UI tests inject the storage
  directory and an `UnavailableAudioRecorder`, so they need **no** `path_provider`
  or microphone plugin.
- Tests use **cheap Argon2id parameters** (256 KiB / 1 pass) for speed, except
  one test that exercises the real production parameters end-to-end.
- Recording is not unit-tested because it requires a device microphone. The
  transcription seam is unit-tested for WAV decoding and local-engine behavior,
  while real whisper.cpp inference is covered by an opt-in skipped integration
  test because it needs the native library and model.

## Not yet tested (honest gaps)

- The voice-note bottom sheet UI (depends on a real recorder).
- Real whisper.cpp transcription in the default CI run; it is available as an
  opt-in integration test, see `docs/transcription.md`.
- Per-platform file-permission behaviour of the vault directory.
- Fuzzing of the `vault.json` / backup parsers (on the roadmap).
