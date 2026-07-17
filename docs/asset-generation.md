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

## Main-menu concept scene

The user-supplied reference is retained verbatim for provenance:

```text
ios/AssetSources/Menu/menu-concept-reference-original.png
SHA-256 a45f4ca6b5306cd3791832a2ef6275a62f531edfcc8e87cddf4331ebf7e3fccf
```

The shipping phone and iPad plates are:

```text
ios/AssetSources/Menu/menu-concept-scene-v3.png
ios/AssetSources/Menu/menu-concept-scene-pad-v3.png
ios/PocketVector/Resources/Assets.xcassets/MenuConceptScene.imageset/
ios/PocketVector/Resources/Assets.xcassets/MenuConceptScenePad.imageset/
```

The phone plate is a precise built-in ImageGen edit of the reference. Its edit
brief was: remove the bottom-center Achievements control and the far-right
Personal Best board; reconstruct the vacated turf, crowd, and sideline equipment
in the same detailed pixel-art style; preserve the title, tagline, Play control,
QB, coach, Locker, Leaderboard, typography, lighting, and all other composition.
The canonical generated output is:

```text
/Users/andypark/.codex/generated_images/019f7182-19d5-7d40-8e97-6ebea8ba5808/exec-64a8d3e9-e33a-453b-93ea-05fc23f3210e.png
```

The dedicated 1448 x 1086 iPad plate was built with the original concept as
visual grounding. The complete ImageGen brief was:

> Preserve the centered Pocket Vector concept composition and extend it to a
> seamless 4:3 stadium. Continue the night sky, upper bowl, trusses,
> floodlights, flags, turf, sideline, and yard markings in the same polished
> high-detail pixel-art style. Do not duplicate or add title, Play, navigation,
> characters, scoreboards, icons, text, logos, or helmets. Do not blur or soften
> the art.

Its canonical generated output is:

```text
/Users/andypark/.codex/generated_images/019f7182-19d5-7d40-8e97-6ebea8ba5808/exec-8441f627-1b0f-428a-aa3e-ef7acb231db8.png
```

The iPad output is an independently rendered 4:3 adaptation, not a
pixel-preserving vertical outpaint. It preserves the approved hierarchy and
subjects while regenerating crowd, field, character, and spacing details for
the wider vertical composition.

`MainMenuView` applies the selected team's illuminated primary and secondary
palette asynchronously through a bounded Core Image cache. Authored masks keep
skin and football leather out of the palette replacement. Dynamic team banners
and upper-stadium lighting complete the team change. Nova City Comets remains
the fresh-profile default.

## Main-menu interface assets

Editable masters and runtime imagesets:

```text
ios/AssetSources/Menu/personal-best-scoreboard-v3.png
ios/AssetSources/Menu/utility-achievements-v2.png
ios/AssetSources/Menu/utility-settings-v2.png
ios/AssetSources/Menu/utility-store-v2.png
ios/AssetSources/Menu/coin-v2.png
ios/PocketVector/Resources/Assets.xcassets/MenuPersonalBest.imageset/
ios/PocketVector/Resources/Assets.xcassets/MenuAchievementIcon.imageset/
ios/PocketVector/Resources/Assets.xcassets/MenuSettingsIcon.imageset/
ios/PocketVector/Resources/Assets.xcassets/MenuStoreIcon.imageset/
ios/PocketVector/Resources/Assets.xcassets/MenuCoinIcon.imageset/
```

- Personal Best began as the reference scoreboard crop. Built-in ImageGen
  isolated the complete scoreboard against a flat chroma field; the chroma was
  deterministically removed to alpha without redrawing the housing. Canonical
  generated output:
  `/Users/andypark/.codex/generated_images/019f7182-19d5-7d40-8e97-6ebea8ba5808/exec-e17f5df4-eacb-442a-bb5b-5e61c5cc2a30.png`.
- Achievements is the trophy-and-frame crop from the supplied concept.
- Settings used built-in ImageGen with the brief “single detailed square
  pixel-art steel gear utility icon, navy equipment-panel housing, orange trim,
  centered, no text.” Canonical output:
  `/Users/andypark/.codex/generated_images/019f71e4-86ed-7d43-8bb4-92dfa4264e57/exec-73766e19-87a5-4141-9a09-d02f21fdaf42.png`.
- Store used built-in ImageGen with the brief “single detailed square pixel-art
  football equipment/store chest, navy equipment-panel housing, orange trim,
  centered, no text.” Canonical output:
  `/Users/andypark/.codex/generated_images/019f71e4-db88-7a03-8d58-cc9149fe7026/exec-cee88d88-a990-4615-9589-a66d109f3d18.png`.
- Coin used built-in ImageGen with the brief “single polished gold arcade coin,
  embossed football seam, transparent background, no text.” Canonical output:
  `/Users/andypark/.codex/generated_images/019f71e5-2b2a-7032-9462-4dfdd3fddf44/exec-e3644807-a924-435b-a4cb-3e837babbcec.png`.

The source masters retain full generation resolution. Runtime Settings and Store
are normalized to 144 px, Coin to 96 px, and Personal Best to 660 x 381 px;
these sizes cover the largest device-pixel slot without shipping multi-megabyte
utility textures. Menu assets are validated through asset-catalog compilation
and are not part of the exact `native-assets.json` inventory.

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
