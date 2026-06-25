# Roadmap

The MVP is deliberately boring and small. This is the path from "works and is
honestly private" to "would survive scrutiny on r/privacy".

## The next 10 improvements (in priority order)

1. **Independent crypto review + reproducible builds.** The single most valuable
   thing. Get the ~250-line crypto core reviewed, publish the threat model, and
   ship reproducible, signed builds so users can verify the binary matches the
   source. Privacy claims are worthless without verifiability.

2. **Native crypto acceleration on mobile** via `cryptography_flutter`, and raise
   Argon2id cost to a calibrated target (e.g. tune to ~750 ms on the actual
   device at first run). Faster unlock lets us afford stronger KDF parameters.

3. **Metadata hardening.** Pad note ciphertext to size buckets so file sizes stop
   approximating note lengths; consider a single packed encrypted store (or
   per-note random size jitter) so the file count stops revealing how many notes
   exist. Document the residual leakage that remains.

4. **Biometric / OS-keystore unlock as an *option*.** Let users cache the wrapped
   key behind Face ID / Touch ID / Windows Hello via the platform secure
   enclave, without ever weakening the passphrase-only path. Strictly opt-in.

5. **Secure deletion & anti-forensics.** Best-effort secure-delete of note files
   and temp audio, scrub note caches more aggressively, and investigate
   `flutter_secure_screen`/FLAG_SECURE to block screenshots and app-switcher
   thumbnails of unlocked content.

6. **Encrypted attachments** (images, files, audio) using the same DEK +
   per-blob nonce scheme, stored as separate AEAD blobs — keeping the
   "only ciphertext on disk" invariant.

7. **Real on-device transcription on every target.** macOS and Android now use
   whisper.cpp via FFI with a bundled quantized English model and an
   off-UI-isolate worker; Android is still pending physical-device verification.
   iOS still needs its native build/linking PR, and Windows/Linux keep the stub
   by design. See `docs/transcription.md`.

8. **Native file picker / share sheet for exports** (`file_picker`,
   `share_plus`) so users choose where backups go, plus **encrypted-backup
   import/restore** (the backup format already carries everything needed).

9. **Optional end-to-end encrypted sync**, off by default, zero-knowledge
   (server stores only ciphertext + wrapped keys). This is where most "private"
   apps quietly betray users — so it must be opt-in, auditable, and never a
   requirement. Likely via a user-supplied WebDAV/S3 or a self-hostable relay.

10. **Hardening polish for distribution:** dependency pinning + SBOM, supply-chain
    review of `record`/`path_provider`, fuzzing the vault/backup parsers,
    property-based crypto tests, a passphrase-strength meter (zxcvbn), and a
    written incident/key-rotation story.

## Smaller follow-ups

- Soft-delete / "Recently deleted" with a purge window.
- Markdown preview toggle (kept optional; the editor stays plain by default).
- Tags or folders (only if they don't complicate the calm UX).
- Configurable Argon2id presets (interactive / sensitive) in settings.
- Localization / RTL.
- Per-note "lock individually" for extra-sensitive notes.

## Explicit non-goals (kept out on purpose)

- Rich-text/WYSIWYG complexity.
- Real-time collaboration / social / sharing features.
- Remote/cloud AI of any kind.
- Mandatory accounts or cloud.
- Ads, telemetry, analytics, tracking — ever.
