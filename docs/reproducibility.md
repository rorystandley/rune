# Reproducible builds — status, evidence, and residual nondeterminism

This is the honest, evidence-backed companion to
[RELEASE.md → "Reproducible / verifiable builds"](../RELEASE.md#reproducible--verifiable-builds-roadmap-1).
It records what has actually been measured, with what toolchain, and exactly
what is **not yet** proven — so no claim here outruns the diff that backs it.

> **Summary — not yet reproducible.** Two clean builds in the *same* directory
> are byte-for-byte identical, which rules out the usual wreckers (build
> timestamps, file ordering, nondeterministic compression, the Play
> dependency-metadata blob). But the stronger two-checkout CI job — building the
> same commit at two *different* paths, as any independent rebuilder (and
> F-Droid) does — **fails**: the Dart AOT libraries `libapp.so` and
> `libdartjni.so` differ across build paths. So the build is **not bit-for-bit
> reproducible yet**; the residual is build-path dependence in the AOT snapshot.
> See [Residual nondeterminism](#residual-nondeterminism).

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

## Evidence: same-host, same-directory double build (the weaker test)

> This rebuilds in the *same* directory, so it cannot catch build-path
> dependence — which the two-checkout CI job later exposed (see
> [Residual nondeterminism](#residual-nondeterminism)). The identical result
> below therefore proves only same-path determinism, **not** reproducibility.

Ran [`build_twice.sh`](../tool/reproducibility/build_twice.sh) on commit at the
time of writing. Two clean `flutter build apk --release` builds:

```
IDENTICAL apart from signature: 183 entries match
  (names, order, compression, CRC, and compressed bytes).

build-1.apk  sha256 41dc5602964052b7bd51b1533db40ee1a1865b20bc4bfc7be0ea22fe372ab24c
build-2.apk  sha256 41dc5602964052b7bd51b1533db40ee1a1865b20bc4bfc7be0ea22fe372ab24c
cmp: byte-for-byte identical (signature included), 52,953,120 bytes
```

The two APKs were not merely identical apart from the signature — they were
**fully identical**, signature included. Two reasons:

1. AGP normalises ZIP entry timestamps to a constant, and with the
   dependency-metadata blob disabled there is no per-build random data left in
   the non-signature portion.
2. The APK is signed **v2-only** (APK Signature Scheme v2; no v1/JAR signature,
   confirmed with `apksigner verify --verbose`). Signing the identical content
   with the identical key produces the identical signing block, so even the
   signature matched in this same-key run.

Local toolchain used for this run (recorded for honesty — it is **not** all the
pinned set above):

| | |
|---|---|
| Host | macOS (Darwin 25.5.0), arm64 |
| Flutter / engine / Dart | `3.44.2` (`c9a6c48423`) / `77e2e94772` / `3.12.2` |
| JDK | **21.0.9** (Android Studio JBR) — note: CI and F-Droid use **17** |
| Gradle / AGP / Kotlin | `9.1.0` / `9.0.1` / `2.3.20` |
| NDK / build-tools / compileSdk | `28.2.13676358` / `36.1.0` / `36` |
| Signing (local) | debug key, v2-only |

## Residual nondeterminism

Honest scoping of what the evidence above does and does not establish.

**Proven (same host, same *directory*):** no nondeterminism from build
timestamps, ZIP entry ordering, compression, the bundled engine
(`libflutter.so`), Flutter asset bundling, or the dependency-metadata blob — a
clean rebuild at the same path reproduces the bytes exactly. **But** the AOT
snapshot (`libapp.so`, `libdartjni.so`) reproduces *only while the build path is
constant*; across different paths it differs (item 1 below), so it is **not**
proven deterministic.

**Not yet proven — and how to close each:**

1. **Path independence — FAILS (the current blocker).** `build_twice.sh` builds
   twice in the *same* working directory, so an absolute build path leaking into
   an artifact does not show up. The CI job
   [`reproducibility.yml`](../.github/workflows/reproducibility.yml) builds the
   same commit at two *different* checkout paths (`a/` vs `b/`) on Linux/JDK 17.
   It was run on 2026-06-23 (run 28015970937) and **failed**: six native-library
   entries differ — `lib/{arm64-v8a,armeabi-v7a,x86_64}/{libapp.so,libdartjni.so}`.
   This is unresolved **build-path dependence in the Dart AOT snapshot**
   (`gen_snapshot` embeds the build directory into `libapp.so`). Until it is fixed
   — build at a canonical path, or strip the embedded path — Rune is **not**
   reproducible across independent builds, and F-Droid's verification cannot pass.
2. **JDK major/vendor.** This local run used JDK 21 (Android Studio's JBR); CI
   and F-Droid use JDK 17. `javac`/`d8` output can differ across JDK majors, so
   the **authoritative** rebuild must use JDK 17, as pinned. Same-host identity
   under JDK 21 does not certify a JDK-17 rebuild — the Linux/JDK-17 CI job does.
3. **Host OS / architecture.** This run was on macOS/arm64; F-Droid and the
   release pipeline build on Linux/x64. `gen_snapshot` is a host tool emitting
   target-arch code; output is expected to be host-independent, but that has not
   been cross-checked here. The Linux CI job closes the gap against F-Droid's
   environment (also Linux).
4. **The real F-Droid test.** None of the above equals "F-Droid rebuilt it and
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

Or trigger the two-path Linux build under Actions → **reproducibility** → Run
workflow, and download the `reproducibility` artifact (both APKs + a diffoscope
report) from the run.
