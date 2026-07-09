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

4. **Biometric / OS-keystore unlock as an *option*.** Implemented: users can
   cache the vault DEK behind Face ID / Touch ID / Windows Hello via the
   platform credential store, without ever weakening the passphrase-only path.
   Strictly opt-in, then automatic on each locked session while enabled.

5. **Secure deletion & anti-forensics.** Best-effort secure-delete of note files
   and temp audio, scrub note caches more aggressively, and investigate
   `flutter_secure_screen`/FLAG_SECURE to block screenshots and app-switcher
   thumbnails of unlocked content.

6. **Encrypted attachments** (images, files, audio) using the same DEK +
   per-blob nonce scheme, stored as separate AEAD blobs — keeping the
   "only ciphertext on disk" invariant.

7. **Real on-device transcription on every target.** macOS, Android, and iOS
   now use whisper.cpp via FFI with a bundled quantized English model and an
   off-UI-isolate worker, verified transcribing real audio on hardware: macOS,
   a physical Android device (Galaxy A53), and a physical iPhone. Windows/Linux
   keep the stub by design. See `docs/transcription.md`.

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

## User-experience additions (in priority order)

The privacy work above is the point of the app; this is the daily-use polish that
makes people actually *want* to live in it. All ten are chosen to fit the calm,
low-chrome ethos and to respect the non-goals below — no WYSIWYG, no cloud, no
tracking. Effort is a rough T-shirt size for the client-side work.

1. **Pin to top.** Implemented: a `pinned` flag on the note model surfaces a
   "Pinned" section above the list, with the rest under a "Notes" header. Toggle
   from the editor toolbar (both layouts) or a long-press on any list row; pinned
   rows show a pin glyph. Pinning preserves the note's modified time. The
   highest-value organizing feature, and calmer than folders or tags. (Small.)

2. **Undo delete + Recently Deleted.** Implemented: a `deletedAt` flag soft-deletes
   notes instead of erasing them. Deleting from the editor now shows an "Undo"
   snackbar (no confirm dialog) and drops the note into a **Recently Deleted**
   view — reachable from a footer that appears in the list only when something is
   there. From there notes can be restored, deleted forever, or emptied; anything
   left is purged permanently after a 30-day window on the next unlock. The blob
   stays encrypted the whole time. A safety net matters *more* here because there
   is no cloud to recover from. (Medium.)

3. **Appearance controls.** In-app Light / Dark / System toggle and an adjustable
   text size (plus editor max-width on wide screens). Today the theme is whatever
   the OS decides and the font size is fixed; reading/writing comfort is the most
   common notes-app request. (Small.)

4. **Desktop keyboard shortcuts.** ⌘N new note, ⌘F focus search, ⌘⌫ delete, ⌘L
   lock, Esc to clear search. The two-pane layout already signals "desktop"; power
   users expect these. (Small.)

5. **Search that shows its work.** Highlight the matched substring in the title /
   preview and show a result count. Turns search from "did anything happen?" into
   a real tool. (Small.)

6. **Note info sheet.** Created / modified timestamps, word count, character count,
   and reading time in a tap-to-open sheet. The editor surfaces none of this today;
   writers love a word count. (Small.)

7. **Swipe actions in the list.** Swipe a row to pin or delete, with haptics — the
   standard mobile idiom, currently absent. (Small.)

8. **Markdown preview (read mode).** An optional, off-by-default toggle that renders
   headings / lists / links and tappable `- [ ]` checkboxes while the editor stays
   plain text. Keeps WYSIWYG out; checklists alone win a lot of users. (Medium.)

9. **Share & single-note export.** Native share sheet / "copy as text" for one note,
   plus single-note encrypted export — today it is all-or-nothing from Settings.
   Pairs with the file-picker / share-sheet work in item 8 above. (Medium.)

10. **Trustworthy first run.** A passphrase-strength meter on vault creation (zxcvbn,
    from item 10 above) and a warmer first-run empty state that reassures ("encrypted
    on this device — no account, no cloud") and points at voice notes. For a privacy
    app, vault creation *is* the trust moment. (Small–Medium.)

## Smaller follow-ups

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
