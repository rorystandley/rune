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

Before a public 1.0 (from [ROADMAP.md](ROADMAP.md)): independent crypto review +
reproducible/signed builds (#1) and supply-chain review / SBOM (#10). Not store
blockers, but they back up the "honestly private" claim.

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

## Reproducible / verifiable builds (ROADMAP #1)

For a privacy app this is the credibility step: pin toolchain + dependency
versions, document the exact build environment, publish build hashes, and sign
releases so users can verify the binary matches this source.
