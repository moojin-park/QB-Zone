# Nova City Comets receiver rebuild

Review-only, full-color receiver candidates. Nothing in this directory is
bundled or referenced by the runtime.

## Frame contract

- Source strip geometry: 3620 x 724 RGBA.
- Ten 362 x 724 slots, in order: `run-1`, `run-2`, `run-3`, `run-4`,
  `catch`, `carry-1`, `carry-2`, `carry-3`, `carry-4`, `touchdown`.
- Receiver faces right and wears number 11.
- Candidate frames use one shared scale (`1.541657`) and retain the reference
  frame baselines: 534 px for `run-1`, then 551 px for every other frame.

## Primary generation prompt

```text
Use case: stylized-concept
Asset type: review-only production pixel-art animation sprite sheet for a 2D American-football game
Input image: pose/layout/silhouette reference only. Do NOT recolor, trace, retain, composite, or reuse any source pixels. Redraw the character and every material completely from scratch.
Primary request: Create one new horizontal sprite strip containing exactly 10 equal slots in a single row, in the exact order and with the same right-facing posture, silhouette, proportions, equipment placement, football placement, relative character scale, and spacing as the reference: run-1, run-2, run-3, run-4, catch, carry-1, carry-2, carry-3, carry-4, touchdown. The football appears only in catch/carry/touchdown frames exactly as shown by the reference action beats.
Character: Nova City Comets receiver, jersey number 11, consistent identity and body proportions in all frames.
Uniform: authored full-color primary uniform. Helmet and jersey cyan #1DE6EF. Shoulder panels and pants violet #7D4DFF. Number 11, all trim, and socks white #F7FCFF. Facemask and cleats neutral dark graphite. Gloves and athletic tape neutral white. Natural warm skin colors. Brown leather football with white laces. Each material must be cleanly separated and deliberately drawn; no color replacement artifacts.
Style: high-resolution crisp arcade pixel art matching the game, coherent 1-pixel/2-pixel clusters, restrained controlled shading, clean outlines, readable at small scale, production asset rather than concept art.
Canvas: exactly one horizontal row, 10 equal slots, generous padding within each slot. Perfectly flat solid #00FF00 chroma-key background across every unused pixel, with no shadows, gradients, texture, reflections, floor plane, lighting variation, slot dividers, borders, or transparency. Do not use #00FF00 anywhere on the player.
Constraints: exact frame count; no extra or missing figures; no overlap across slots; preserve the reference frame order and postures; right-facing except the front-biased touchdown posture as shown; consistent number 11; stable helmet and anatomy; clean uniform color regions.
Avoid: masking artifacts, mottling, speckles, color spill, dirty pants, dirty jersey, accidental teal/violet pixels on skin or neutral equipment, photorealism, smooth vector art, scenery, labels, text outside jersey numbers, watermark, logo, team name, poster composition.
```

## Alternate generation prompt

The alternate used the same prompt, replacing only the uniform paragraph with:

```text
Uniform: authored full-color alternate uniform. Helmet and jersey violet #7D4DFF. Shoulder panels and pants white #F7FCFF. Number 11, all trim, and socks cyan #1DE6EF. Facemask and cleats neutral dark graphite. Gloves and athletic tape neutral white. Natural warm skin colors. Brown leather football with white laces. Each material must be cleanly separated and deliberately drawn; no color replacement artifacts.
```

## Processing and QA

- Generated with the built-in image-generation tool using
  `receiver-strip.png` only as a pose/layout/silhouette reference.
- Flat chroma was removed with the installed `remove_chroma_key.py` helper,
  using `#00FF00`, soft matte, thresholds 12/220, and despill.
- `normalize_receiver_review.py` detects the ten independently generated
  figures, applies one shared nearest-neighbor scale, and positions them on the
  locked 362 x 724 source slots.
- Geometry: passed for both 3620 x 724 strips.
- Frame count and order: passed; ten nonempty frames in each strip.
- Reference baselines: passed for all twenty frames.
- Chroma leakage: passed; zero visible `#00FF00`-range pixels.
- Existing character-strip processor: passed in dry-run mode for both uniforms
  with nearest-neighbor scaling, lossless WebP round-trip, and mirror-pair
  validation enabled.
- Visual inspection: passed for posture sequence, right-facing direction,
  football progression, natural skin, neutral equipment, clean material
  boundaries, stable number 11, and absence of masking-style spots.

The images in `Raw/`, `Transparent/`, `Normalized/`, and `QA/` remain
review-only until the complete character set is approved and Technical adopts
the baked-asset path contract.
