# Axiom Point Gravitons baked-uniform provenance

## Selected ImageGen sources

| Runtime strip | Selected ImageGen file |
| --- | --- |
| Primary quarterback | `exec-f06d6f2b-d8e6-4272-a3e0-0012d9600356.png` |
| Alternate quarterback | `exec-66b1d9d9-a9a1-43f7-a486-a386aab71f0f.png` |
| Primary receiver | `exec-9e54f33e-9236-4e9f-83b3-110fe9922cc9.png` |
| Alternate receiver | `exec-cc8e1b47-2e98-46e6-9b40-b650ae0cbb80.png` |
| Primary defender | `exec-cce6d39e-29ed-4eca-81da-af93de1b6fad.png` |
| Alternate defender | `exec-8103637b-09b9-4316-80b0-3f64c844cc36.png` |

The selected files were generated with the built-in ImageGen tool. Directly accepted strips were copied to `generation/*-chroma.png`; the two selected receiver sources used the deterministic component placement documented below to restore equal-slot spacing without changing their authored pixels. Each prompt used the generic role strip and matching Nova City Comets primary strip as pose, proportion, pixel-density, and strip-grammar references only. The prompts required new authored pixel art on a flat `#FF00FF` field, exact frame order and numbers 7/11/24, large cell gutters, clean uniform regions, one football per applicable frame, and no logos, masks, stains, holes, fragments, or duplicate equipment.

## Palette mapping

- Team colors: royal blue `#1648B8`, solar yellow `#EFCB32`, frost white `#F4F7FC`.
- Primary offense: royal-blue helmet/jersey, solar-yellow shoulders/pants, frost-white number/trim/socks.
- Alternate offense: solar-yellow helmet/jersey, frost-white shoulders/pants, royal-blue number/trim/socks.
- Primary defense: royal-blue jersey/pants, solar-yellow helmet/shoulders/socks, frost-white number/trim.
- Alternate defense: solar-yellow jersey/pants, frost-white helmet/shoulders/socks, royal-blue number/trim.

## Rejected candidates

- `exec-47068241-6534-4b91-8ee4-3b751261f95e.png` and `exec-49ad9595-3d69-4657-a404-01fedebc89fb.png` were rejected because receiver touchdown frame 10 held both a raised football and an unintended second tucked football. Both complete receiver strips were regenerated rather than retouched.
- `exec-7eb96055-ea5b-4fe1-a6c6-aeaa4091205c.png` was rejected because its primary quarterback included a partial football and normalized substantially smaller than the paired alternate.
- Intermediate receiver candidates `exec-279c71d2-2044-4641-805d-8a9186b71dfe.png` and `exec-43cbd009-42d7-4147-a331-21e972d58d5c.png` were rejected after normalization exposed undersized poses and slot-boundary fragments.

## Deterministic processing and QA

- Chroma extraction: `ios/Tools/extract-flat-pixel-chroma.py` with checked-in defaults and the finalized 512-pixel isolated-debris cutoff.
- Paired normalization: `ios/Tools/normalize-baked-team-strips.py` with one shared scale per primary/alternate role pair and the finalized 512-pixel isolated-artifact cutoff.
- Deterministic receiver spacing: the primary source's ten authored 8-connected pose components were nearest-neighbor scaled by `1.20` and placed into a `2172×724` strip at exact slot centers on baseline `526`; the alternate source's ten authored components were translated without resampling (`1.00` scale) into the same geometry and baseline. Both outputs retain exactly ten complete components with 40–70 pixels of horizontal gutter. No recoloring or despill was used.
- No manual paint, recoloring, masking, or QA-only cleanup is applied.

- Final paired normalization scales: quarterback `0.88366890`, receiver `1.95327103`, defender `0.86352941`.
- Canonical outputs: quarterback `2172×724`, receiver `3620×724`, defender `2103×748`; every canonical strip retains alpha and contains zero visible exact-key `#FF00FF` pixels.
- Runtime export: 34 lossless `384×512` WebPs per uniform, 68 total; independent regeneration was byte-identical to the checked output.
- Visual/component QA: one complete connected player silhouette per frame, with a separate component only for the intentional airborne quarterback football; numbers 7/11/24, frame order, single-ball rules, palette continuity, and primary/alternate distinction pass.
- Review sheet: `../QA/primary-alternate-review.png` (`2048×3780`).
