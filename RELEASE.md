# Release & distribution

How to take Rune from source to shipped builds. The app is local-first and
network-free; the privacy story (see [PRIVACY.md](PRIVACY.md) and
[SECURITY.md](SECURITY.md)) makes the store privacy forms easy — declare that
nothing is collected or transmitted.

All commands run from the `app/` directory unless noted.

## Status

Done:

- App icons + splash for all platforms (light, iOS dark, Android themed). Sources
  in `app/assets/branding/`; regenerate with `dart run flutter_launcher_icons`
  and `dart run flutter_native_splash:create`.
- Real bundle identifiers everywhere (`co.rorystandley.*`).
- User-facing name "Rune" across iOS, Android, macOS, Windows, Linux.
- iOS microphone usage string + export-compliance flag (`Info.plist`).
- Android release-signing plumbing (`build.gradle.kts` reads `key.properties`).
- Verifiable releases: SLSA build-provenance attestations + a keyless cosign
  signature over `SHA256SUMS` on every CI release, with gated Android upload
  signing and macOS Developer ID signing + notarization. See
  [Verifying a release](#verifying-a-release).
- Android build determinism (toolchain pinned; Play dependency-metadata blob and
  R8 off; `SOURCE_DATE_EPOCH`; F-Droid recipe + Fastlane metadata in-repo).
  **Not yet bit-for-bit reproducible** — the two-checkout CI build fails on
  build-path-dependent Dart AOT libs (`libapp.so`/`libdartjni.so`). See
  [Reproducible / verifiable builds](#reproducible--verifiable-builds-roadmap-1)
  and [docs/reproducibility.md](docs/reproducibility.md).

Before a public 1.0 (from [ROADMAP.md](ROADMAP.md)): independent crypto review;
**bit-for-bit reproducibility for #1** — the determinism config is in place, but
the Dart AOT libraries are still build-path-dependent (the two-checkout CI build
fails), which must be fixed before F-Droid can verify a tagged release; and
supply-chain review / SBOM (#10). Not store blockers, but they back up the
"honestly private" claim.

## Pre-flight (every release)

```sh
flutter analyze
flutter test
flutter pub outdated   # review before bumping deps
```

Bump the version in `app/pubspec.yaml` (`version: x.y.z+build`). The build number
must increase for every store upload. Consider obfuscating release binaries:
`--obfuscate --split-debug-info=build/symbols`.

## iOS (App Store)

Requires the Apple Developer Program ($99/yr).

1. In Xcode (`open ios/Runner.xcworkspace`): set the team, confirm
   `co.rorystandley.rune`, and create the App ID + app record in
   App Store Connect.
2. Confirm voice notes prompt for mic access (the `NSMicrophoneUsageDescription`
   is set) and that `ITSAppUsesNonExemptEncryption` is correct for you.
3. `flutter build ipa` → upload `build/ios/ipa/*.ipa` via Xcode Organizer or
   `xcrun altool`/Transporter, then submit from App Store Connect.
4. Listing: screenshots per device size, description, privacy "nutrition label"
   (collects nothing), age rating.

## Android (Google Play)

Requires a Play Console account ($25 once).

1. Generate an upload keystore and create `app/android/key.properties` from
   `key.properties.example` (both are git-ignored). **Back up the keystore** —
   losing it blocks future updates.
2. `flutter build appbundle` → upload `build/app/outputs/bundle/release/*.aab`.
3. Play uses Play App Signing; your key is the upload key.
4. Listing: screenshots, feature graphic, description, **Data safety** form
   (no data collected/shared), content rating questionnaire.

## macOS

- Mac App Store: enable Hardened Runtime, sign with a Mac App Store provisioning
  profile, `flutter build macos`, upload via Transporter.
- Direct download: sign with a "Developer ID Application" cert, then **notarize**
  (`xcrun notarytool submit ... --wait`) and `xcrun stapler staple` the `.app`.
- The mic usage string and app sandbox are already set; keep the entitlements
  network-free to match the privacy claim.

## Windows

- `flutter build windows` produces `build/windows/x64/runner/Release/`.
- Package as MSIX (`msix_create`) for the Microsoft Store, or ship a signed
  installer (Inno Setup / WiX). Code-signing cert recommended to avoid
  SmartScreen warnings.

## Linux

- `flutter build linux` produces `build/linux/x64/release/bundle/`.
- Package as Flatpak, Snap, or AppImage. Application ID is
  `co.rorystandley.rune`.

## Verifying a release

Every release built by [`.github/workflows/release.yml`](.github/workflows/release.yml)
ships **cryptographic provenance that anyone can verify against this repo** — no
maintainer secrets are involved in producing it. Two independent mechanisms:

- **SLSA build-provenance attestations** (`actions/attest-build-provenance`) over
  every artifact and `SHA256SUMS`. They prove a file was produced by *this*
  workflow in *this* repo, and are stored by GitHub keyed on the file's digest.
- **A keyless [cosign](https://github.com/sigstore/cosign) signature** over
  `SHA256SUMS` (`SHA256SUMS.cosign.bundle`), made with the workflow's short-lived
  Sigstore/Fulcio identity (no long-lived signing key exists to leak).

Each release attaches the artifacts, `SHA256SUMS`, and
`SHA256SUMS.cosign.bundle`. To verify a download (replace `<artifact>` with the
file you downloaded, e.g. `notes-app-linux-x64.tar.gz`):

```sh
# 1. Provenance: this artifact was built by rorystandley/rune's release workflow.
#    Needs the GitHub CLI (`gh`); no auth required for a public repo.
gh attestation verify <artifact> --repo rorystandley/rune

# 2. The checksums file is signed by this repo's workflow identity (keyless cosign).
#    Needs cosign (https://github.com/sigstore/cosign).
cosign verify-blob \
  --bundle SHA256SUMS.cosign.bundle \
  --certificate-identity-regexp '^https://github.com/rorystandley/rune/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  SHA256SUMS

# 3. Your download matches the (now-trusted) checksums.
sha256sum -c SHA256SUMS        # macOS: `shasum -a 256 -c SHA256SUMS`
```

Step 2 establishes that `SHA256SUMS` itself was signed by this repo's CI; step 3
ties your local file to a line in that trusted list. Step 1 is an independent
provenance check on the artifact itself.

## Signing secrets (CI)

Provenance above is automatic. **Platform code-signing** is gated on repo secrets
(Settings → Secrets and variables → Actions). If a platform's secrets are absent
the workflow falls back to its current behaviour — Android debug signing, macOS
ad-hoc — and the build still succeeds; it never fails for missing secrets.

### Android (Google Play upload signing) — 4 secrets

Signs the `.aab`/`.apk` with your upload keystore instead of the debug key.

| Secret | How to produce it |
|--------|-------------------|
| `ANDROID_KEYSTORE_BASE64` | `base64 -i ~/keys/notes-app-upload.jks` (macOS) / `base64 -w0 …` (Linux) of the keystore from the [Android](#android-google-play) section. |
| `ANDROID_STORE_PASSWORD` | The keystore's store password. |
| `ANDROID_KEY_PASSWORD` | The key's password (often the same as the store password). |
| `ANDROID_KEY_ALIAS` | The key alias (e.g. `upload`). |

### macOS (Developer ID signing + notarization) — 5 secrets

Signs `Rune.app` with a Developer ID Application cert + hardened runtime, then
notarizes and staples it. Requires the Apple Developer Program.

| Secret | How to produce it |
|--------|-------------------|
| `MACOS_CERT_P12_BASE64` | Export your **Developer ID Application** cert + private key from Keychain Access as a `.p12`, then `base64 -i DeveloperID.p12`. |
| `MACOS_CERT_PASSWORD` | The password you set on that `.p12` export. |
| `APPLE_ID` | The Apple ID email used for notarization. |
| `APPLE_APP_SPECIFIC_PASSWORD` | An app-specific password for that Apple ID (appleid.apple.com → Sign-In and Security → App-Specific Passwords). |
| `APPLE_TEAM_ID` | Your 10-character Apple Developer Team ID (Apple Developer → Membership). |

> Do not commit any of these values. Set them only as encrypted Actions secrets.

## Reproducible / verifiable builds (ROADMAP #1)

This is the credibility backbone of the privacy claim: anyone should be able to
prove the shipped binary was built from this source.

### Provenance + signing — **done**

Every release carries SLSA build-provenance attestations and a keyless cosign
signature over `SHA256SUMS` (see [Verifying a release](#verifying-a-release)),
plus gated platform code-signing. No maintainer secrets are involved in producing
the provenance.

### Determinism — **configured, not yet reproducible**

The goal is bit-for-bit reproducibility so an independent rebuild from source
yields byte-identical artifacts — the prerequisite for F-Droid's
reproducible-build badge. What's pinned and configured (full table and rationale
in [docs/reproducibility.md](docs/reproducibility.md)):

- **Pinned build inputs**, recorded here, in the F-Droid recipe, and in the
  `reproducibility` workflow: Flutter `3.44.2`
  (`c9a6c484230f8b5e408ec57be1ef71dee1e77020`, engine `77e2e94772`, Dart
  `3.12.2`), Gradle `9.1.0`, AGP `9.0.1`, Kotlin `2.3.20`, **Java 17**,
  compileSdk/targetSdk `36`, minSdk `24`, NDK `28.2.13676358`, build-tools
  `36.1.0`.
- **`SOURCE_DATE_EPOCH`** derived from the tag commit's date, honoured by the
  release archive packaging (deterministic `tar.gz`; normalised mtimes before the
  Windows zip). macOS archives are left as-is (out of scope; F-Droid is
  Android-only).
- **`app/android/app/build.gradle.kts`**: the Play **dependency-metadata blob is
  disabled** (`dependenciesInfo { includeInApk = false; includeInBundle = false }`)
  — it is non-deterministic and alone defeats any byte comparison — and **R8 /
  resource shrinking is left off** (R8 output isn't byte-stable across toolchain
  versions). Both decisions are documented inline.

### Prove it — the double-build check

Two clean release builds from the same commit must be byte-identical apart from
the signature. Locally:

```sh
# From the repo root (use the pinned toolchain; ideally JDK 17).
tool/reproducibility/build_twice.sh /tmp/rune-repro
# -> "IDENTICAL apart from signature: N entries match"  (exit 0), or the
#    differing entries (exit 1).
```

In CI, the [`reproducibility`](.github/workflows/reproducibility.yml) workflow
(**Actions → reproducibility → Run workflow**, manual-only) builds the APK twice
in two *separate* clean checkouts on Linux and runs the same comparator
([`tool/reproducibility/compare_apks.py`](tool/reproducibility/compare_apks.py)),
uploading both APKs and a diffoscope report.

**Evidence:** two clean builds in the *same* directory are byte-for-byte
identical (same SHA-256), which rules out timestamps, entry ordering,
nondeterministic compression, and the dependency blob. But the stronger
two-checkout CI job — building the same commit at two *different* paths — **fails**
(run 28015970937, 2026-06-23): the Dart AOT libraries `libapp.so` and
`libdartjni.so` differ across build paths. So the build is **not yet reproducible**
across independent checkouts; the residual is build-path dependence in the AOT
snapshot, which must be fixed before F-Droid can verify it. Full detail in
[docs/reproducibility.md](docs/reproducibility.md).

### F-Droid submission

F-Droid rebuilds from source and, on a byte match, ships our signed APK with a
"reproducible" badge. Prepared in-repo:

- **Store listing**: [`fastlane/metadata/android/en-US/`](fastlane/metadata/android/en-US/)
  (title, short/full description, changelog, phone screenshot) — F-Droid reads it
  straight from this repo.
- **Build recipe**: [`docs/fdroid/co.rorystandley.rune.yml`](docs/fdroid/co.rorystandley.rune.yml)
  (License `GPL-3.0-or-later`, `subdir: app`, pinned Flutter/NDK, the exact build
  commands, `Binaries:` pointing at the published APK for reproducible
  verification, AntiFeatures: none).
- **How to submit** the merge request to `gitlab.com/fdroid/fdroiddata`, plus the
  two values to finalise first (a `v0.1.0` tag and the release key's SHA-256):
  [`docs/fdroid/README.md`](docs/fdroid/README.md).
