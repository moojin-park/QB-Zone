# Main-menu design QA

Date: 2026-07-17

## Scope

- Reference: `ios/AssetSources/Menu/menu-concept-reference-original.png`
- Phone master: `ios/AssetSources/Menu/menu-high-mesa-helions-phone-v1.png`
- iPad master: `ios/AssetSources/Menu/menu-high-mesa-helions-pad-v1.png`
- Implementation: `ios/PocketVector/UI/MainMenuView.swift`
- Visual direction: one fixed High Mesa Helions menu for every selected gameplay team
- Form factors: compact iPhone, regular iPhone, and 13-inch iPad landscape

The Product Design workflow normally writes `design-qa.md` at repository root.
That path is PM-owned in this repository, so this Art-owned evidence record lives
with the menu source instead.

## Final evidence

- Supplied concept and regular-iPhone implementation comparison:
  `ios/AssetSources/Menu/QA/menu-concept-vs-implementation-v4.png`
- iPad source and simulator implementation comparison:
  `ios/AssetSources/Menu/QA/menu-ipad-source-vs-implementation-v4.png`
- Compact iPhone (iPhone 17e):
  `ios/AssetSources/Menu/QA/menu-compact-iphone-high-mesa-v4.png`
- Regular iPhone (iPhone 17 Pro):
  `ios/AssetSources/Menu/QA/menu-regular-iphone-high-mesa-v4.png`
- iPad, High Mesa selected (iPad Pro 13-inch):
  `ios/AssetSources/Menu/QA/menu-ipad-high-mesa-selected-v4.png`
- iPad, Nova selected while menu remains High Mesa:
  `ios/AssetSources/Menu/QA/menu-ipad-nova-static-high-mesa-v4.png`

The iPad uses a separately authored 1448 x 1086 plate rather than a stretched
or blurred phone letterbox. The selected-team proof was exercised in the
simulator by selecting Nova City Comets and High Mesa Helions through the
existing team-selection route and returning to the menu after each selection.

## Corrections verified

1. The marquee, detailed characters, stadium, dimensional Play control, and
   chrome closely follow the supplied concept.
2. Both stadium banners read `HIGH MESA` / `HELIONS` and use one consistent
   solar-mesa mark. No Nova City or Comets residue remains.
3. The quarterback jersey and Team & Locker jersey icon both clearly read
   `10`; neither phone nor iPad artwork contains a residual `12`.
4. Skin remains warm, footballs remain brown and cream, steel remains neutral,
   turf remains green, and floodlights remain white. No full-scene tint or mask
   contaminates independent material colors.
5. Achievements, Store, Settings, and the icon-first coin value share one
   compact corner row. Privacy and Support remains inside Settings.
6. Personal Best is a live-value scoreboard centered between Team & Locker and
   Leaderboard at the same compact scale previously used by the sideline board.
7. The title, tagline, Play label, banners, uniforms, and team marks are fully
   rendered artwork. Runtime SwiftUI supplies only live values and hit targets.
8. The menu remains visually High Mesa when the selected gameplay team changes.
   There is no Core Image renderer, mask, dynamic team banner, palette swap, or
   selected-team asset lookup.
9. Play, Locker, and Leaderboard retain their original routes and large mapped
   hotspots. Utility actions retain distinct 44 x 44 point targets.

## Independent review

Three independent reviewers audited the final assets, implementation, and
screenshots.

- Visual fidelity and color separation: no P0, P1, P2, or P3 findings; passed.
- Behavior and accessibility code review: no P0, P1, or P2 findings; passed.
- Asset/catalog/package review: no P0, P1, P2, or P3 findings; passed.

The behavior reviewer identified one stale Nova proof capture made before the
final utility-row adjustment. The proof was recaptured from the final build and
the stale file was replaced before handoff.

## Verification

- Phone source/runtime dimensions: 1847 x 851; passed.
- iPad source/runtime dimensions: 1448 x 1086; passed.
- Phone source/runtime SHA-256:
  `1a8f6d2c6f81157b291d92b3f84261b6b391496e8bff8525351598ba446358d3`;
  matched.
- iPad source/runtime SHA-256:
  `42ef0a17c24cd741004ec8a2b3ef15d84a8d0c5acb960c9acc1cca1c307aff80`;
  matched.
- Asset-catalog JSON validation with `jq`: passed.
- Asset-catalog compilation and simulator build: passed.
- Compact-iPhone, regular-iPhone, and iPad screenshots: passed.
- Existing menu routes and selected-team static-art behavior exercised in the
  iPad simulator: passed.
- Unsigned generic-iOS Release archive: passed.
- `git diff --check`: passed.
- Changed-path ownership audit: Art-owned paths only.
- Focused native-asset manifest test: blocked by the pre-existing bundling of
  `PocketVector/Resources/GameAssets/AGENTS.md`, which is not declared in
  `native-assets.json`. The menu asset catalog does not change that inventory;
  correcting the project resource membership is PM-owned.

Final main-menu result: passed. The unrelated repository manifest gate requires
PM follow-up before release integration.
