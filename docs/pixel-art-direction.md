# Shipping visual direction

Pocket Vector uses a high-contrast arcade-broadcast presentation: dark navy
surfaces, cyan structure, warm score accents, crisp pixel characters, and
team-specific field identity. Visual changes must remain readable on compact
landscape iPhones without obscuring the playfield.

## Team identity

The launch catalog contains eight original fictional teams. Every team has a
primary and alternate uniform palette, an emblem, a wordmark, and field/HUD
colors. The selected offense controls the field, end zone, scorebug, aim guide,
and player uniform. The randomized opponent controls defender uniforms.

Team identity is data-driven in:

- `ios/PocketVector/Catalog/LaunchTeamCatalog.swift`
- `ios/PocketVector/Presentation/LaunchVisualIdentity.swift`

Do not add real league marks, team names, logos, uniform designs, or other
third-party trade dress.

## Character sprites

The four approved source strips live in
`ios/AssetSources/PixelCharacters/`. Generated runtime frames use a 384 x 512
transparent canvas with a bottom-center anchor at `[192, 496]`.

- Quarterback: four rear-view poses.
- Receiver: four run phases, catch, four carry phases, and touchdown; left
  frames mirror right frames.
- Defender: four run phases and interception; square/front-facing art is reused
  without mirroring the jersey number.
- Official: two wave phases; left frames mirror right frames.

Nearest-neighbor processing and lossless WebP encoding are required. Runtime
uniform recoloring must preserve transparent padding, skin details, authored
shading, helmet structure, and pose silhouettes.

## Field and ball

The checked-in wide stadium plate supplies turf, stands, and authored texture.
SpriteKit draws current sidelines, team end zones, and wordmarks so team identity
is never baked into the base plate. The selected football cosmetic is a runtime
vector/material choice and remains attached to the player across teams.

## HUD and safe areas

- Keep gameplay, matchup, score, clock, Adrenaline, pause, mute, and exit
  controls inside the current device safe area.
- Protect the central throwing lane and receiver crossing space.
- Compact layouts must not overlap the matchup/exit chrome with the Adrenaline
  meter or scorebug.
- Preserve visible texture-readiness and failure states; never hide a stalled
  preload behind an unresponsive scene.
- Reduced motion must remove ornamental motion without changing simulation.

## Source and runtime boundaries

Editable sources live under `ios/AssetSources/`; regeneration tools live under
`ios/Tools/`; exact shipping files live under
`ios/PocketVector/Resources/GameAssets/`. Only the runtime directory is bundled.
See `asset-generation.md` for commands and inventory checks.

Every visual change requires focused geometry or presentation tests plus
representative landscape screenshots on compact and regular iPhone sizes and
an iPad before release approval.
