# Native asset sources and regeneration

All shipping resources are checked in under
`ios/PocketVector/Resources/GameAssets/`. A normal build does not run any asset
generator. Editable source art and the tools that produce native runtime files
are intentionally kept outside that bundle.

## Inventory contract

`ios/PocketVector/Resources/GameAssets/native-assets.json` declares the exact
runtime inventory and its source provenance. The manifest contains 620 assets:

- 3 native control PNGs;
- 16 WAV audio files;
- 582 lossless character WebPs: 38 shared/fallback frames and 544 baked
  primary/alternate uniform frames for all eight launch teams;
- 1 compatibility stadium field PNG;
- 1 neutral stadium/turf PNG;
- 1 universal field-markings PNG;
- 16 team paint PNGs: one end-zone layer and one midfield layer for each of
  the eight launch teams.

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

Approved baked launch-team source strips:

```text
ios/AssetSources/PixelCharacters/teams/<team-id>/primary/{qb,receiver,defender}-strip.png
ios/AssetSources/PixelCharacters/teams/<team-id>/alternate/{qb,receiver,defender}-strip.png
```

The eight valid `<team-id>` values and their palettes are documented in
`ios/AssetSources/PixelCharacters/teams/README.md`.

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

Team-specific baked sets use the same processor in `--uniform-only` mode. That
mode emits exactly 34 QB, receiver, and defender frames and intentionally omits
the four universal official frames. Generate every primary and alternate set
into its catalog-backed asset prefix. Nova City is shown as the concrete
example:

```bash
python3 ios/Tools/process-pixel-character-strips.py \
  --qb-strip ios/AssetSources/PixelCharacters/teams/nova_city_comets/primary/qb-strip.png \
  --receiver-strip ios/AssetSources/PixelCharacters/teams/nova_city_comets/primary/receiver-strip.png \
  --defender-strip ios/AssetSources/PixelCharacters/teams/nova_city_comets/primary/defender-strip.png \
  --uniform-only \
  --output-dir ios/PocketVector/Resources/GameAssets/characters/teams/nova_city_comets/primary \
  --force

python3 ios/Tools/process-pixel-character-strips.py \
  --qb-strip ios/AssetSources/PixelCharacters/teams/nova_city_comets/alternate/qb-strip.png \
  --receiver-strip ios/AssetSources/PixelCharacters/teams/nova_city_comets/alternate/receiver-strip.png \
  --defender-strip ios/AssetSources/PixelCharacters/teams/nova_city_comets/alternate/defender-strip.png \
  --uniform-only \
  --output-dir ios/PocketVector/Resources/GameAssets/characters/teams/nova_city_comets/alternate \
  --force
```

All 16 team/uniform directories contain lossless 384 x 512 WebPs anchored at
`[192, 496]`. Together they add 544 baked frames and approximately 25.14 MiB to
the checked-in resource bundle. They preserve fully authored team materials
and must be loaded without runtime uniform projection. The shared 38-frame set
remains an emergency/development fallback rather than launch-team presentation.
Technical owns team/jersey routing and the projection-bypass behavior.

## Stadium field

Neutral source and registration specification:

```text
ios/AssetSources/Field/stadium-field-neutral-v1.png
ios/AssetSources/Field/field-layers-v1.json
```

Generated editable layers:

```text
ios/AssetSources/Field/field-markings-v1.png
ios/AssetSources/Field/field-paint-distress-mask-v1.png
ios/AssetSources/Field/teams/<team-id>/end-zone-v1.png
ios/AssetSources/Field/teams/<team-id>/field-branding-v1.png
```

Runtime outputs:

```text
ios/PocketVector/Resources/GameAssets/pixel/stadium-field-neutral-v1.png
ios/PocketVector/Resources/GameAssets/pixel/field-markings-v1.png
ios/PocketVector/Resources/GameAssets/pixel/teams/<team-id>/end-zone.png
ios/PocketVector/Resources/GameAssets/pixel/teams/<team-id>/field-branding.png
ios/PocketVector/Resources/GameAssets/pixel/stadium-field-wide-endzone-v3.png
```

All field layers share an exact 1728 x 768 canvas and pixel origin. The neutral
plate contains one continuous green turf material with no mowing bands or team
identity. Its centered goalpost contacts the rear end-zone edge at `(864, 230)`.
The generated universal markings use the locked perspective in
`field-layers-v1.json`; team end zones use the same projected four-corner mask,
and midfield emblems are transparent distressed paint without backing panels.

The intended runtime stack is neutral base, selected team's end-zone and
field-branding layers, universal markings, then gameplay actors and HUD. The
shipping `stadium-field-wide-endzone-v3.png` is retained as a neutral-plus-
markings compatibility plate until Technical switches the gameplay renderer to
the layered files. Do not add team identity to that compatibility plate.

The neutral stadium was created with built-in ImageGen and normalized to the
locked canvas without changing its 9:4 composition. Canonical generated output:

```text
/Users/andypark/.codex/generated_images/019f7182-19d5-7d40-8e97-6ebea8ba5808/exec-b2d3647f-b9fe-4a33-b4c0-e33da141c6b0.png
```

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

The previous Nova source plates are retained as edit inputs. The shipping phone
and iPad plates are the static High Mesa Helions renders:

```text
ios/AssetSources/Menu/menu-high-mesa-helions-phone-v1.png
SHA-256 1a8f6d2c6f81157b291d92b3f84261b6b391496e8bff8525351598ba446358d3
ios/AssetSources/Menu/menu-high-mesa-helions-pad-v2.png
SHA-256 0c6d013086641ce5f6a1659fe5c33e2d806bf5012ed74110bd4004a6658557c0
ios/PocketVector/Resources/Assets.xcassets/MenuHighMesaScenePhone.imageset/
ios/PocketVector/Resources/Assets.xcassets/MenuHighMesaScenePad.imageset/
```

The phone plate is a precise built-in ImageGen edit of
`menu-concept-scene-v3.png`, grounded by the original supplied concept. Its
brief preserved the exact composition and detailed pixel-art materials, baked
the High Mesa palette and `HIGH MESA` / `HELIONS` banners, replaced all team
marks with the solar-mesa emblem, changed the quarterback and locker jersey
numbers to `10`, made the leaderboard bars neutral glacier-white, and kept the
bottom-center gap clear for the live Personal Best overlay. The canonical
generated output is:

```text
/Users/andypark/.codex/generated_images/019f7182-19d5-7d40-8e97-6ebea8ba5808/exec-d1690610-ee1a-4b51-855e-8d37f0b0632c.png
```

The dedicated 1448 x 1086 iPad plate is a separate precise edit of
`menu-concept-scene-pad-v3.png`. It uses the approved phone render as the
identity and material reference while preserving the iPad source's 4:3 stadium
depth and vertical composition. It applies the same exact copy, solar-mesa
marks, independent material colors, quarterback number `10`, locker number
`10`, neutral leaderboard bars, and empty Personal Best slot.

Its canonical generated output is:

```text
/Users/andypark/.codex/generated_images/019f7182-19d5-7d40-8e97-6ebea8ba5808/exec-a72ee551-316d-48da-bbcd-f8bd2b4eaff2.png
```

The iPad output is an independently rendered 4:3 adaptation, not a
pixel-preserving vertical outpaint. It preserves the approved hierarchy and
subjects while regenerating crowd, field, character, and spacing details for
the wider vertical composition.

The retained `menu-high-mesa-helions-pad-v1.png` source is the provenance plate
for the iPad skyline. Version 2 removes only the two bare center pole assemblies
near x=638 and x=808. Built-in ImageGen reconstructed the occluded sky, rail,
truss, crowd, and marquee-top pixels; that reconstruction was then restricted
to the two tight removal regions so every pixel outside those regions remains
from v1. All three flagged poles and the far-right bare upright remain. The
canonical inpainting output used as the local donor is:

```text
/Users/andypark/.codex/generated_images/019f7182-19d5-7d40-8e97-6ebea8ba5808/exec-f311bca9-4b92-4059-8453-544067129d52.png
```

`MainMenuView` selects only the phone or iPad static plate based on viewport
shape. It performs no Core Image rendering, semantic masking, palette change,
dynamic banner composition, or selected-team asset selection. Gameplay team
selection remains available and persisted, but it does not change the menu's
visual appearance.

The live Personal Best plate uses form-factor-specific geometry to remain clear
of both the Play bezel and utility row: 260 x 150 phone-source pixels at source
y 610, and 240 x 139 iPad-source pixels. Achievements, Store, and Settings
remain in a centered row immediately below it. Phone utilities remain at source
y 758 and render 24-point art bottom-aligned inside separate 44-point targets;
iPad utilities render 36-point art inside separate 52-point targets. The source
rasters retain resolution headroom at both sizes. The coin
and live balance remain anchored independently to the top-leading safe area in
a compact black panel with an ember keyline.

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

## Championship submenu assets

Editable masters for the neutral stadium plate, shared controls, eight
achievement medals, and Settings icons live under:

```text
ios/AssetSources/Submenus/
```

The exact main-menu coin remains the only currency artwork and is consumed
directly as `MenuCoinIcon`; the submenu generator does not duplicate or alter
it. Team emblems, jersey previews, and football previews remain data-driven and
are not baked into the neutral submenu assets.

Runtime outputs are universal lossless PNG imagesets under:

```text
ios/PocketVector/Resources/Assets.xcassets/SubmenuStadiumBackdrop.imageset/
ios/PocketVector/Resources/Assets.xcassets/Submenu*Icon.imageset/
ios/PocketVector/Resources/Assets.xcassets/Achievement*Icon.imageset/
ios/PocketVector/Resources/Assets.xcassets/Settings*Icon.imageset/
```

The backdrop is normalized to 2532 x 1170. Shared control icons are 144 px;
achievement medals are 384 px; Settings panel icons are 192 px and row icons
are 144 px. Nearest-neighbor reduction preserves the authored pixel edges and
all outputs are stripped to deterministic 8-bit sRGB PNGs.

Requirements: Node.js and ImageMagick.

```bash
node ios/Tools/generate-submenu-assets.mjs
```

These asset-catalog resources are outside `native-assets.json`. Validate them
through JSON checks, asset-catalog compilation, simulator builds, and visual
inspection on compact iPhone, regular iPhone, and iPad landscape.

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

The approved Championship Marquee app-icon master is:

```text
ios/AssetSources/AppIcon/pocket-vector-app-icon-championship-v1.png
SHA-256 55ef8e5b1137bc333a7ee01072dcc444b688cbc8be9eadc121a59c88bdc9832c
```

It was created with built-in ImageGen from the approved Pocket Stadium
submittal. The brief preserved the glacier-white `P`, ember-orange `V`, dark
stadium scoreboard, premium double-stepped steel frame, centered brown
football, symmetrical floodlights, and opaque full-bleed square. The canonical
generated output is:

```text
/Users/andypark/.codex/generated_images/019f7182-19d5-7d40-8e97-6ebea8ba5808/exec-70aa945e-732f-4ab6-bdd0-886b762f9947.png
```

The shipping 1024-point PNG is
`ios/PocketVector/Resources/Assets.xcassets/AppIcon.appiconset/PocketVector-AppIcon-1024.png`
with SHA-256
`b21e93de7ff2198f043ab23ff9092ed4fcaf0b29ec9bec46b0bf505f5a5f89bb`.
Generate it deterministically from the source master with:

```bash
magick ios/AssetSources/AppIcon/pocket-vector-app-icon-championship-v1.png \
  -filter LanczosSharp \
  -resize 1024x1024! \
  -colorspace sRGB \
  -alpha off \
  -strip \
  ios/PocketVector/Resources/Assets.xcassets/AppIcon.appiconset/PocketVector-AppIcon-1024.png
```

The previous abstract vector source remains at
`ios/AssetSources/AppIcon/pocket-vector-app-icon.svg` for provenance only; it
is no longer the shipping source.

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
