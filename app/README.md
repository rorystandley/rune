# notes_app (Flutter UI)

This is the thin Flutter UI layer. All crypto, storage, and note logic lives in
the pure-Dart [`../packages/notes_core`](../packages/notes_core) package.

See the **[project README](../README.md)** for setup, architecture, the stack
rationale, and run/build/test instructions, plus
[SECURITY.md](../SECURITY.md) and [PRIVACY.md](../PRIVACY.md).

Quick start:

```bash
flutter pub get
flutter test          # state + widget tests
flutter run           # launch on a connected device / desktop target
```
