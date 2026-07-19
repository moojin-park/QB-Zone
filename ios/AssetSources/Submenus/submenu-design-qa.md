# Theme 3 Submenu Design QA

The QA report is stored with the Art-owned submenu sources instead of the
repository root because the Pocket Vector collaboration contract reserves root
and release surfaces for the Project/Release PM.

## Comparison Target

- Source visual truth: `/Users/andypark/.codex/generated_images/019f7182-19d5-7d40-8e97-6ebea8ba5808/exec-df4cdc9e-aec5-4c41-93d4-133e0af165a7.png`
- Primary implementation screenshot: `/tmp/pocket-vector-submenus-theme3-20260719/compact/choose-offense-landscape.png`
- Responsive implementation screenshots:
  - `/tmp/pocket-vector-submenus-theme3-20260719/regular/choose-offense-final-upright.png`
  - `/tmp/pocket-vector-submenus-theme3-20260719/ipad/choose-offense-final-landscape-v2.png`
  - `/tmp/pocket-vector-submenus-theme3-20260719/ipad/achievements-final-landscape-v2.png`
  - `/tmp/pocket-vector-submenus-theme3-20260719/ipad/store-final-landscape-v2.png`
  - `/tmp/pocket-vector-submenus-theme3-20260719/ipad/settings-final-landscape-v2.png`
  - `/tmp/pocket-vector-submenus-theme3-20260719/ipad/team-locker-final-landscape-v3.png`
- Primary viewport: compact iPhone landscape, 2532 × 1170 pixels. The source
  was normalized to the same 2.164:1 content aspect ratio.
- Additional viewports: regular iPhone landscape, 2622 × 1206 pixels; iPad
  landscape, 2752 × 2064 pixels.
- State: authenticated local profile with team catalog loaded, Rainport Auroras
  selected on the regular-iPhone and iPad captures, real ownership/price data,
  confirmed coin balance, and a pending-coin value where persisted test data
  supplied one. The source's sample team names and six-card content are treated
  as visual direction rather than production copy.

## Evidence

- Full-view comparison:
  `/tmp/pocket-vector-submenus-theme3-20260719/design-qa/choose-offense-reference-vs-final.png`
- Focused offense-footer comparison:
  `/tmp/pocket-vector-submenus-theme3-20260719/design-qa/choose-offense-footer-focus.png`
- Additional compact-iPhone screens:
  - `/tmp/pocket-vector-submenus-theme3-20260719/compact/achievements-landscape.png`
  - `/tmp/pocket-vector-submenus-theme3-20260719/compact/store-landscape.png`
  - `/tmp/pocket-vector-submenus-theme3-20260719/compact/team-locker-landscape.png`
  - `/tmp/pocket-vector-submenus-theme3-20260719/compact/settings-landscape.png`
  - `/tmp/pocket-vector-submenus-theme3-20260719/compact/settings-scrolled-landscape.png`
- Additional regular-iPhone screens:
  - `/tmp/pocket-vector-submenus-theme3-20260719/regular/achievements-final-upright.png`
  - `/tmp/pocket-vector-submenus-theme3-20260719/regular/settings-final-upright.png`

## Findings

No actionable P0, P1, or P2 differences remain.

### Fonts and Typography

The implementation retains the source's condensed broadcast-scoreboard
hierarchy using heavy monospaced system display text, hard offset shadows,
uppercase section labels, and smaller utility copy. The Swift type scales fit
compact iPhone, regular iPhone, and iPad without title wrapping or persistent
control truncation. Using system text instead of a bundled display font is an
intentional accessibility and shipping constraint; the weight, tracking, and
shadow treatment preserve the approved character.

### Spacing and Layout Rhythm

The centered title marquee, symmetric back/balance slots, equipment-panel
frames, card rhythm, and equipped-action footer visibly follow the reference.
Compact layouts preserve 44-point minimum controls. The iPad uses adaptive
two-column achievement/store content, two settings panels, a 4 × 2 locker team
grid, and a 3-column offense grid to avoid an underscaled phone layout. No
persistent control clips or collides with the safe area.

### Colors and Visual Tokens

The shell is team-neutral: championship navy/graphite faces, glacier-white
type, brushed-silver borders, and restrained cyan status illumination. Gold is
reserved for currency and reward values. Team colors are confined to team
marks, uniforms, and identity swatches. Start Run is neutral white/cyan rather
than borrowing the selected team's palette.

### Image Quality and Asset Fidelity

All non-standard controls, achievement marks, and Settings symbols use authored
pixel-art raster assets. Images use nearest-neighbor interpolation and retain
transparent edges without chroma halos. Currency uses the existing untinted,
unmasked `MenuCoinIcon` from the main menu, including store stacks and prices.
The neutral stadium backdrop stays sharp at the reviewed landscape sizes.

### Copy and Content

Production team names, ownership states, prices, achievement counts, store
packs, Settings labels, and offense-selection copy are preserved. Privacy and
Support remains inside Settings. The implementation shows all eight real teams,
so compact iPhone intentionally scrolls beyond the six-card sample mock.

## Comparison History

1. Initial compact implementation: the title was undersized, team cards were
   too tall, and the equipped jersey was absent from the footer. The title was
   enlarged, cards were compacted, and the real equipped jersey was added.
   Post-fix evidence:
   `/tmp/pocket-vector-submenus-theme3-20260719/design-qa/choose-offense-reference-vs-final.png`.
2. Static accessibility/layout review: the balance could intrude into the
   centered title at large pending values, and locked locker teams lacked an
   explicit accessibility value. The header was rebuilt as symmetric fixed
   slots with scalable balance copy, and locker cards now report selected,
   owned, or locked-with-price values. Post-fix evidence:
   `/tmp/pocket-vector-submenus-theme3-20260719/compact/choose-offense-landscape.png`.
3. Initial iPad review: phone-density grids and controls underused the canvas.
   The header, cards, icons, grids, panels, and content bounds were expanded for
   the regular vertical size class. Post-fix evidence:
   `/tmp/pocket-vector-submenus-theme3-20260719/ipad/choose-offense-final-landscape-v2.png`.
4. Final independent review: the supplied regular-iPhone files were upside
   down, while iPad Team & Locker used a sparse horizontal rail with avoidable
   label truncation. Upright regular captures replaced the artifacts; the iPad
   locker now uses a 4 × 2 team grid and larger equipment cards with complete
   names. Post-fix evidence:
   `/tmp/pocket-vector-submenus-theme3-20260719/regular/choose-offense-final-upright.png`
   and
   `/tmp/pocket-vector-submenus-theme3-20260719/ipad/team-locker-final-landscape-v3.png`.
5. Centered-title follow-up: the original `HStack` centered Back, the marquee,
   and any accessory as one bundle, allowing accessory-free screens to shift
   the marquee right of the viewport center. The marquee now occupies an
   independent centered layer while Back and the reserved accessory region sit
   in a separate edge-control layer. Focused before/after evidence:
   `/tmp/pocket-vector-submenu-title-center-20260719/screenshots/header-before-after.png`.
   Source-to-final full-view evidence:
   `/tmp/pocket-vector-submenu-title-center-20260719/design-qa/source-vs-centered-title.png`.

## Follow-up Polish

- P3: The reference uses heavier riveted outer frames than the reusable SwiftUI
  shell. The lighter steel frame is accepted because it improves content space
  and remains consistent across five production screens.
- P3: iPad's 4:3 viewport exposes more atmospheric stadium floor than the wide
  mock. This is an intentional responsive crop, not missing content.

## Verification Summary

- Primary interactions exercised: back navigation, opening each submenu,
  scrolling compact Settings to Privacy & Support, selecting the offense route,
  and inspecting all persistent controls through the accessibility hierarchy.
- Exact coin identity, neutral token usage, icon sharpness, safe-area
  containment, and compact/regular/iPad density were reviewed visually.
- Independent final visual review found no actionable P0, P1, or P2 issues.
- Focused presentation/navigation/resource tests passed at
  `/tmp/pocket-vector-submenus-theme3-20260719/final-after-locker-focused.xcresult`.
- The unsigned Release archive passed at
  `/tmp/pocket-vector-submenus-theme3-20260719/PocketVector-submenus-final.xcarchive`.
- The centered-title follow-up passed on compact iPhone, regular iPhone, and
  iPad with marquee centers at the exact viewport centers and no title/control
  overlap. Focused tests passed at
  `/tmp/pocket-vector-submenu-title-center-20260719/title-center-tests.xcresult`.

final result: passed
