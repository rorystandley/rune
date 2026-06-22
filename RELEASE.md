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

Before a public 1.0 (from [ROADMAP.md](ROADMAP.md)): independent crypto review +
bit-for-bit reproducible builds (#1, the remaining half of "reproducible/signed")
and supply-chain review / SBOM (#10). Not store blockers, but they back up the
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

Provenance + signing (above) are now in place. The remaining credibility step is
**bit-for-bit reproducibility**: pin toolchain + dependency versions, document the
exact build environment, and make an independent rebuild from this source produce
byte-identical artifacts (the prerequisite for F-Droid's reproducible-build
verification). An easy early win to capture for that work is honouring
`SOURCE_DATE_EPOCH` so archive/build timestamps are deterministic.
