# Design QA — Option 3 Run Results

## Source of truth

- Approved reference: `/Users/andypark/.codex/generated_images/019f7182-19d5-7d40-8e97-6ebea8ba5808/exec-3898364b-12e0-4c3c-8d9f-eb5e5aeb86cf.png`
- Implementation: `ios/PocketVector/UI/RunResultsView.swift`
- State: new personal best, 12,500 score, 14 attempts, 10 completions,
  71% accuracy, 3 touchdowns, 277 coins, optional-bonus progress 2 of 5.

## Responsive evidence

- Compact iPhone landscape: `/tmp/pocket-vector-results-option3-final/compact-iphone-landscape.png`
- Regular iPhone landscape: `/tmp/pocket-vector-results-option3-final/regular-iphone-landscape.png`
- iPad landscape: `/tmp/pocket-vector-results-option3-final/ipad-landscape.png`
- Compact iPhone Accessibility 5: `/tmp/pocket-vector-results-option3-final/compact-iphone-accessibility5.png`
- Regular iPhone Accessibility 5: `/tmp/pocket-vector-results-option3-final/regular-iphone-accessibility5.png`
- iPad Accessibility 5: `/tmp/pocket-vector-results-option3-final/ipad-accessibility5.png`

All Accessibility 5 content and both actions are contained in one vertical
scroll view. Standard layouts keep both actions and all result data inside the
visible safe area.

## Comparison evidence

- Full reference/implementation comparison:
  `/tmp/pocket-vector-results-option3-final-comparison/full-comparison.png`
- Focused stat and coin wing comparison:
  `/tmp/pocket-vector-results-option3-final-comparison/panels-comparison.png`

The first coded pass used generic stroked panels and was rejected at P1 for
insufficient hardware fidelity. The post-fix pass uses authored marquee, wing,
and bonus-rail bezel rasters with clipped steel corners, bolts, cyan status
lights, inner navy materials, and controlled shadows. It restores the approved
scoreboard silhouette and density while preserving responsive SwiftUI content.

## Findings

- Resolved P1: generic panel borders did not match the approved equipment
  frames. Replaced them with authored lossless pixel-art bezels.
- Resolved P1: compact-iPhone marquee crowded its score and label. Reflowed it
  into a horizontal compact composition without changing the regular or iPad
  hierarchy.
- Resolved P2: stat icons were initially generic system marks. Replaced all four
  with dedicated neutral pixel-art assets; currency uses the exact main-menu
  coin asset.
- Resolved P2: the iPad Accessibility 5 two-column stat grid created awkward
  word fragments. Accessibility layouts now use a single-column semantic stat
  list at every viewport.
- Open P3: on compact iPhone at Accessibility 5, the score marquee is taller
  than the initial viewport. The complete marquee, all details, and both actions
  remain reachable in the single screen-level scroll view.
- Open P1 integration dependency: app presentation currently replaces gameplay
  with Results. PM must retain a frozen, noninteractive final gameplay surface
  (or supply its final frame) so the actual completed play remains beneath the
  transparent overlay. The Art view uses the same registered team field layers
  as a visual fallback and does not fabricate gameplay actors.
- Open P1 integration dependency: Results presentation exposes only aggregate
  earned coins. The current-version display reconciles existing authoritative
  reward totals, but Technical must expose version-aware line items and PM must
  pass them through before this receipt can be considered a permanent economy
  contract.

## Verification

- Focused Results presentation, coordinator, replay, natural-completion, and
  native asset-manifest tests passed.
- Debug iPhone simulator build passed.
- New asset-catalog JSON files validated and all authored PNG masters were
  confirmed as RGBA lossless sources.

## Final result

**Blocked for integrated acceptance.** The Art-owned screen and assets pass the
visual comparison, responsive layout, accessibility reflow, build, and focused
tests. Final product acceptance requires the two foreign-domain integration
dependencies listed above.
