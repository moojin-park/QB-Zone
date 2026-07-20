# Pocket Vector iOS target

Pocket Vector uses SwiftUI for app navigation, SpriteKit for gameplay
presentation and touch input, and a deterministic Swift gameplay core. The
target has no third-party runtime dependencies or Swift package dependencies.

## Target contract

- iPhone and iPad
- iOS 17 or later
- landscape left and landscape right only
- one app scene
- Swift 6 concurrency checks
- checked-in privacy manifest and encryption declaration

Open `PocketVector.xcodeproj`, select the shared `PocketVector` scheme, and run
on a landscape-capable simulator. The development bundle identifier is
`com.pocketvector.game`; physical-device and distribution builds require the
owner's Apple Developer team and permanent bundle identity.

## Runtime ownership

- SwiftUI owns launch, menus, settings, tutorial, locker, store, results, and
  platform presentation.
- `AppCoordinator` owns navigation and validates every transition into gameplay.
- SpriteKit receives one immutable run configuration, simulates one run, and
  emits one immutable completion callback.
- The profile repository is the only authority for durable selections, runs,
  records, achievements, ownership, and coin-ledger mutations.
- Apple and advertising adapters report verified outcomes through service
  contracts; they do not mutate the player profile directly.

The complete contract is in `../docs/production-architecture.md`.

## Resources

The app bundles `PocketVector/Resources/GameAssets/` as an opaque resource
folder. `GameAssets/native-assets.json` is the authoritative 620-file inventory,
and `GameCoreTests.testNativeAssetManifestMatchesBundledResources` checks both
directions: every manifest path exists and every physical bundled file is
declared.

Editable native source art lives in `AssetSources/`; regeneration tools live in
`Tools/`. No source art or tool is included in the shipping resource bundle.

## Verification

From the repository root:

```bash
xcodebuild \
  -project ios/PocketVector.xcodeproj \
  -scheme PocketVector \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

Resource, capability, app-composition, or Release changes also require an
unsigned generic-iOS archive. Use the command in the root `README.md`.

## Release dependencies

The native target is not yet an App Store release candidate. Live CloudKit
profile hydration, retained production service orchestration, permanent
identifiers and capabilities, StoreKit products, Game Center records,
rewarded-ad verification, signed device testing, accessibility review,
TestFlight metrics, and App Store metadata remain gated work. See
`../docs/production-release-status.md` for current evidence and dependency order.
