# Main-menu design QA

Date: 2026-07-17

## Scope

- Reference: `ios/AssetSources/Menu/menu-concept-reference-original.png`
- Phone master: `ios/AssetSources/Menu/menu-high-mesa-helions-phone-v1.png`
- iPad provenance master: `ios/AssetSources/Menu/menu-high-mesa-helions-pad-v1.png`
- iPad shipping master: `ios/AssetSources/Menu/menu-high-mesa-helions-pad-v2.png`
- Implementation: `ios/PocketVector/UI/MainMenuView.swift`
- Visual direction: one fixed High Mesa Helions menu for every selected gameplay team
- Form factors: compact iPhone, regular iPhone, and 13-inch iPad landscape

The Product Design workflow normally writes `design-qa.md` at repository root.
That path is PM-owned in this repository, so this Art-owned evidence record lives
with the menu source instead.

## Final evidence

- Supplied concept and regular-iPhone implementation comparison:
  `ios/AssetSources/Menu/QA/menu-concept-vs-implementation-v5.png`
- iPad source and simulator implementation comparison:
  `ios/AssetSources/Menu/QA/menu-ipad-source-vs-implementation-v5.png`
- Focused iPad pole-removal comparison:
  `ios/AssetSources/Menu/QA/menu-ipad-pole-removal-v5.png`
- Compact iPhone (iPhone 17e):
  `ios/AssetSources/Menu/QA/menu-compact-iphone-high-mesa-v5.png`
- Regular iPhone (iPhone 17 Pro):
  `ios/AssetSources/Menu/QA/menu-regular-iphone-high-mesa-v5.png`
- iPad (iPad Pro 13-inch):
  `ios/AssetSources/Menu/QA/menu-ipad-high-mesa-v5.png`

The compact capture exercises a five-digit Personal Best and confirmed-plus-
pending coin state. The regular-iPhone and iPad captures exercise the zero
balance and zero Personal Best states.

## Corrections verified

1. Personal Best is approximately 18 percent larger than the prior placement
   and remains centered between Team & Locker and Leaderboard. It is visually
   subordinate to Play and does not read as a third destination button.
2. Achievements, Store, and Settings form one centered icon row directly below
   Personal Best in that order. The artwork renders at 28 points while every
   action retains its own 44 x 44 point target.
3. Coin balance is separated from the utility actions and anchored to the
   top-leading safe area. Its compact near-black panel, black outer border, and
   ember inner keyline remain readable against both sky and floodlight bloom.
4. The iPad v2 plate removes only the two bare center pole assemblies above the
   title marquee. All three flagged poles and the far-right bare upright remain.
   No pixels outside the two approved removal regions changed from v1.
5. The marquee, detailed characters, stadium, dimensional Play control, banners,
   number `10` jerseys, team logos, and independent material colors remain
   unchanged. There is no full-scene tint, mask, or dynamic team palette.
6. Play, Locker, Leaderboard, Achievements, Store, and Settings retain their
   existing actions, accessible names, and large hit targets. Privacy and
   Support remain inside Settings.

## Independent review

Three independent reviewers audited the final assets, implementation, and v5
simulator captures.

- Visual fidelity and color separation: no P0, P1, P2, or P3 findings; passed.
- Behavior, safe-area geometry, and accessibility: no P0, P1, or P2 findings;
  passed.
- Asset/catalog/package integrity: no P0, P1, P2, or P3 findings; passed.

## Verification

- Phone source/runtime dimensions: 1847 x 851; passed.
- iPad v2 source/runtime dimensions: 1448 x 1086; passed.
- iPad v2 is 8-bit sRGB PNG, non-interlaced, without alpha; passed.
- Phone source/runtime SHA-256:
  `1a8f6d2c6f81157b291d92b3f84261b6b391496e8bff8525351598ba446358d3`;
  matched.
- iPad v2 source/runtime SHA-256:
  `0c6d013086641ce5f6a1659fe5c33e2d806bf5012ed74110bd4004a6658557c0`;
  matched.
- V1-to-v2 pixel comparison outside approved removal regions: zero changed
  pixels; passed.
- Asset-catalog JSON validation with `jq`: passed.
- Asset-catalog compilation and simulator build: passed.
- Compact-iPhone, regular-iPhone, and iPad simulator screenshots: passed.
- Zero, five-digit Personal Best, and confirmed-plus-pending coin layouts:
  passed.
- Unsigned generic-iOS Release archive: passed.
- `git diff --check`: passed.
- Changed-path ownership audit: Art-owned paths only.
- Focused native-asset manifest test: blocked by the pre-existing bundling of
  `PocketVector/Resources/GameAssets/AGENTS.md`, which is not declared in
  `native-assets.json`. The menu asset catalog does not change that inventory;
  correcting the project resource membership is PM-owned.

final result: passed
