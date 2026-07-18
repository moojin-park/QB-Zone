# Main-menu design QA

Date: 2026-07-17

## Scope

- Reference: `ios/AssetSources/Menu/menu-concept-reference-original.png`
- Phone master: `ios/AssetSources/Menu/menu-high-mesa-helions-phone-v1.png`
- iPad shipping master: `ios/AssetSources/Menu/menu-high-mesa-helions-pad-v2.png`
- Implementation: `ios/PocketVector/UI/MainMenuView.swift`
- Form factors: compact iPhone, regular iPhone, and 13-inch iPad landscape
- State: fixed High Mesa menu, zero and five-digit Personal Best values, and
  confirmed-plus-pending coin balance

The Product Design workflow normally writes `design-qa.md` at repository root.
That surface is outside the Art workstream, so this Art-owned evidence record
lives with the menu source instead.

## Final evidence

- Supplied concept and regular-iPhone implementation comparison:
  `ios/AssetSources/Menu/QA/menu-concept-vs-implementation-v6.png`
- iPad source and implementation comparison:
  `ios/AssetSources/Menu/QA/menu-ipad-source-vs-implementation-v6.png`
- Focused regular-iPhone v5-to-v6 HUD comparison:
  `ios/AssetSources/Menu/QA/menu-phone-v5-vs-v6-hud.png`
- Focused iPad v5-to-v6 HUD comparison:
  `ios/AssetSources/Menu/QA/menu-ipad-v5-vs-v6-hud.png`
- Compact iPhone (iPhone 17e):
  `ios/AssetSources/Menu/QA/menu-compact-iphone-high-mesa-v6.png`
- Regular iPhone (iPhone 17 Pro):
  `ios/AssetSources/Menu/QA/menu-regular-iphone-high-mesa-v6.png`
- iPad (iPad Pro 13-inch):
  `ios/AssetSources/Menu/QA/menu-ipad-high-mesa-v6.png`

The focused comparisons are required because the score-to-Play clearance and
utility-icon scale are too small to judge reliably from the full-screen sheets
alone.

## Comparison history

### V5 findings

- P2 layout: the phone Personal Best plate visibly tucked into the bottom Play
  bezel instead of reading as the next element in the vertical stack.
- P2 hierarchy: Personal Best remained underweighted, especially on iPad.
- P2 accessibility: the iPad utility artwork remained 28 points and looked too
  small for the 13-inch composition even though its target met 44 points.

### V6 fixes

- Phone Personal Best increased from 224 x 130 to 260 x 150 source pixels and
  moved lower. Its visible housing now clears the Play bezel.
- iPad Personal Best increased from 182 x 105 to 240 x 139 source pixels and
  moved lower.
- Phone utility art is bottom-aligned at 24 points inside unchanged 44 x 44
  point targets, making the row read lower without violating the compact safe
  boundary.
- iPad utility art increased from 28 to 36 points inside 52 x 52 point targets
  with 6-point spacing.

### Post-fix evidence

The v6 compact, regular, and iPad captures show clear Play-to-score separation,
no score-to-utility collision, no edge clipping, and a materially more readable
iPad utility row. No actionable P0, P1, or P2 issue remains.

## Required fidelity surfaces

- Fonts and typography: the rendered title, Play lettering, banners, and utility
  artwork remain unchanged. Live Personal Best digits retain the bold monospaced
  treatment and `32,500` fits without truncation.
- Spacing and layout: Play remains dominant; Personal Best is centered to Play;
  Achievements, Store, Settings remain centered below it in that order. Compact
  and regular phone layouts retain complete 44-point targets; iPad uses complete
  52-point targets.
- Colors and tokens: High Mesa orange, navy, glacier-white, neutral steel, skin,
  football leather, turf, and floodlights remain independent. No tint or mask
  was introduced.
- Image quality and asset fidelity: all authored raster assets use nearest-
  neighbor presentation. The 660 x 381 Personal Best runtime raster and utility
  icon rasters retain physical-pixel headroom at the new sizes; no upscaling or
  replacement asset is required.
- Copy and content: `POCKET VECTOR`, `READ THE FIELD. FIRE THE PASS.`, `PLAY`,
  `PERSONAL BEST`, `TEAM & LOCKER`, and `LEADERBOARD` remain unchanged and
  legible. Privacy and Support remain inside Settings.

## Independent review

Three independent reviewers audited the implementation and matched v6 captures.

- Visual hierarchy and color fidelity: no P0, P1, or P2 findings; passed with
  one P3 follow-up noted below.
- Responsive geometry, routes, and accessibility: no P0, P1, P2, or P3
  findings; passed.
- Asset resolution and package scope: no P0, P1, P2, or P3 findings; passed.

## Follow-up polish

- P3: phone utility artwork is 24 points rather than the v5 28 points. This is
  an intentional compact-layout tradeoff: bottom alignment keeps all three
  visuals below the enlarged score plate while preserving separate 44-point
  targets inside the safe boundary. The v6 phone captures remain legible; iPad
  receives the requested accessibility enlargement.

## Verification

- Asset-catalog JSON validation with `jq`: passed.
- Asset-catalog compilation and simulator build: passed.
- Compact-iPhone, regular-iPhone, and iPad simulator screenshots: passed.
- Zero and five-digit Personal Best values: passed.
- Confirmed-plus-pending coin layout: passed.
- `git diff --check`: passed.
- Changed-path ownership audit: Art-owned paths only.
- Focused native-asset manifest test: blocked by the pre-existing bundling of
  `PocketVector/Resources/GameAssets/AGENTS.md`, which is not declared in
  `native-assets.json`. This UI-only revision does not change that inventory;
  correcting the project resource membership is PM-owned.

final result: passed
