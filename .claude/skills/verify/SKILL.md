---
name: verify
description: Verify UI changes to the Rune app by driving it on a real iOS simulator and capturing device screenshots.
---

# Verifying Rune UI changes

The app lives in `app/`. The repo already ships an integration-test screenshot
harness — reuse it instead of clicking the Simulator (computer-use screen
recording is not granted on this machine, and there is no idb/cliclick).

## Recipe

1. Boot a simulator: `xcrun simctl list devices available | grep iPhone`,
   then `xcrun simctl boot <udid>`.
2. Write a throwaway drive target at `app/integration_test/verify_*.dart`,
   modelled on `integration_test/screenshots_test.dart`:
   - `buildSeededController()` from `demo_seed.dart` gives an unlocked vault
     with 5 notes; call `controller.deleteNote(...)` to thin it out.
   - Avoid `pumpAndSettle` (blinking cursors never settle); pump fixed frames.
   - `binding.takeScreenshot('name')` captures the real device frame,
     including safe-area insets.
   - Dark mode: `controller.updateSettings(settings.copyWith(themeMode: ...))`.
3. Run it (from `app/`):
   ```sh
   SCREENSHOT_OUT=<out-dir> flutter drive \
     --driver=test_driver/screenshot_driver.dart \
     --target=integration_test/verify_fixes_test.dart -d <udid>
   ```
   Build + run takes ~2 min. PNGs land in `SCREENSHOT_OUT`.
4. Delete the throwaway target before committing; shut the simulator down.

## Gotchas

- `tester.pump(Duration(seconds: n))` does not reliably let a SnackBar's
  real timer expire — expect snackbars to linger across later captures.
- `enterText` raises the keyboard inset; Flutter's capture shows the area
  blank with content shifted up. Not a bug.
- Tests at the default 800px test size hit the wide (two-pane) layout;
  the phone layout needs a real phone-sized device, which this recipe uses.
