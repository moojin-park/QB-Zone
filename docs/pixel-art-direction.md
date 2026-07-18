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

- Keep gameplay, score, clock, Adrenaline, pause, and mute controls inside the
  current device safe area. Exit belongs only inside the paused gameplay panel.
- Protect the central throwing lane and receiver crossing space.
- Do not add a separate matchup or team-name capsule during active gameplay;
  the in-scene field treatment already communicates team identity.
- Compact pause panels must remain inside the safe area without covering the
  essential score or control readouts.
- Center `PAUSED` in the panel with `STATS` directly beneath it; omit ornamental
  header taglines that compete with the run information.
- Exit confirmation must provide explicit `KEEP PLAYING` and `END RUN` actions
  on every device class, with the paused controls inaccessible behind it.
- Preserve visible texture-readiness and failure states; never hide a stalled
  preload behind an unresponsive scene.
- Reduced motion must remove ornamental motion without changing simulation.

## Main menu

The main menu is a full-stadium arcade marquee, not a stack of generic app
cards. Its hierarchy is: the stadium-mounted `POCKET VECTOR` marquee and
tagline, large central Play control, flanking QB and coach, then the two bottom
destinations. Personal Best is a compact live-value scoreboard centered between
the two bottom destinations, with Achievements, Store, and Settings in one small
icon row directly below it. Privacy and Support live inside Settings. The
scoreboard and utility row remain subordinate to Play rather than reading as a
third destination card.

The live center stack is responsive rather than uniformly scaled. The phone
scoreboard must visibly clear both the Play bezel and the bottom-aligned compact
utility artwork; keep the utility row inside 44-point targets and above the
landscape bottom safe boundary. The 4:3 iPad layout gives Personal Best more
visual weight and uses larger utility artwork inside 52-point targets so the
controls remain readable and easy to acquire on the larger screen.

The menu has one fixed High Mesa Helions art direction regardless of the
selected gameplay offense. The fully rendered phone and iPad plates author the
ember `#F06A3B`, deep indigo `#2B234D`, and glacier `#D8F0EC` palette directly;
there is no runtime palette replacement, mask, team banner, or team-dependent
asset selection. Skin, football leather, white lettering, steel, turf, and
neutral shadows remain independent materials. A dedicated 4:3 scene is
required for iPad; do not letterbox the phone plate over a blurred enlargement.

- Preserve the concept's dark navy, bright stadium lighting, framed marquee,
  detailed character art, oversized dimensional Play control, and clear
  two-button bottom navigation rhythm.
- Both background banners read `HIGH MESA` / `HELIONS`; the solar-mesa mark is
  used consistently on banners, flags, helmets, and coach apparel.
- The quarterback and Team & Locker jersey icon both wear number `10`.
- Do not place a separate oversized team badge beside the title.
- Coin balance is icon-first and compact: use the coin mark plus value, never a
  large balance card or the word “Coin.” Anchor it to the top-leading safe area
  in a compact, opaque black stadium panel with a crisp ember keyline so the
  balance remains legible against floodlights.
- On the 4:3 iPad plate, preserve the three flagged poles and the far-right bare
  upright while omitting the two empty center poles above the title marquee.
- Keep every interactive control inside landscape safe areas on compact iPhone,
  regular iPhone, and iPad.
- Utility icon art may scale by form factor, but tap targets never drop below
  44 x 44 points and Achievements, Store, Settings retain that reading order.
- Decorative stadium and player layers remain hidden from accessibility; every
  control has a concise label and the Play control includes an action hint.
- Prefer nearest-neighbor scaling for character sprites and high-contrast text
  over fine pixel detail when the compact layout must compress.

## Source and runtime boundaries

Editable sources live under `ios/AssetSources/`; regeneration tools live under
`ios/Tools/`; exact shipping files live under
`ios/PocketVector/Resources/GameAssets/`. Only the runtime directory is bundled.
See `asset-generation.md` for commands and inventory checks.

Every visual change requires focused geometry or presentation tests plus
representative landscape screenshots on compact and regular iPhone sizes and
an iPad before release approval.
