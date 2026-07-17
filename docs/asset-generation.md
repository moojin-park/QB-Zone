# Native asset sources and regeneration

All shipping resources are checked in under
`ios/PocketVector/Resources/GameAssets/`. A normal build does not run any asset
generator. Editable source art and the tools that produce native runtime files
are intentionally kept outside that bundle.

## Inventory contract

`ios/PocketVector/Resources/GameAssets/native-assets.json` declares the exact
runtime inventory and its source provenance. The manifest contains 58 assets:

- 3 native control PNGs;
- 16 WAV audio files;
- 38 lossless character WebPs;
- 1 wide stadium field PNG.

`GameCoreTests.testNativeAssetManifestMatchesBundledResources` enumerates the
physical bundle and requires exact set equality with the manifest, excluding
the manifest file itself. It also decodes every image and audio asset.

## Character sprites

Source strips:

```text
ios/AssetSources/PixelCharacters/qb-strip.png
ios/AssetSources/PixelCharacters/receiver-strip.png
ios/AssetSources/PixelCharacters/defender-strip.png
ios/AssetSources/PixelCharacters/official-strip.png
```

The processor validates nonempty equal-width slots, shared per-role scale,
nearest-neighbor palette preservation, transparent padding, lossless WebP
round trips, mirror pairs, and square defender direction pairs. It writes the
38 runtime WebPs directly to the native character resource directory.

Requirements: Python 3 and Pillow with WebP support.

Validate without writing:

```bash
python3 ios/Tools/process-pixel-character-strips.py \
  --qb-strip ios/AssetSources/PixelCharacters/qb-strip.png \
  --receiver-strip ios/AssetSources/PixelCharacters/receiver-strip.png \
  --defender-strip ios/AssetSources/PixelCharacters/defender-strip.png \
  --official-strip ios/AssetSources/PixelCharacters/official-strip.png \
  --dry-run
```

Regenerate the checked-in WebPs by removing `--dry-run` and adding `--force`.
Review every binary diff before committing.

## Stadium field

Source:

```text
ios/AssetSources/Field/stadium-field-wide-endzone-v2.png
```

Runtime output:

```text
ios/PocketVector/Resources/GameAssets/pixel/stadium-field-wide-endzone-v3.png
```

The tool removes obsolete painted sidelines while preserving the authored turf
and yard-line texture. SpriteKit draws current boundaries, team wordmarks, and
end-zone identity at runtime.

Requirements: Node.js and ImageMagick.

```bash
node ios/Tools/generate-native-field-plate.mjs
```

## Main-menu stadium

Editable source:

```text
ios/AssetSources/Menu/menu-stadium-neutral-v1.png
```

Runtime asset-catalog image:

```text
ios/PocketVector/Resources/Assets.xcassets/MenuStadium.imageset/menu-stadium-neutral-v1.png
```

The 1672 x 941 lossless PNG was created with the built-in image generator from
the approved menu concept and the existing stadium-field source. The generation
prompt requested a neutral 16:9 nighttime pixel-football stadium with a bright
crowd and floodlights, blank banners, sideline equipment, and no lettering,
logos, characters, or baked team identity. `MainMenuView` adds the selected
team's colors, mark, wordmark, and runtime-recolored players above this plate.

The neutral source must stay free of team marks so all eight launch teams can
share the same composition. Validate it through the asset-catalog build; it is
not part of the exact `native-assets.json` runtime inventory.

## HUD control icons

Sources:

```text
ios/AssetSources/Controls/icon-mute.svg
ios/AssetSources/Controls/icon-unmute.svg
ios/AssetSources/Controls/icon-pause.svg
```

Runtime outputs are the corresponding `-native.png` files under
`ios/PocketVector/Resources/GameAssets/art/`.

Requirements: Node.js, macOS `sips`, and ImageMagick.

```bash
node ios/Tools/generate-native-control-icons.mjs
```

The tool strips nondeterministic PNG metadata. A regeneration should leave
identical hashes when neither source nor tool behavior changed.

## App icon and audio

The editable app-icon source is
`ios/AssetSources/AppIcon/pocket-vector-app-icon.svg`; the shipping 1024-point
PNG lives in the app icon asset catalog.

Audio files under `GameAssets/audio/` are checked-in shipping masters. There is
no active audio generator in this repository. Replace them only with approved,
redistributable masters and then update the manifest and audio tests.

## Change checklist

1. Change only an editable source or an intentional tool rule.
2. Run the relevant generator and inspect binary dimensions and transparency.
3. Update `native-assets.json` if paths or inventory changed.
4. Run the focused manifest test and the complete simulator suite.
5. Create an unsigned generic-iOS Release archive.
6. Confirm the archive contains the declared runtime assets and does not contain
   `AssetSources/` or `Tools/`.
