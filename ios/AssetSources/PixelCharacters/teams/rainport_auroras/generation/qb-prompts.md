# Rainport Auroras quarterback rebuild prompts

Execution path: built-in ImageGen. `qb-strip.png` from the legacy shared set was supplied only as a pose/layout/silhouette reference. The approved Nova City strip for the matching uniform was supplied only as a production-fidelity reference. Every character pixel was newly authored on a flat chroma key, then the key was removed locally with the ImageGen skill helper.

## Primary

```text
Use case: stylized-concept
Asset type: review-only production candidate pixel-art quarterback animation strip for Pocket Vector iOS
Input images: Image 1 is the legacy quarterback strip and is reference only for exact pose sequence, layout, rear-facing orientation, silhouette family, equipment placement, football placement, relative scale, and animation timing. Image 2 is the approved Nova City primary quarterback and is reference only for the required high-resolution pixel-art quality, clean materials, crisp cluster logic, stable proportions, and authored finish. Do NOT reuse, recolor, trace, mask, or preserve pixels from either reference. Redraw every character pixel from scratch as a distinct Rainport Auroras player.

Create exactly one horizontal row of exactly four equal slots showing the same fictional American-football quarterback from the rear in this exact sequence: 1 idle ready stance with arms down; 2 aim/cocked stance holding the football beside the right ear with left hand raised; 3 throw/release follow-through with throwing arm extended up-right and the football airborne above/right; 4 recovery follow-through leaning slightly right with right arm extended horizontally. Keep the character centered consistently within each slot, same bottom anchor, same body proportions, same size, same helmet, pads, gloves, pants, socks, cleats, and readable block number 7 on the back. No cropped limbs or football.

Uniform: Rainport Auroras PRIMARY, fully authored opaque colors. Helmet and jersey deep teal #0B3A4A. Shoulder panels and pants lime #9DD643. Back number 7, trim, waistband accents, and socks cool white #E5F2EA. Facemask and cleats neutral graphite. Gloves neutral white with restrained team-color trim. Natural warm skin. Brown leather football with white laces. Use these defined colors as the dominant local colors with darker same-family shadows and restrained lighter highlights only; never let one material's color spill into another material.

Style: high-resolution pixel art game sprite matching the approved Nova production fidelity; crisp intentional pixel clusters; strong readable silhouette; restrained arcade shading; coherent fixed-size pixel clusters; production asset, not concept art. Helmet, jersey, shoulder panels, pants, socks, gloves, facemask, cleats, skin, and football must remain independently colored and materially distinct. Pants and jersey must be clean continuous authored surfaces with no speckles, mottling, camouflage, stains, random colored islands, mapped-color patches, glow, hue wash, or chromatic contamination. Number 7 must be geometrically clean and consistent in all four frames.

Backdrop: perfectly flat solid #FF00FF chroma-key background filling every empty pixel. One uniform color only—no shadows, gradients, texture, floor, reflection, lighting variation, halos, or chroma-key color in the player. Generous separation around each sprite.

Canvas/layout constraints: 2172 by 724 pixels, very wide 3:1 aspect ratio, exactly four equal horizontal frame cells of 543 by 724 pixels, no dividers, no labels, no text other than jersey number 7, no scenery, no duplicate people, no poster composition, no watermark. Preserve Image 1's relative per-frame placement as closely as possible while matching Image 2's finish quality.
```

Canonical built-in output:

```text
/Users/andypark/.codex/generated_images/019f7c71-421d-79e0-97fb-bf4d737d67bc/exec-7b5401e3-c539-4756-8cc1-5c51ffd11798.png
```

## Alternate

```text
Use case: stylized-concept
Asset type: review-only production candidate pixel-art quarterback animation strip for Pocket Vector iOS
Input images: Image 1 is the legacy quarterback strip and is reference only for exact pose sequence, layout, rear-facing orientation, silhouette family, equipment placement, football placement, relative scale, and animation timing. Image 2 is the approved Nova City alternate quarterback and is reference only for the required high-resolution pixel-art quality, clean materials, crisp cluster logic, stable proportions, and authored finish. Do NOT reuse, recolor, trace, mask, or preserve pixels from either reference. Redraw every character pixel from scratch as a distinct Rainport Auroras player.

Create exactly one horizontal row of exactly four equal slots showing the same fictional American-football quarterback from the rear in this exact sequence: 1 idle ready stance with arms down; 2 aim/cocked stance holding the football beside the right ear with left hand raised; 3 throw/release follow-through with throwing arm extended up-right and the football airborne above/right; 4 recovery follow-through leaning slightly right with right arm extended horizontally. Keep the character centered consistently within each slot, same bottom anchor, same body proportions, same size, same helmet, pads, gloves, pants, socks, cleats, and readable block number 7 on the back. No cropped limbs or football.

Uniform: Rainport Auroras ALTERNATE, fully authored opaque colors. Helmet and jersey lime #9DD643. Shoulder panels and pants cool white #E5F2EA. Back number 7, trim, waistband accents, and socks deep teal #0B3A4A. Facemask and cleats neutral graphite. Gloves neutral white with restrained team-color trim. Natural warm skin. Brown leather football with white laces. Use these defined colors as the dominant local colors with darker same-family shadows and restrained lighter highlights only; never let one material's color spill into another material.

Style: high-resolution pixel art game sprite matching the approved Nova production fidelity; crisp intentional pixel clusters; strong readable silhouette; restrained arcade shading; coherent fixed-size pixel clusters; production asset, not concept art. Helmet, jersey, shoulder panels, pants, socks, gloves, facemask, cleats, skin, and football must remain independently colored and materially distinct. Pants and jersey must be clean continuous authored surfaces with no speckles, mottling, camouflage, stains, random colored islands, mapped-color patches, glow, hue wash, or chromatic contamination. Number 7 must be geometrically clean and consistent in all four frames.

Backdrop: perfectly flat solid #FF00FF chroma-key background filling every empty pixel. One uniform color only—no shadows, gradients, texture, floor, reflection, lighting variation, halos, or chroma-key color in the player. Generous separation around each sprite.

Canvas/layout constraints: 2172 by 724 pixels, very wide 3:1 aspect ratio, exactly four equal horizontal frame cells of 543 by 724 pixels, no dividers, no labels, no text other than jersey number 7, no scenery, no duplicate people, no poster composition, no watermark. Preserve Image 1's relative per-frame placement as closely as possible while matching Image 2's finish quality.
```

Canonical built-in output:

```text
/Users/andypark/.codex/generated_images/019f7c71-421d-79e0-97fb-bf4d737d67bc/exec-0e5cf44a-4198-4eb6-adec-0443a136103d.png
```

## QA/iteration notes

The built-in alternate chroma output was 2173×724. Its untouched raw output is preserved in `qb-alternate-chroma.png`; after key removal, one empty right-edge column was cropped to enforce the canonical 2172×724 four-slot contract. No character pixels were cropped.
