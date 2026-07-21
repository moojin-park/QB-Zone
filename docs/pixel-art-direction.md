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

Nearest-neighbor processing and lossless WebP encoding are required. Approved
team-specific uniform sets author jersey, pants, helmet, trim, and sock colors
directly into the source art and must be loaded without runtime recoloring,
tinting, or semantic masks. Transparent padding, skin details, authored
shading, helmet structure, and pose silhouettes remain independent materials.
All eight launch teams have primary and alternate baked sets. The shared
generic set is an emergency/development fallback only and is not approved as
the launch presentation for any team.

## Field and ball

The stadium field is a registered 1728 x 768 layer stack. The opaque neutral
base supplies the stadium, stands, lighting, goalpost, and one continuous turf
material. Grass uses one uniform green across the full field; fine same-hue
grain is allowed, but mowing bands, alternating light/dark sections, wedges,
and broad gradients are not. The centered goalpost must meet the rear end-zone
edge at source coordinate `(864, 230)`, never the wall by the stands.

Team identity is supplied by two transparent layers per team: projected
end-zone paint and a distressed midfield emblem painted directly onto the
turf. Both remain free of opaque cover panels. Universal sidelines, goal lines,
yard lines, and hashes render above team paint from
`pixel/field-markings-v1.png`. Every layer shares the exact canvas, origin, and
projection declared in `ios/AssetSources/Field/field-layers-v1.json`.

Runtime layer order is neutral base, selected team paint, universal markings,
then gameplay actors and HUD. The selected football cosmetic remains a runtime
vector/material choice and stays attached to the player across teams.

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

## Championship submenus

Achievements, Coin Store, Team & Locker, Settings, and Choose Your Offense use
one neutral championship-jumbotron system. The fixed shell is near-black navy,
graphite, brushed steel, silver, and glacier white. Thin cool-cyan illumination
is a status detail only; it does not fill primary controls or recolor the shell.
The large Start Run and purchase controls earn hierarchy through scale, depth,
white illumination, and a multi-step steel bezel rather than a launch-team hue.

- No selected-team palette enters the background, title marquee, Back control,
  navigation, generic icon, panel border, or primary action.
- Team colors remain inside team emblems, jersey and football artwork, and the
  three identity swatches shown on team cards.
- Gold is reserved for the exact main-menu coin, prices, achievement points,
  completed rewards, and other genuine reward states.
- Every currency surface reuses `MenuCoinIcon` without tint, masking, redraw,
  or team-color treatment. Visible prices use the coin mark plus the number;
  VoiceOver continues to announce the word “coins.”
- Selected content uses a glacier-white/silver outer border, semantic text or
  icon, and only a thin cyan inner light so selection never depends on color.
- The eight achievement medals and Settings controls use authored raster pixel
  art. Back, disclosure, lock, selected, and play controls use the shared
  authored submenu icon set instead of generic system symbols.
- Native toggles and sliders retain their behavior, accessibility, and hit
  testing. Their surrounding equipment bays and active lights receive the
  Championship treatment.
- Interactive targets remain at least 44 points, titles remain live SwiftUI
  text, and compact-iPhone, regular-iPhone, and iPad landscape layouts keep all
  headers, balances, scrolling content, and primary actions inside safe areas.

## Run Results

Run Results uses a split stadium-scoreboard composition over the completed
field: a centered score marquee, stat wing at leading, coin ledger wing at
trailing, optional-bonus rail, and the existing Main Menu and Play Again
actions. The center lane remains open so the field reads as the continuation
of the run rather than a hard cut to another menu.

- Results panels use translucent championship navy with authored steel bezel
  rasters, clipped corners, bolts, and restrained cyan status lights.
- Attempts, Completions, Accuracy, and Touchdowns use dedicated neutral pixel
  icons; currency continues to use the exact main-menu coin.
- Coin sources appear in settlement order with a gold total. Optional rewarded
  ad coins remain visually separate from the coins won in the completed run.
- Decorative field and hardware are hidden from accessibility. At accessibility
  text sizes the split boards reflow into one scrollable semantic stack with
  both actions reachable.
- The retained final gameplay surface is frozen and noninteractive. A composed
  same-team field-layer background is the visual fallback when no final frame
  is supplied by app presentation.

## Source and runtime boundaries

Editable sources live under `ios/AssetSources/`; regeneration tools live under
`ios/Tools/`; exact shipping files live under
`ios/PocketVector/Resources/GameAssets/`. Only the runtime directory is bundled.
See `asset-generation.md` for commands and inventory checks.

Every visual change requires focused geometry or presentation tests plus
representative landscape screenshots on compact and regular iPhone sizes and
an iPad before release approval.
