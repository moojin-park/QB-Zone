# Main-menu design QA

Date: 2026-07-17

## Scope

- Source: user-supplied Pocket Vector menu concept
- State: fresh-profile Nova City Comets menu, plus persisted High Mesa Helions
- Implementation: `ios/PocketVector/UI/MainMenuView.swift`
- Primary comparison: concept and regular-iPhone implementation rendered at the same 1847 x 849 viewport

The Product Design workflow normally writes `design-qa.md` at repository root.
That path is PM-owned in this repository, so this Art-owned evidence record lives
with the menu source instead.

## Evidence

- Combined concept/final comparison:
  `/tmp/PocketVectorArtEvidence/after/menu-concept-vs-final.png`
- Compact iPhone (iPhone 17e):
  `/tmp/PocketVectorArtEvidence/after/menu-iphone17e-final.png`
- Regular iPhone (iPhone 17 Pro, Nova):
  `/tmp/PocketVectorArtEvidence/after/menu-iphone17pro-nova-final.png`
- Regular iPhone (iPhone 17 Pro, High Mesa):
  `/tmp/PocketVectorArtEvidence/after/menu-iphone17pro-high-mesa-v3.png`
- iPad landscape (iPad Pro 13-inch):
  `/tmp/PocketVectorArtEvidence/after/menu-ipad-pro13-v3.png`

## Review history

The first independent pass found two P2 issues: flexible iPad panels stretched
vertically, and the stadium's team shift was too subtle. The layout was capped
by viewport aspect ratio, team-colored stadium lighting was strengthened, and
dynamic TeamMark/wordmark billboards were added to both sides. A final compact
capture then found a fixed-frame clip; the content frame now expands to its
minimum required height while keeping the iPad cap.

Final independent review:

- P0: none
- P1: none
- P2: none
- P3: side billboards are partly obscured by the device cutout and players;
  the concept coach is represented by an approved second player sprite. Primary
  team identity remains fully readable, so both are accepted deviations.

The final set has no visible clipping, wrapping, unsafe interactive placement,
or hierarchy regression. Nova and High Mesa visibly change marks, wordmarks,
uniforms, accents, billboards, and stadium lighting. Accessibility inspection
confirmed concise control labels and a Play hint; screenshots cannot prove
every Dynamic Type or VoiceOver traversal state.

final result: passed
