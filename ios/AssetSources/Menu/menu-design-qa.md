# Main-menu design QA

Date: 2026-07-17

## Scope

- Reference: `ios/AssetSources/Menu/menu-concept-reference-original.png`
- Implementation: `ios/PocketVector/UI/MainMenuView.swift`
- Default state: fresh-profile Nova City Comets
- Alternate state: persisted High Mesa Helions
- Form factors: compact iPhone, regular iPhone, and 13-inch iPad landscape

The Product Design workflow normally writes `design-qa.md` at repository root.
That path is PM-owned in this repository, so this Art-owned evidence record lives
with the menu source instead.

## Final evidence

- Concept and regular-iPhone Nova comparison:
  `ios/AssetSources/Menu/QA/menu-concept-vs-implementation-v3.png`
- Compact iPhone Nova (iPhone 17e):
  `ios/AssetSources/Menu/QA/menu-compact-iphone-nova-v3.png`
- Regular iPhone Nova (iPhone 17 Pro):
  `ios/AssetSources/Menu/QA/menu-regular-iphone-nova-v3.png`
- Regular iPhone High Mesa (iPhone 17 Pro):
  `ios/AssetSources/Menu/QA/menu-regular-iphone-high-mesa-v3.png`
- iPad Nova (iPad Pro 13-inch):
  `ios/AssetSources/Menu/QA/menu-ipad-nova-v3.png`

The side-by-side evidence uses the same 1847 x 851 comparison viewport. The iPad
uses a separately authored 1448 x 1086 plate rather than a blurred phone
letterbox.

## Corrections verified

1. The marquee, detailed characters, stadium, dimensional Play control, and
   chrome closely follow the approved concept.
2. Achievements, Store, and Settings are compact corner controls.
3. Privacy and Support is absent from the menu and remains inside Settings.
4. Currency uses a polished coin icon without the word “Coin.”
5. Currency is a compact corner value, not a full card.
6. Personal Best is a live-value scoreboard integrated into the right sideline.
7. The title is part of the stadium marquee and receives team color.
8. No oversized team emblem sits beside the title.

Nova and High Mesa visibly change the marquee, Play face, flags, banners,
uniforms, equipment highlights, navigation chrome, and stadium lighting. The
final mask preserves character skin, football leather, white lettering, steel,
and neutral shadows. The Play/Locker/Leaderboard hotspots exceed 44 points on
all reviewed geometries; utility actions use distinct 44 x 44 targets.

## Independent review

Final visual review:

- P0: none
- P1: none
- P2: none
- Result: passed

Final asset/package review:

- P0: none
- P1: none
- P2: none after this evidence record was corrected
- Result: passed

Behavior/accessibility review found one P2: the utility press response honored
the system Reduce Motion value but not the app's saved Reduce Motion preference.
The final implementation now combines both values. It also keeps the previous
same-format team render visible while the next asynchronous palette render is
prepared, avoiding a flash of the original orange plate.
The focused recheck reported no remaining P0, P1, or P2 findings; behavior and
accessibility result: passed.

Accepted P3 polish notes: the corner rail partly overlaps the decorative right
banner, the Store icon reads primarily as a football equipment chest, the
trophy crop is less refined than the generated Store and Settings icons, and
the Dynamic Island can cover decorative left-sideline art. The unobstructed left
or right banner retains team identity, and no actionable control or unique live
value is obscured.

## Verification

- Asset-catalog JSON and physical filename validation: passed.
- Source/runtime hashes for phone scene, iPad scene, and trophy: matched.
- Coin and Personal Best alpha/corner validation: passed.
- Final simulator build: passed.
- Unsigned generic-iOS archive: passed.
- Focused native-asset manifest test: blocked by the pre-existing bundling of
  `PocketVector/Resources/GameAssets/AGENTS.md`, which is not declared in
  `native-assets.json`; the menu asset catalog does not change that inventory.
- `git diff --check`: passed.
- Changed-path ownership audit: Art-owned paths only.

Final result: passed.
