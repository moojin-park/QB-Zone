# Nova City Comets quarterback rebuild prompts

Execution path: built-in ImageGen with `qb-strip.png` supplied only as a pose,
layout, silhouette, equipment, and scale reference. The generated background was
removed locally from a flat green key; neither output uses the source strip's
pixels or the gameplay uniform projection.

## Primary

```text
Use case: stylized-concept
Asset type: review-only production candidate pixel-art quarterback animation strip for Pocket Vector iOS
Input image: qb-strip.png is reference only for pose, layout, silhouette, rear-facing orientation, proportions, equipment placement, football placement, relative scale, and animation timing. Do NOT reuse, recolor, trace, mask, or preserve any of its red/white pixels. Rebuild every character pixel from scratch.

Create exactly one horizontal row of exactly four equal slots showing the same fictional American-football quarterback from the rear in this exact sequence: 1 idle ready stance with arms down; 2 aim/cocked stance holding the football beside the right ear with left hand raised; 3 throw/release follow-through with throwing arm extended up-right and the football airborne above/right; 4 recovery follow-through leaning slightly right with right arm extended horizontally. Keep the character centered consistently within each slot, same bottom anchor, same body proportions, same size, same helmet, pads, gloves, pants, socks, cleats, and readable block number 7 on the back. No cropped limbs or football.

Uniform: Nova City Comets PRIMARY, fully authored opaque colors. Helmet and jersey cyan #1DE6EF. Shoulder panels and pants violet #7D4DFF. Back number 7, trim, waistband accents, and socks white #F7FCFF. Facemask and cleats neutral graphite. Natural warm skin. Brown leather football with white laces. Use the defined colors as the dominant local colors with darker same-family shadows and restrained lighter highlights only; never let one material's color spill into another material.

Style: high-resolution pixel art game sprite; crisp intentional pixel clusters; strong silhouette; restrained arcade shading; consistent 1-pixel-style edge logic at the authored scale; production asset, not concept art. Pants and jersey must be clean continuous authored surfaces with no speckles, mottling, camouflage, stains, random colored islands, mapped-color patches, glow, or chromatic contamination. Number 7 must be geometrically clean and consistent in all four frames.

Backdrop: perfectly flat solid #00FF00 chroma-key background filling every empty pixel. One uniform color only—no shadows, gradients, texture, floor, reflection, lighting variation, halos, or green in the player. Generous separation around each sprite.

Canvas/layout constraints: very wide strip with 3:1 aspect ratio, exactly four equal horizontal frame cells, no dividers, no labels, no text other than jersey number 7, no scenery, no duplicate people, no poster composition, no watermark. Preserve the reference's relative per-frame placement as closely as possible.
```

Canonical built-in output:

```text
/Users/andypark/.codex/generated_images/019f7c1a-986a-72e3-b4ff-a6574690b96f/exec-b3bff190-54f0-4fbc-9cd3-0cef98c7905b.png
```

## Alternate

```text
Use case: stylized-concept
Asset type: review-only production candidate pixel-art quarterback animation strip for Pocket Vector iOS
Input image: qb-strip.png is reference only for pose, layout, silhouette, rear-facing orientation, proportions, equipment placement, football placement, relative scale, and animation timing. Do NOT reuse, recolor, trace, mask, or preserve any of its red/white pixels. Rebuild every character pixel from scratch.

Create exactly one horizontal row of exactly four equal slots showing the same fictional American-football quarterback from the rear in this exact sequence: 1 idle ready stance with arms down; 2 aim/cocked stance holding the football beside the right ear with left hand raised; 3 throw/release follow-through with throwing arm extended up-right and the football airborne above/right; 4 recovery follow-through leaning slightly right with right arm extended horizontally. Keep the character centered consistently within each slot, same bottom anchor, same body proportions, same size, same helmet, pads, gloves, pants, socks, cleats, and readable block number 7 on the back. No cropped limbs or football.

Uniform: Nova City Comets ALTERNATE, fully authored opaque colors. Helmet and jersey violet #7D4DFF. Shoulder panels and pants white #F7FCFF. Back number 7, trim, waistband accents, and socks cyan #1DE6EF. Facemask and cleats neutral graphite. Natural warm skin. Brown leather football with white laces. Use the defined colors as the dominant local colors with darker same-family shadows and restrained lighter highlights only; never let one material's color spill into another material.

Style: high-resolution pixel art game sprite; crisp intentional pixel clusters; strong silhouette; restrained arcade shading; consistent 1-pixel-style edge logic at the authored scale; production asset, not concept art. Pants and jersey must be clean continuous authored surfaces with no speckles, mottling, camouflage, stains, random colored islands, mapped-color patches, glow, or chromatic contamination. Number 7 must be geometrically clean and consistent in all four frames.

Backdrop: perfectly flat solid #00FF00 chroma-key background filling every empty pixel. One uniform color only—no shadows, gradients, texture, floor, reflection, lighting variation, halos, or green in the player. Generous separation around each sprite.

Canvas/layout constraints: very wide strip with 3:1 aspect ratio, exactly four equal horizontal frame cells, no dividers, no labels, no text other than jersey number 7, no scenery, no duplicate people, no poster composition, no watermark. Preserve the reference's relative per-frame placement as closely as possible.
```

Canonical built-in output:

```text
/Users/andypark/.codex/generated_images/019f7c1a-986a-72e3-b4ff-a6574690b96f/exec-45b34d28-a99a-4d20-a043-d5bf09d9916e.png
```
