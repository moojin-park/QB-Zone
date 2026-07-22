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

The permanent bundle identifier is `com.pocketvector.game`, and the app target
is assigned to the owner's Apple Developer team. App Store distribution still
requires the account records and signed-release gates tracked in
`docs/production-release-status.md`.

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

Create and export an App Store Connect-signed archive after the reproducibility
gate passes:

```bash
xcodebuild \
  -project ios/PocketVector.xcodeproj \
  -scheme PocketVector \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/PocketVector-AppStore.xcarchive \
  -allowProvisioningUpdates \
  archive

xcodebuild \
  -exportArchive \
  -archivePath /tmp/PocketVector-AppStore.xcarchive \
  -exportPath /tmp/PocketVector-AppStore-export \
  -exportOptionsPlist ios/ExportOptions-AppStore.plist \
  -allowProvisioningUpdates
```

The tracked export options preserve the committed build number, require the
Production CloudKit environment, and use Apple-managed distribution signing.

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
tutorial, shipping visuals, diagnostics, private-cloud profile association, and
online-only commerce composition are implemented. The configured runtime now
fails closed unless both CloudKit and StoreKit configuration are complete;
catalog spends and coin-pack requests revalidate the private account and
network immediately before their transaction boundary. The permanent bundle
identity and Apple team are configured. Build 159 is the current code baseline
and passes the complete simulator suite and unsigned Release archive; build 158
remains the last App Store distribution export. App Store products and records,
production CloudKit deployment, live Game Center and rewarded-ad composition,
service-aware privacy answers, build 159 signing and upload, and TestFlight
gates remain release work.

See `docs/production-release-status.md` for the active delivery board and
`docs/production-release-charter.md` for the approved version-one scope.

## Asset regeneration

Native asset sources and commands are documented in
`docs/asset-generation.md`. Regeneration is optional for normal builds because
all runtime assets are checked in. The field and control tools require Node.js
and ImageMagick; control icons also use macOS `sips`. Character processing
requires Python 3 with Pillow WebP support.
