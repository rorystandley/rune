<!-- Thanks for contributing! See CONTRIBUTING.md for the ground rules. -->

## What & why

<!-- What does this change, and what problem does it solve? Link the issue if there is one. -->

## Checklist

- [ ] `dart analyze && dart test` pass in `packages/notes_core/`
- [ ] `flutter analyze && flutter test` pass in `app/`
- [ ] Commits are signed off (`git commit -s`, per the DCO in CONTRIBUTING.md)
- [ ] No new runtime dependencies — or the rationale and FOSS licence are explained above
- [ ] No network calls, telemetry, or weakening of the "only ciphertext at rest" invariant
- [ ] Changes to `packages/notes_core/` (crypto, storage, vault state machine) include tests and a clear rationale
- [ ] Docs updated if behaviour changed (README / SECURITY.md / CHANGELOG.md)
