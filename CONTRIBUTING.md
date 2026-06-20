# Contributing

Thanks for your interest in this project. It's a privacy-first, local-first,
encrypted notes app — so correctness and trust matter more than features. Please
read this before opening a PR.

## Development setup

See the "Setup, build, run" and "Testing" sections in [README.md](README.md).
In short:

```sh
cd packages/notes_core && dart pub get && cd -
cd app && flutter pub get
```

Before sending a PR, make sure these pass:

```sh
cd packages/notes_core && dart test          # core security + logic tests
cd app && flutter analyze && flutter test     # lints + app tests
```

## Ground rules

- **Match the existing style.** The project uses `flutter_lints`; keep the calm,
  low-dependency, no-telemetry posture. New runtime dependencies need a good
  reason and must be FOSS-compatible (so F-Droid/Flathub stay viable).
- **Security-critical code lives in `packages/notes_core/`.** Changes to crypto,
  storage, or the vault state machine need accompanying tests and a clear
  rationale. We never roll our own crypto primitives (see [SECURITY.md](SECURITY.md)).
- **No network calls** in the app's normal operation. Anything that phones home,
  adds analytics, or weakens the "only ciphertext on disk" invariant will be
  declined.
- **Reporting a vulnerability?** Do **not** open a public issue — follow the
  disclosure process in [SECURITY.md](SECURITY.md).

## Sign your commits (DCO)

We use the [Developer Certificate of Origin](https://developercertificate.org/).
Add a sign-off to each commit (certifying you wrote it / may submit it):

```sh
git commit -s -m "your message"
```

## Licensing of contributions

By contributing, you agree that your contributions are licensed under the
project's **GPLv3** (see [LICENSE](LICENSE)).

**App-store note:** the GPLv3 conflicts with the additional usage restrictions
imposed by Apple's App Store (and similar stores). So that this app can continue
to be distributed there, by submitting a contribution you also grant the project
maintainer an additional permission, under GPLv3 §7, to distribute your
contribution through application stores under those stores' standard terms. This
permission does not affect anyone's GPLv3 rights to the source. If you're not
comfortable with this, open an issue first so we can discuss alternatives.

> This project is maintained by a solo developer; this is a pragmatic,
> good-faith arrangement, not formal legal advice.
