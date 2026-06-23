# Reproducible builds — status, evidence, and residual nondeterminism

This is the honest, evidence-backed companion to
[RELEASE.md → "Reproducible / verifiable builds"](../RELEASE.md#reproducible--verifiable-builds-roadmap-1).
It records what has actually been measured, with what toolchain, and exactly
what is **not yet** proven — so no claim here outruns the diff that backs it.

> **Summary — reproducible in the two-checkout CI gate.** The failed
> two-checkout run 28015970937 was traced to two Android native-library problems:
> Flutter compiled the generated Dart plugin registrant into `libapp.so` with an
> absolute checkout-path `file://` URI, and package:jni linked `libdartjni.so`
> with a path-varying GNU build-id. Rune now patches the pinned disposable
> Flutter SDK and package:jni build input before Android release APK builds. A
> local two-checkout build at different paths reports
> `IDENTICAL apart from signature: 183 entries match`; the authoritative
> Linux/JDK 17 GitHub `reproducibility` workflow is also green
> ([run 28019115978](https://github.com/rorystandley/rune/actions/runs/28019115978),
> commit `43c360d`).

## What "reproducible" has to mean here

F-Droid rebuilds the app from source, then uses
[apksigcopier](https://github.com/obfusk/apksigcopier) to graft the developer's
signature onto its own rebuild. If the grafted result is byte-identical to the
published, developer-signed APK, F-Droid ships **our** APK with a "reproducible"
badge. So the property we need is: *everything except the signing material is
bit-for-bit identical between independent builds.*

The check lives in [`tool/reproducibility/`](../tool/reproducibility/):

- [`compare_apks.py`](../tool/reproducibility/compare_apks.py) — pure-stdlib
  comparator. Compares the ordered entry list and, per entry, the compression
  method, CRC-32, and **raw compressed bytes**, ignoring only the signature
  (`META-INF/*.{RSA,DSA,EC,SF}`, `MANIFEST.MF`, and the v2/v3 APK Signing Block,
  which is not a ZIP entry). Exits non-zero on any other difference.
- [`build_release_apk.sh`](../tool/reproducibility/build_release_apk.sh) — one
  clean release build into a chosen path, honouring `SOURCE_DATE_EPOCH`.
- [`prepare_android_reproducible_build.sh`](../tool/reproducibility/prepare_android_reproducible_build.sh)
  — idempotently patches the disposable Flutter SDK and package:jni source used
  by the Android release build so generated Dart source URIs and JNI build-ids
  are path-independent.
- [`build_twice.sh`](../tool/reproducibility/build_twice.sh) — local
  convenience: build twice, then run the comparator.

CI runs the stronger, two-checkout version on demand:
[`.github/workflows/reproducibility.yml`](../.github/workflows/reproducibility.yml)
(`workflow_dispatch`).

## Pinned build inputs

Reproducibility is only meaningful against a fixed toolchain. These are recorded
here, in [RELEASE.md](../RELEASE.md), in the reproducibility workflow, and in the
F-Droid recipe ([`docs/fdroid/co.rorystandley.rune.yml`](fdroid/co.rorystandley.rune.yml)):

| Input | Value | Pinned in |
|-------|-------|-----------|
| Flutter SDK | `3.44.2` @ `c9a6c484230f8b5e408ec57be1ef71dee1e77020` (channel `stable`) | `*.yml` env, recipe `srclibs` |
| Flutter engine | revision `77e2e94772` (hash `04efd7c093d4e9281d5526ebcad6ecc60ba8badf`) | follows the Flutter tag |
| Dart | `3.12.2` | follows the Flutter tag |
| Gradle | `9.1.0` | `app/android/gradle/wrapper/gradle-wrapper.properties` |
| Android Gradle Plugin | `9.0.1` | `app/android/settings.gradle.kts` |
| Kotlin | `2.3.20` | `app/android/settings.gradle.kts` |
| Java (JDK) | **17** | `setup-java` in CI; `compileOptions`/`jvmTarget` in `build.gradle.kts` |
| compileSdk / targetSdk | `36` / `36` | Flutter defaults (3.44.2) |
| minSdk | `24` | Flutter default (3.44.2) |
| NDK | `28.2.13676358` | `build.gradle.kts` (`flutter.ndkVersion`), recipe `ndk:` |
| Build-tools | `36.1.0` | bundled with the pinned AGP/SDK |
| R8 / resource shrinking | **off** | `build.gradle.kts` (see below) |
| Play dependency metadata | **off** (`dependenciesInfo`) | `build.gradle.kts` |

Two deliberate decisions:

- **R8 / minify off.** R8's output is not guaranteed byte-stable across
  toolchain versions; the app is tiny and ships no Java/Kotlin hot paths, so the
  cost of leaving it on (reproducibility risk) outweighs the benefit. If it is
  ever turned on it must be re-verified against the double-build check.
- **`dependenciesInfo { includeInApk = false; includeInBundle = false }`.** AGP
  otherwise embeds a dependency-tree blob encrypted to a Google public key; it is
  non-deterministic (fresh bytes every build) and alone defeats any byte
  comparison. Turning it off is a hard F-Droid requirement.
- **Generated-toolchain patching.** Flutter `3.44.2` has the
  `FileSystemRoots`/`FileSystemScheme` mechanism needed to turn absolute
  generated-file paths into stable synthetic URIs, but its Android Gradle helper
  does not forward those values to `flutter assemble`, and the compiler URI
  rewrite uses constructor defaults rather than the per-build roots. The wrapper
  patches those two pinned Flutter files in the throwaway SDK clone, then passes
  `filesystem-roots=<canonical app dir>` and
  `filesystem-scheme=org-dartlang-root`. The same wrapper patches package:jni
  `1.0.0`'s Android CMake link options with `-Wl,--build-id=none`, because the
  linked bytes were otherwise identical after zeroing `.note.gnu.build-id`.

## Evidence: two-checkout path independence

### Failed baseline

GitHub Actions run 28015970937 (2026-06-23) built the same commit at
`/home/runner/work/rune/rune/a` and `/home/runner/work/rune/rune/b`. The APK
entry list, timestamps, compression, resources, `classes.dex`, and
`libflutter.so` matched; six native entries differed:

```
lib/{arm64-v8a,armeabi-v7a,x86_64}/{libapp.so,libdartjni.so}
```

`diffoscope` and direct `strings`/`readelf` checks showed:

- `libapp.so` embedded
  `file:///home/runner/work/rune/rune/{a,b}/app/.dart_tool/flutter_build/dart_plugin_registrant.dart`.
  The path also changed derived Dart snapshot strings such as the
  `_PluginRegistrant@...` name hash, so zeroing the ELF build-id was not enough.
- `libdartjni.so` contained no differing source strings. After zeroing only its
  `.note.gnu.build-id` bytes, each ABI pair became identical, proving its
  residual was the native linker's build-id note.

### Local two-path proof after the fix

To validate before pushing, the working tree was copied to two different
physical paths (`/private/tmp/rune-two/a` and `/private/tmp/rune-two/b`) and
built with the pinned Flutter `3.44.2`, NDK `28.2.13676358`, and a temporary pub
cache. The comparator passed:

```
build-a.apk  sha256 4078a084295be6ddb6d3df7bc7d2f49561be4e84e247c4dcea1210c8d45c89cb
build-b.apk  sha256 4078a084295be6ddb6d3df7bc7d2f49561be4e84e247c4dcea1210c8d45c89cb
IDENTICAL apart from signature: 183 entries match
  (names, order, compression, CRC, and compressed bytes).
```

The patched frontend command now compiles the generated registrant as
`org-dartlang-root:///.dart_tool/flutter_build/dart_plugin_registrant.dart`
instead of a checkout-specific `file://` URI, and `readelf -n` on
`libdartjni.so` shows only `.note.android.ident` (no GNU build-id note).

### Linux/JDK 17 CI proof

The authoritative GitHub Actions gate passed on 2026-06-23:
[reproducibility run 28019115978](https://github.com/rorystandley/rune/actions/runs/28019115978)
(`workflow_dispatch`, commit `43c360d`). It built the same commit in two clean
Linux checkouts (`a/` and `b/`) and `compare_apks.py` reported all 183
non-signature entries identical.

Local toolchain used for this run (recorded for honesty — the authoritative CI
run uses Linux/JDK 17):

| | |
|---|---|
| Host | macOS (Darwin 25.5.0), arm64 |
| Flutter / engine / Dart | `3.44.2` (`c9a6c48423`) / `77e2e94772` / `3.12.2` |
| JDK | **21.0.9** (Android Studio JBR) — CI and F-Droid use **17** |
| Gradle / AGP / Kotlin | `9.1.0` / `9.0.1` / `2.3.20` |
| NDK / build-tools / compileSdk | `28.2.13676358` / `36.1.0` / `36` |
| Signing (local) | debug key, v2-only |

## Residual nondeterminism

Honest scoping of what the evidence above does and does not establish.

**Proven locally and in CI:** no nondeterminism from build timestamps, ZIP entry
ordering, compression, the bundled engine (`libflutter.so`), Flutter asset
bundling, the dependency-metadata blob, the generated Dart plugin registrant
path, or package:jni's native build-id. A clean rebuild at two different paths
reproduces the APK bytes exactly.

**Not yet proven — and how to close each:**

1. **JDK major/vendor.** The local run used JDK 21 (Android Studio's JBR); CI
   and F-Droid use JDK 17. `javac`/`d8` output can differ across JDK majors, so
   the Linux/JDK 17 workflow is the authoritative path-independence proof.
2. **Host OS / architecture.** The local run was on macOS/arm64; F-Droid and the
   release pipeline build on Linux/x64. `gen_snapshot` is a host tool emitting
   target-arch code; the Linux CI job closes the gap against F-Droid's
   environment (also Linux/x64).
3. **The real F-Droid test.** None of the above equals "F-Droid rebuilt it and
   the bytes matched the published APK." That can only be confirmed once the app
   is submitted and F-Droid's build server reports `Verified`. Until then this
   document claims only what the diffs above support: deterministic on a fixed
   toolchain, with the inputs pinned so an independent rebuild *can* match.

## How to reproduce the evidence

```sh
# From the repo root. Requires the pinned toolchain (ideally JDK 17).
tool/reproducibility/build_twice.sh /tmp/rune-repro
# -> "IDENTICAL apart from signature: N entries match" and exit 0,
#    or a list of the entries that differ and exit 1.
```

That helper rebuilds in one checkout. To test path independence locally, copy the
working tree to two physical paths, run
[`build_release_apk.sh`](../tool/reproducibility/build_release_apk.sh) once in
each copy with the same `SOURCE_DATE_EPOCH`, then compare the two APKs with
[`compare_apks.py`](../tool/reproducibility/compare_apks.py).

The authoritative proof is the two-path Linux build under Actions →
**reproducibility** → Run workflow. Download the `reproducibility` artifact (both
APKs + a diffoscope report) from the run when investigating any future mismatch.
