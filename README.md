# Pocket Vector

Pocket Vector is a native landscape arcade football game for iPhone and iPad.
The shipping app is written in Swift 6, SwiftUI, and SpriteKit and supports
iOS 17 and later. This repository contains only the iOS product; the historical
browser implementation is maintained separately.

## Open and run

1. Open `ios/PocketVector.xcodeproj` in Xcode.
2. Select the shared `PocketVector` scheme.
3. Choose a landscape-capable iPhone or iPad simulator.
4. Run the app.

The development bundle identifier is `com.pocketvector.game`. A permanent
identifier and Apple Developer team are still required before device and App
Store distribution.

## Verify from the command line

Run the simulator test suite with any installed simulator destination:

```bash
xcodebuild \
  -project ios/PocketVector.xcodeproj \
  -scheme PocketVector \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

Create an unsigned generic-device archive for the reproducibility gate:

```bash
xcodebuild \
  -project ios/PocketVector.xcodeproj \
  -scheme PocketVector \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/PocketVector.xcarchive \
  CODE_SIGNING_ALLOWED=NO \
  archive
```

## Repository layout

- `ios/PocketVector/`: app, gameplay, domain, persistence, services, and UI.
- `ios/PocketVectorTests/`: native unit, integration, resource, and presentation tests.
- `ios/PocketVector/Resources/GameAssets/`: exact shipping runtime asset bundle.
- `ios/AssetSources/`: editable source art retained for native regeneration.
- `ios/Tools/`: deterministic native asset tools.
- `docs/`: gameplay references and production release contracts.

Runtime resources are enumerated in
`ios/PocketVector/Resources/GameAssets/native-assets.json`. The native test
suite requires that manifest to match the physical bundled files exactly.

## Production status

The gameplay core, production shell, eight-team catalog, persistence model,
Apple service adapters, tutorial, shipping visuals, and diagnostics foundation
are implemented. Live CloudKit hydration, production service composition,
permanent Apple identifiers, commerce, rewarded-ad verification, device QA,
TestFlight gates, and App Store records remain release work.

See `docs/production-release-status.md` for the active delivery board and
`docs/production-release-charter.md` for the approved version-one scope.

## Asset regeneration

Native asset sources and commands are documented in
`docs/asset-generation.md`. Regeneration is optional for normal builds because
all runtime assets are checked in. The field and control tools require Node.js
and ImageMagick; control icons also use macOS `sips`. Character processing
requires Python 3 with Pillow WebP support.
