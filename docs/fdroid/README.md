# Getting Rune into F-Droid

F-Droid builds every app **itself, from source**, on its own servers and signs
the result. If we also publish a developer-signed APK and the bytes match
F-Droid's independent rebuild, F-Droid ships **our** signed APK with a
[reproducible-build](https://f-droid.org/docs/Reproducible_Builds/) badge. That
is the end goal of ROADMAP #1 and the reason for the determinism work in
[RELEASE.md](../../RELEASE.md#reproducible--verifiable-builds-roadmap-1) and
[`tool/reproducibility/`](../../tool/reproducibility/).

This directory holds what F-Droid needs **on our side**; the actual recipe is
contributed to F-Droid's separate `fdroiddata` repository (an external merge
request — steps below).

## What's here

- [`co.rorystandley.rune.yml`](co.rorystandley.rune.yml) — the F-Droid build
  recipe (the file that becomes `metadata/co.rorystandley.rune.yml` in
  `fdroiddata`). Pins Flutter/Gradle/AGP/Kotlin/NDK/compileSdk/Java and points
  F-Droid at our published APK for reproducible verification.
- The store listing is **not** duplicated here: F-Droid reads it straight from
  this repo's [`fastlane/metadata/android/en-US/`](../../fastlane/metadata/android/en-US/)
  (title, descriptions, changelog, screenshot). Keep that updated and F-Droid
  picks it up automatically.

## Before you submit (prerequisites)

The recipe is complete in form but has two `FILL BEFORE SUBMIT` placeholders that
can only be set once the first real release exists:

1. **Cut a tagged release.** F-Droid builds a tag, not a moving branch. Tag the
   release commit `v0.1.0` (matching `versionName`/`versionCode` in
   `app/pubspec.yaml`, currently `0.1.0+1`) and let the release workflow publish
   the artifacts. Set the recipe's `commit:` to that tag.
2. **Finalise the release signing key** and fill `AllowedAPKSigningKeys` with its
   **SHA-256** (the release key, *not* the CI debug fallback). With the published
   APK in hand:
   ```sh
   apksigner verify --print-certs notes-app-android.apk | grep -i 'SHA-256'
   # -> use the hex digest, lowercased, with no colons
   ```
3. **Confirm the `Binaries:` URL resolves** — i.e. the release attaches
   `notes-app-android.apk` (it does; see `release.yml`). `%v` expands to the
   `versionName`.

Until those are filled, the recipe must not be submitted: F-Droid would reject an
all-zero signing key, and reproducible verification needs the real one.

## Test the recipe locally (recommended before opening the MR)

Use `fdroidserver` (the easiest route is F-Droid's Docker image so you don't have
to install the full Android/Flutter toolchain locally):

```sh
# In a checkout of https://gitlab.com/fdroid/fdroiddata with the recipe added as
# metadata/co.rorystandley.rune.yml:

fdroid readmeta                       # the recipe parses
fdroid lint co.rorystandley.rune      # passes F-Droid's linter
fdroid rewritemeta co.rorystandley.rune   # normalise formatting (review the diff)

# Full build of the tagged version (slow; needs Docker or a configured toolchain):
fdroid build -v -l co.rorystandley.rune
```

A successful `fdroid build` produces an APK under `unsigned/`. To pre-check
reproducibility against our published binary the way F-Droid's server will:

```sh
# Compare F-Droid's rebuild to the developer-signed APK (signature ignored).
# apksigcopier is the same tool F-Droid uses; or use our comparator:
python3 /path/to/rune/tool/reproducibility/compare_apks.py \
  unsigned/co.rorystandley.rune_1.apk  notes-app-android.apk
```

## Submit the merge request to fdroiddata

F-Droid recipes live in <https://gitlab.com/fdroid/fdroiddata> (GitLab, not this
repo). High-level steps — F-Droid's
[Inclusion How-To](https://f-droid.org/docs/Inclusion_How-To/) and
[Submitting to F-Droid Quick Start](https://f-droid.org/docs/Submitting_to_F-Droid_Quick_Start/)
are authoritative:

1. Fork `fdroid/fdroiddata` on GitLab and clone your fork.
2. Add the recipe as `metadata/co.rorystandley.rune.yml` (copy this file with the
   placeholders filled per above).
3. Run `fdroid lint co.rorystandley.rune` and `fdroid rewritemeta
   co.rorystandley.rune`; fix anything it reports.
4. Commit on a branch, push to your fork, and open a merge request against
   `fdroid/fdroiddata` `master`. Title it `New app: Rune (co.rorystandley.rune)`.
5. In the MR description, note that the app is FOSS (GPL-3.0-or-later), has no
   trackers/AntiFeatures, and is intended for reproducible builds (link this repo
   and [`docs/reproducibility.md`](../reproducibility.md)).
6. Respond to the maintainers' review. Once merged, F-Droid builds, attempts the
   reproducible verification, and — on a byte match — publishes our signed APK.

## Keeping it green for future releases

- Bump `versionName`/`versionCode` in `app/pubspec.yaml`, tag `vX.Y.Z`, and add a
  `fastlane/metadata/android/en-US/changelogs/<versionCode>.txt`.
- `AutoUpdateMode: Version` + `UpdateCheckMode: Tags` mean F-Droid picks up new
  tags automatically; usually no `fdroiddata` change is needed per release.
- If you change the toolchain (Flutter, Gradle, AGP, NDK, Java), update the
  recipe's pins **and** the table in `RELEASE.md` / `docs/reproducibility.md` in
  the same change, then re-run the `reproducibility` workflow.
