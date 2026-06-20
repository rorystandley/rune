# Privacy

Plain English. No lawyer-speak, no weasel words.

## The short version

- Your notes stay **on your device**.
- Your notes are **encrypted** with a passphrase only you know.
- The app makes **no network connections** in normal use.
- There is **no account**, **no cloud**, **no sign-up**, **no email**.
- There is **no telemetry**, **no analytics**, **no crash reporting**, **no
  tracking**, and **no advertising** — none, not "anonymised", not "aggregated".
- We don't have your data. There is no "we". There is no server.

## What data exists, and where

| Data | Where it lives | Protected how |
|------|----------------|---------------|
| Note titles & bodies | This device only | Encrypted (XChaCha20-Poly1305) |
| Your passphrase | Only in your memory while you type it | Never stored; not recoverable |
| Encryption keys | In device RAM only while unlocked | Wiped (best effort) on lock |
| Auto-lock setting & toggles | `settings.json` on device | Stored in clear — contains no secrets |
| Voice recordings | Temp folder on device | Deleted after transcription by default |
| Exports you create | Where you save them | Encrypted backup = safe; plaintext = **not** safe |

## Network

The app contains **no networking code** and requires no network permission to
create, edit, search, read, or transcribe notes. If you put this device in
airplane mode, everything still works. If anything ever tries to make a network
call, that is a bug — report it.

(For transparency: the **Flutter developer tooling** used to build the app has
its own usage analytics, which were turned off during development with
`flutter --disable-analytics`. That is build-time tooling, not part of the app,
and ships nothing.)

## Voice notes

- Recording happens **locally** on your device.
- Transcription is designed to happen **locally** too (see
  [docs/transcription.md](docs/transcription.md)). In this build the transcriber
  is a clearly-labelled stub — it does not send audio anywhere because it does
  nothing over the network at all.
- By default, the **raw audio is deleted** as soon as transcription finishes.
  You can opt to keep it.

## Exports

- **Encrypted backup**: stays encrypted, needs your passphrase to open. Safe to
  store on a USB stick or (if you choose) a cloud drive.
- **Plaintext export**: writes your notes as readable, **unencrypted** files.
  The app forces an explicit warning and confirmation first. After that, those
  files are your responsibility — anything that can read the folder (including
  OS cloud-backup features) can read your notes.

## What we ask you to understand

- **If you forget your passphrase, your notes are gone.** No reset, no recovery,
  no backdoor. This is the price of real privacy.
- Encryption protects data **at rest**. It cannot protect notes that are open on
  an unlocked, compromised device.

## Changes

This is an MVP. If the privacy posture ever changes (for example, if optional
sync is added later), it will be **opt-in**, off by default, and documented here
before it ships.
