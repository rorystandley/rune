# Store screenshots

Screenshots are captured by driving a seeded demo vault (no real data) to each
key screen and saving the frames. The harness lives in `app/`:

- `integration_test/demo_seed.dart` — builds a temp vault, unlocks it, seeds
  demo notes.
- `integration_test/screenshots_test.dart` — drives Home → Settings → Editor
  and calls `takeScreenshot`.
- `test_driver/screenshot_driver.dart` — writes the PNGs to `screenshots/…`.
- `tool/screenshots/{ios,android,macos}.sh` — boot the right device size and run.

Output lands in `app/screenshots/<platform>/<size>/` (git-ignored — regenerate
any time). Each run produces `01-home.png`, `02-settings.png`, `03-editor.png`.

## Run

```sh
cd app
flutter pub get

./tool/screenshots/ios.sh        # iPhone 6.9" + iPad 13" simulators
./tool/screenshots/android.sh    # needs a running emulator (see below)
./tool/screenshots/macos.sh      # macOS desktop window
```

Android needs an emulator first (and the Android cmdline-tools from
`flutter doctor`):

```sh
flutter emulators                 # list
flutter emulators --launch <id>
```

## Required store sizes

You only upload the largest size in each family; the stores down-scale the rest.

| Store | Required | Provided by |
|---|---|---|
| iOS App Store | 6.9" iPhone (1320×2868) | `iPhone 17 Pro Max` sim |
| iOS App Store | 13" iPad, only if you ship iPad | `iPad Pro 13-inch` sim |
| Google Play | 2–8 phone shots (min 1080px side), 16:9/9:16 | Android emulator |
| Google Play | Feature graphic 1024×500 (made separately) | design tool |
| Mac App Store | 1280×800 / 1440×900 / 2560×1600 / 2880×1800 | `macos.sh` window |

Add or change device sizes by editing the `DEVICES` arrays in the scripts;
list candidates with `xcrun simctl list devices`.

## macOS capture

`integration_test`'s `takeScreenshot` is **not implemented for macOS desktop**,
so `macos.sh` doesn't use the driver. Instead it builds the seeded demo app,
launches it, reads the window bounds (needs Accessibility permission for your
terminal), and grabs the window with `screencapture`. It captures the two-pane
home; navigate manually for the other screens.

If Accessibility isn't available, capture by hand:

```sh
flutter run -t integration_test/demo_main.dart -d macos
screencapture -o -w screenshots/macos/01-home.png   # then click the window
```

Note: the Mac App Store expects specific sizes (1280×800, 1440×900, 2560×1600,
2880×1800). Resize the window or use a design tool to match before uploading;
direct-download distribution has no size constraint.

## Notes

- The demo passphrase and seeded content are defined in `demo_seed.dart`.
- Phones render the single-pane list; iPad/macOS (≥760px wide) render the
  two-pane layout automatically — good variety for the listings.
- These are raw device frames. Add marketing text / device bezels afterward in
  a design tool or Fastlane `frameit` if you want framed listing images.
