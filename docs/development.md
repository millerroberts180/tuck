# Developing Tuck

Tuck is a Swift package with no Xcode project. `TuckCore` holds the logic and its tests; `TuckApp` is
the app: the overlay, panel, Settings, setup, and the Accessibility and system integrations. See
[architecture.md](architecture.md) for how they fit together.

## Requirements

- macOS 14 or later
- Swift 6 toolchain (Xcode 16+ or the Command Line Tools)
- No third-party dependencies

## Build and run

```sh
# Once per Mac: a local signing identity, so the Accessibility grant survives rebuilds (below)
scripts/signing-identity.sh

# Build a size-optimised, stripped app bundle into build/Tuck.app and launch it
scripts/build-app.sh
open build/Tuck.app

# Or run straight from SwiftPM during development
swift run Tuck

# Debug builds only (swift run is one), for demos and checks; a release build ignores these flags.
# Open the panel automatically on launch
swift run Tuck -TuckOpenOnLaunch YES

# Screenshots and checks against a separate library, never your own: open the fold fully (full),
# through a lens (windows, files or copied) or on the window picker (picker), open Settings, or open
# setup or the tutorial
swift run Tuck -TuckSupportDirectory /tmp/tuck-shots -TuckOpenOnLaunch YES -TuckOpenPage full
swift run Tuck -TuckSupportDirectory /tmp/tuck-shots -TuckOpenSettingsOnLaunch YES
swift run Tuck -TuckSupportDirectory /tmp/tuck-shots -TuckOpenSetupOnLaunch YES
swift run Tuck -TuckSupportDirectory /tmp/tuck-shots -TuckOpenTutorialOnLaunch YES

# Render every Settings pane and setup step, light and dark, to PNGs without opening a window; and the
# fold and the notch: States 0 to 2, each lens, every kind as a tile (gallery-tiles-*), an open editor,
# stack and app's windows, searches (chips, a lens stepping aside, no matches), Arrange, the window
# picker, the prompts, the in-panel drop for a file, a link and text, and the closed surface's states
# and drop labels, in Light, Dark and both Increase Contrast appearances
swift run Tuck --snapshot-ui /tmp/tuck-settings
swift run Tuck --snapshot-panel /tmp/tuck-panel
```

macOS ties the Accessibility grant to the app's signature. An ad-hoc signature changes with every
build, so the permission would need granting again after each rebuild. `scripts/signing-identity.sh`
creates a self-signed "Tuck Local Signing" certificate in its own keychain,
`~/Library/Keychains/tuck-signing.keychain-db`, and `scripts/build-app.sh` signs with it whenever it
exists, so the grant survives rebuilds. Without it, the build is signed ad hoc and says so. The same
identity signs the test DMG until there is a Developer ID (see [release.md](release.md)), so back up its
private key. A `swift run` has no bundle and no such signature.

## Tests

```sh
scripts/test.sh
```

The script adds the framework search paths Swift Testing needs when only the Command Line Tools are
installed; with full Xcode, `swift test` works directly. The tests cover the logic in `TuckCore`:
the one stream (`StreamTests`: its order, grouping by app, lenses, search and the drop target's labels),
merging a sessions library into it and backing it up (`SessionsMigrationTests`), recognising each
kind of copy and its thresholds, reading kind and day words in a search, clipboard capture, re-copies,
previews, assets and history from before kinds, held items and
clearing them, how windows are tucked, grouped, ordered and restored, placement geometry and the
placement chooser, choosing windows to tuck, drops and file intake, persistence and recovery, Rest
eligibility, keyboard shortcuts, haptic pacing, swipe and scroll maths, surface layout and springs,
settings carried over from the old bundle ID (`SettingsMigrationTests`, on throwaway preferences
domains it removes again), and setup's tour: its steps, the gesture practice through the real swipe
tracker, and the pretend desktop's drop and flight geometry.

## Releasing

Tuck is offered directly, outside the Mac App Store, as a free DMG signed with a Developer ID and
notarized by Apple, for Apple silicon only. `scripts/release.sh` builds it into `dist/`, with its
checksum; `scripts/release.sh --unsigned` makes a test DMG without an Apple account, signed with "Tuck
Local Signing" when this Mac has it. The bundle ID and copyright are set once, in `Support/release.env`,
with the website, support, privacy policy and licence agreement links that About shows. Each DMG comes
with its debug symbols, zipped beside it in `dist/` (never inside), for reading crash reports. See
[release.md](release.md) for the one-time setup, the steps and the launch checklist.
