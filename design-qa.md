# Results Retained-Surface Design QA

**Source visual truth**

- `/Users/andypark/.codex/generated_images/019f7182-19d5-7d40-8e97-6ebea8ba5808/exec-3898364b-12e0-4c3c-8d9f-eb5e5aeb86cf.png`

**Implementation evidence**

- Compact iPhone, 667 × 375, completed run: `/tmp/pocket-vector-results-retained-final/compact-iphone-landscape.png`
- Regular iPhone, 874 × 402, completed run: `/tmp/pocket-vector-results-retained-final/regular-iphone-landscape.png`
- iPad, 1376 × 1032, completed run: `/tmp/pocket-vector-results-retained-final/ipad-landscape.png`
- Accessibility 5 top and bottom scroll positions for all three sizes: `/tmp/pocket-vector-results-retained-final/*-accessibility5.png` and `/tmp/pocket-vector-results-retained-final/*-accessibility5-bottom.png`

**State**

- Authoritative run Results over the terminal frame from the actual gameplay renderer.
- Gameplay scene frozen, noninteractive, accessibility-hidden, and free of gameplay HUD and settlement chrome.
- Standard Dynamic Type and Accessibility 5.

**Comparison evidence**

- Full-view normalized iPad comparison: `/tmp/pocket-vector-results-retained-final-comparison/reference-vs-retained-ipad.png`
- Focused central field, panels, and ledger comparison: `/tmp/pocket-vector-results-retained-final-comparison/reference-vs-retained-ipad-focused.png`

**Findings**

- P0: none.
- P1: none.
- P2: none.
- P3: Compact Accessibility 5 wraps `OPTIONAL` as `OPTION-` / `AL`. The full wording, progress, and both actions remain reachable; this is non-blocking polish.
- P3: Frozen player sprites can remain faintly visible through translucent iPad panels. Contrast and text legibility remain strong, and the visible final-play actors reinforce that this is the real retained field.

**Required fidelity surfaces**

- Fonts and typography: monospaced broadcast hierarchy, condensed labels, score emphasis, and gold reward totals match the approved direction. No standard-size truncation is visible. Accessibility 5 preserves semantic scaling and complete action labels.
- Spacing and layout rhythm: marquee, dual wings, center field opening, bonus rail, and actions retain the approved composition across compact iPhone, regular iPhone, and iPad. Accessibility content is one continuous scroll with both actions reachable.
- Colors and visual tokens: midnight panels, steel bezels, cyan status lights, glacier text, and gold rewards remain consistent with the championship UI system.
- Image quality and asset fidelity: the background is a terminal texture captured from the shipping `GameScene`; no synthetic field, placeholder, code-drawn field, or substitute backdrop is present. Pixel assets retain nearest-neighbor rendering.
- Copy and content: `RUN COMPLETE`, final score, Attempts, Completions, Accuracy, Touchdowns, all applicable coin lines, Total, Optional Bonus, Main Menu, and Play Again are complete and correctly ordered.

**Comparison history**

1. P1 evidence defect: the first retained-field capture was gray because hierarchy capture could not read the Metal-backed SpriteKit surface. Fix: capture the shipping `GameScene` texture and compose the transparent Results view over it. Post-fix evidence: all files under `/tmp/pocket-vector-results-retained-final/` show the real field.
2. P1 state mismatch: an intermediate renderer capture still showed the countdown overlay. Fix: advance the renderer naturally through its terminal Results phase and assert the broadcast HUD is hidden before capture. Post-fix evidence: the final compact, regular, and iPad screenshots contain no countdown, scorebug, controls, or settlement chrome.
3. P1 lifecycle defect: hosted verification showed SpriteKit actions could continue after the Results transition. Fix: synchronize the frozen presentation state to the retained `SKView` and `GameScene`. Post-fix verification: `testHostedShellRetainsAndFreezesExactGameSceneThroughResults` passes and confirms exact object identity plus a stopped SKAction.
4. P2 accessibility evidence gap: top-only Accessibility 5 captures did not prove final actions were reachable, and the first compact bottom capture stopped at Main Menu. Fix: add bottom-position evidence and compact scroll clearance. Post-fix evidence: all `*-accessibility5-bottom.png` files show the final action region; compact and regular show complete vertically stacked actions, while iPad shows complete side-by-side actions.

**Implementation checklist**

- [x] Retain one run-ID-keyed gameplay scene through Results.
- [x] Freeze and remove the retained surface from interaction and accessibility.
- [x] Suppress gameplay HUD, pause controls, settlement chrome, and system-gesture deferral.
- [x] Keep Results transparent over the terminal field.
- [x] Preserve Main Menu and Play Again actions.
- [x] Verify standard and Accessibility 5 layouts at all required sizes.

final result: passed
