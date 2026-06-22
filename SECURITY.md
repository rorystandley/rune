# Security

This document describes what the app does cryptographically, what it protects
against, and — just as importantly — **what it does not protect against**. It is
written to be checkable. If something here is wrong or overstated, treat that as
a bug.

> This is an MVP. The cryptographic design uses standard primitives via a
> well-known library, but **the code has not been independently audited**. Do
> not rely on it for life-or-death secrets yet.

---

## Cryptographic design

### Primitives (no custom crypto)

| Purpose | Algorithm | Source |
|--------|-----------|--------|
| Key derivation | **Argon2id** | `cryptography` package |
| Authenticated encryption | **XChaCha20-Poly1305** (default) or AES-256-GCM | `cryptography` package |
| Randomness | `Random.secure()` (platform CSPRNG) for salts, nonces, keys | Dart SDK |

We do not implement any primitive ourselves. All crypto goes through one small,
auditable file: `packages/notes_core/lib/src/crypto/crypto_service.dart`.

### Key hierarchy (envelope encryption)

1. On vault creation, a random 16-byte **salt** and a random 32-byte
   **data-encryption key (DEK)** are generated with the platform CSPRNG.
2. The passphrase is stretched with **Argon2id** (default: 64 MiB memory,
   3 iterations, 1 lane, 32-byte output) using that salt, producing a
   **key-encryption key (KEK)**.
3. The DEK is encrypted ("wrapped") under the KEK with the AEAD cipher and
   stored as the `wrappedKey` in `vault.json`.
4. Each note's JSON is encrypted under the **DEK** with a fresh random nonce.

**Unlock** re-derives the KEK from the passphrase + stored salt and decrypts the
wrapped DEK. If the passphrase is wrong, the KEK is wrong, the Poly1305/GCM
authentication tag fails, and unlock is rejected with `WrongPassphraseException`.
There is no separate "password check" value to attack — authentication *is* the
check.

### Why this design

- **XChaCha20-Poly1305** uses a 192-bit nonce, so random per-message nonces have
  negligible collision risk without a counter — robust and simple. AES-256-GCM
  is available as an alternative for hardware-accelerated environments.
- **Argon2id** is the current recommendation for passphrase hashing (memory-hard,
  resistant to GPU/ASIC attack). Parameters are stored per-vault so they can be
  raised for new vaults without breaking old ones.
- **Envelope encryption** means changing the passphrase re-wraps a 32-byte key
  instead of re-encrypting every note, and lays groundwork for future
  multi-recipient or key-rotation features.

### Argon2id parameters

Default: **memory = 64 MiB, iterations = 3, parallelism = 1, hash = 32 bytes**.
This exceeds the OWASP Argon2id minimum (19 MiB / 2 passes). It lands around
~0.5 s on a modern laptop with the pure-Dart implementation; on slower phones it
will be higher (see *Performance & native acceleration* below). Parameters live
in `vault.json` and are read back at unlock, so they are forward-compatible.

---

## Threat model

### What this app protects against

- **Device-at-rest / "stolen laptop or phone" (while locked).** With the app
  locked or closed, note content on disk is ciphertext under a key that exists
  only as a passphrase in the owner's head. Without the passphrase, the files
  are AEAD ciphertext + a salted Argon2id-wrapped key.
- **Casual disk inspection / backup leakage of content.** Anyone reading the
  vault directory, a file-level backup, or the encrypted export sees no note
  text, titles, or bodies — only ciphertext and non-secret KDF parameters.
- **Tampering with stored notes.** AEAD (Poly1305/GCM) authentication means a
  modified ciphertext fails to decrypt rather than yielding altered plaintext.
- **Network exposure.** There is no networking code; nothing can be exfiltrated
  over a network by the app because the app opens no sockets.
- **Wrong-passphrase access.** Proven by test: a wrong passphrase cannot decrypt
  the vault.

### What this app does NOT protect against

Be clear-eyed about these:

- **A forgotten passphrase.** There is no recovery, no backdoor, no reset. Lose
  the passphrase → lose the notes. This is by design.
- **A compromised device while unlocked.** If malware, a malicious OS, or
  someone with your unlocked session is present, the DEK and decrypted notes are
  in memory and readable. Encryption at rest cannot save you from an attacker
  who is already inside the running process.
- **A weak passphrase.** Argon2id raises the cost per guess, but a short or
  common passphrase can still be brute-forced offline if someone has your vault
  files. Use a strong, unique passphrase.
- **Keyloggers / hardware implants / shoulder-surfing.** Out of scope.
- **Cold-boot / RAM forensics.** Keys live in RAM while unlocked; a determined
  physical attacker with the right tools may recover them (see memory note).
- **OS-level or filesystem metadata.** File counts, sizes, and timestamps are
  visible to anyone who can read the directory (see below).
- **Platform OS backups copying plaintext exports.** If *you* run a plaintext
  export, those files are unprotected and may be swept into iCloud/OneDrive/etc.
- **Screenshots, OS clipboard, accessibility scraping, swap/paging of process
  memory.** Out of scope for the MVP.
- **Supply-chain trust.** You are trusting Flutter, Dart, the `cryptography`
  package, and the `record` package. Pin and review them for high-assurance use.
  For the released binaries, each download carries verifiable provenance — SLSA
  build-provenance attestations and a keyless cosign signature over `SHA256SUMS`
  — so you can confirm a build came from this repo's CI before trusting it. See
  [Verifying a release](RELEASE.md#verifying-a-release).

### What metadata leaks

The vault is encrypted for *content*, not for *shape*. Anyone with read access
to the vault directory can observe:

| Visible | Why | Mitigation status |
|---------|-----|-------------------|
| Number of notes | one file per note | Not mitigated (roadmap) |
| Approximate size of each note | ciphertext length ≈ plaintext length | Not mitigated; size padding is on the roadmap |
| Creation/modification times | filesystem timestamps + note `createdAt`/`updatedAt` inside ciphertext | File times not mitigated; in-content times are encrypted |
| That this is a "notes vault" | `vault.json` `format` field, directory name | Intentional, non-secret |
| KDF parameters and salt | stored in clear in `vault.json` (must be, to derive the key) | Non-secret by design |

Note **titles, bodies, and the random note ids reveal nothing** — filenames are
random 128-bit ids, not derived from content.

---

## Secrets handling

- **Never logged.** `notes_core` performs no logging at all; there is a test
  (`logging_and_at_rest_test.dart`) that runs a full create/edit/search/unlock
  cycle with `print` intercepted and asserts the passphrase and note body never
  appear in output. The UI layer logs nothing sensitive.
- **Never persisted in the clear.** Decrypted notes exist only in memory
  (`NotesRepository`) while unlocked and are dropped on lock. The only way
  plaintext touches disk is the explicit, confirmation-gated plaintext export.
- **Clipboard.** The app does not copy note content or passphrases to the
  clipboard. (File *paths* shown after export are user-selectable text, which the
  user may copy deliberately.)

### Memory wiping — honest limitations

On lock and after key use, byte buffers holding the KEK/DEK are explicitly
overwritten with zeros. **However:**

- The passphrase arrives from the UI as a Dart `String`, which is **immutable**
  and **cannot be reliably wiped**. Copies may persist in memory until garbage
  collected.
- Dart/Flutter is a managed runtime with a moving/garbage-collected heap. We
  cannot guarantee that no copy of a key or plaintext lingers in RAM, swap, or a
  freed-but-not-overwritten buffer.

So: zeroing is **best-effort defence in depth, not a guarantee.** We do not claim
the app is safe against an attacker who can read process memory.

---

## Auto-lock & lock-on-background

- The app **starts locked** whenever a vault already exists.
- **Manual lock** is always available.
- **Auto-lock** triggers after a configurable inactivity period (default 5 min;
  can be disabled). Pointer activity resets the timer.
- **Lock-on-background** (default on) locks when the app is paused/hidden, so the
  OS app switcher and a backgrounded app don't expose notes.

Locking zeroes the in-memory keys (best effort) and clears decrypted notes.

---

## Performance & native acceleration

The pure-Dart `cryptography` implementation runs everywhere with no native
dependency, which is why the tests are so portable. On mobile, Argon2id at
64 MiB can take longer than on a laptop. For production mobile builds, add
[`cryptography_flutter`](https://pub.dev/packages/cryptography_flutter) to use
the platform's native AES/ChaCha/Argon2 where available — same APIs, faster
unlock. This is intentionally left out of the MVP to keep the build and the web
target simple.

---

## Reporting a vulnerability

If you find a cryptographic mistake, a place where a claim in this document is
not actually true of the code, or any other security issue, please report it
**privately first** — do not open a public issue for an exploitable flaw.

**Preferred channel: GitHub private vulnerability reporting.** Go to the
[Security tab](https://github.com/rorystandley/rune/security/advisories) and
click **Report a vulnerability**, or use the **Report a vulnerability** button
under *Security advisories*. This opens a private advisory visible only to you
and the maintainer — not the public — so a fix can be prepared before any
details are disclosed.

Once a fix is available it will be released and the advisory published with
credit (unless you prefer to remain anonymous). For non-exploitable
documentation or hardening suggestions, a normal public issue or pull request is
welcome.
