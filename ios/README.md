# Pocket Vector for iOS

This directory contains the native iOS port of Pocket Vector. It uses SwiftUI
for the application shell, SpriteKit for rendering and touch input, and a
deterministic Swift gameplay core. There are no CocoaPods, Swift packages, or
other third-party runtime dependencies.

## Run in Xcode

1. Open `PocketVector.xcodeproj`.
2. Select the shared `PocketVector` scheme.
3. Choose a landscape-capable iPhone or iPad simulator.
4. Press Run.

The target supports iOS 17 and later and is locked to landscape. Its bundle
identifier is currently `com.pocketvector.game`; choose your Apple Developer
team and replace that identifier before installing on a physical device or
creating an App Store archive.

The native target bundles only the curated files in
`PocketVector/Resources/GameAssets/`. The runtime inventory and source
provenance are recorded in `GameAssets/native-assets.json`; the target does not
depend on the browser project's `../public/assets/` directory.

## Command-line verification

List the available schemes and simulator destinations:

```bash
xcodebuild -list -project ios/PocketVector.xcodeproj
xcrun simctl list devices available
```

Build and run the unit tests by replacing the destination name with any
installed iOS simulator:

```bash
xcodebuild \
  -project ios/PocketVector.xcodeproj \
  -scheme PocketVector \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

## Current native scope

- Title, countdown, live play, pause, results, and replay phases
- Fixed-step 60 Hz gameplay with seeded receiver and defender movement
- Press-drag-release throwing with speed-dependent trajectories
- Completions, incompletions, interceptions, touchdowns, score, bonus meter,
  streak multiplier, statistics, and the 60-second game clock
- Original field, logo, quarterback, receiver, and defender art, plus a native
  football that follows the throw direction and rolls its laces around its axis
- Looping native music and layered event sound effects using the bundled WAVs
- Original broadcast HUD with the curved Adrenaline meter, centered clock,
  POINTS scorebug, working mute/pause controls, feedback panels, and compact
  iPhone sizing
- Original cabinet-style side rails around the fixed 4:3 playfield on wide
  landscape displays
- XCTest coverage for randomization, lane setup, throws, trajectory, scoring,
  countdown, timer behavior, HUD geometry/formatting, audio playback, and
  ball-rendering math

The first port intentionally leaves several browser features for later parity
passes: saved settings and high scores, accessibility/options menus, precise
defender body hit masks, Game Center, StoreKit purchases, and App Store assets
and metadata.

## App Store setup still needed

Before distribution, provide an Apple Developer team, a permanent bundle ID,
a final 1024-point app icon, signing capabilities, privacy declarations, and
App Store Connect records. StoreKit 2 can then be added against product IDs
created in App Store Connect; no purchase SDK is required for Apple's native
in-app purchase flow.
