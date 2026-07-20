# Nova City Comets baked gameplay sprites

Approved July 19, 2026. These are fully authored, full-color replacements for
the runtime-mapped uniform proof. The legacy source strips were supplied to
built-in ImageGen only as pose, layout, silhouette, and relative-scale
references. No legacy uniform pixels or semantic color masks are used in these
team sets.

## Palette and material contract

- Cyan: `#1DE6EF`
- Violet: `#7D4DFF`
- White: `#F7FCFF`
- Skin, football leather, facemasks, gloves, tape, and cleats remain independent
  natural or neutral materials.

Primary offense uses a cyan helmet and jersey, violet shoulder panels and
pants, and white numbers, trim, and socks. Primary defense uses a cyan jersey
and pants, violet helmet, shoulder panels, and socks, and white numbers and
trim.

Alternate offense uses a violet helmet and jersey, white shoulder panels and
pants, and cyan numbers, trim, and socks. Alternate defense uses a violet
jersey and pants, white helmet, shoulder panels, and socks, and cyan numbers
and trim.

## Locked source contract

Each jersey directory contains the three approved full-color source strips:

- `qb-strip.png`: 2172 x 724, four 543-pixel slots; rear-facing number 7;
  idle, aim, throw, recovery.
- `receiver-strip.png`: 3620 x 724, ten 362-pixel slots; right-facing number
  11; four run frames, catch, four carry frames, touchdown.
- `defender-strip.png`: 2103 x 748, five 420-pixel slots plus three transparent
  compatibility columns; square/front-facing number 24; four run frames and
  interception.

The runtime processor uses one shared scale per role and writes lossless WebP
frames on a 384 x 512 transparent canvas with bottom-center anchor `[192, 496]`.
Receiver left frames are exact mirrors. Defender direction pairs reuse the
same square-facing art so the jersey number is never reversed. The universal
official frames remain in the shared character directory and are not copied
into a team jersey set.

## Deterministic runtime generation

Primary:

```bash
python3 ios/Tools/process-pixel-character-strips.py \
  --qb-strip ios/AssetSources/PixelCharacters/teams/nova_city_comets/primary/qb-strip.png \
  --receiver-strip ios/AssetSources/PixelCharacters/teams/nova_city_comets/primary/receiver-strip.png \
  --defender-strip ios/AssetSources/PixelCharacters/teams/nova_city_comets/primary/defender-strip.png \
  --uniform-only \
  --output-dir ios/PocketVector/Resources/GameAssets/characters/teams/nova_city_comets/primary \
  --force
```

Alternate:

```bash
python3 ios/Tools/process-pixel-character-strips.py \
  --qb-strip ios/AssetSources/PixelCharacters/teams/nova_city_comets/alternate/qb-strip.png \
  --receiver-strip ios/AssetSources/PixelCharacters/teams/nova_city_comets/alternate/receiver-strip.png \
  --defender-strip ios/AssetSources/PixelCharacters/teams/nova_city_comets/alternate/defender-strip.png \
  --uniform-only \
  --output-dir ios/PocketVector/Resources/GameAssets/characters/teams/nova_city_comets/alternate \
  --force
```

Each command produces exactly 34 runtime frames. Exact ImageGen prompts and raw
chroma outputs are retained under `generation/`. The approved full-set review
and enlarged quarterback material inspection are retained under `QA/`.

## Runtime integration boundary

Art owns these source and shipping raster files. Gameplay must select the
appropriate `characters/teams/nova_city_comets/{primary|alternate}` prefix from
the resolved team and jersey IDs and load the baked frame without runtime
uniform projection. That selection and preprocessing behavior is
Technical-owned.
