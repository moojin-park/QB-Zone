# Emerald Spire Vortices baked-uniform provenance

## Selected ImageGen sources

| Runtime strip | Selected ImageGen file |
| --- | --- |
| Primary quarterback | `exec-87e735bf-6889-4e85-9ebb-f9b4bc3b3a44.png` |
| Alternate quarterback | `exec-3c9dc091-0f89-42d2-b057-f62e847e12d5.png` |
| Primary receiver | `exec-d7b3c9cb-0c6e-46be-b5cc-24d077aff621.png` |
| Alternate receiver | `exec-d522673d-b97e-47f2-98c0-67657a8e1fc8.png` |
| Primary defender | `exec-e5a5766b-60f4-4145-bbc6-dff0cd0abd0b.png` |
| Alternate defender | `exec-76a36e89-afb8-47be-a0d3-71a30b83a705.png` |

The selected files were generated with the built-in ImageGen tool. Directly accepted strips were copied to `generation/*-chroma.png`; the selected primary receiver and alternate defender used the deterministic component placement documented below to restore equal-slot spacing without changing their authored colors. Each prompt used the generic role strip and matching Nova City Comets primary strip as pose, proportion, pixel-density, and strip-grammar references only. The prompts required new authored pixel art on a flat `#FF00FF` field, exact frame order and numbers 7/11/24, large cell gutters, continuous black garment regions, one football per applicable frame, and no logos, masks, stains, holes, fragments, or duplicate equipment.

## Palette mapping

- Team colors: emerald green `#0D8642`, black `#000000`, white `#FFFFFF`.
- Primary offense: green helmet/jersey, black shoulders/pants, white number/trim/socks.
- Alternate offense: black helmet/jersey, white shoulders/pants, green number/trim/socks.
- Primary defense: green jersey/pants, black helmet/shoulders/socks, white number/trim.
- Alternate defense: black jersey/pants, white helmet/shoulders/socks, green number/trim.

## Rejected candidates

- `exec-38bde3e4-c030-461c-8ea6-5c863da82f37.png` was rejected because receiver touchdown frame 10 held both a raised football and an unintended second tucked football. The complete primary receiver strip was regenerated rather than retouched.
- `exec-8621427f-dbef-4eff-ad58-0d59c505d6f4.png` was rejected after normalization exposed undersized poses and slot-boundary fragments.
- `exec-1f43f346-bdcb-4d75-b29a-6be194d14580.png` was rejected because the alternate defender normalized undersized and retained slot fragments.

## Deterministic processing and QA

- Chroma extraction: `ios/Tools/extract-flat-pixel-chroma.py` with checked-in defaults and the finalized 512-pixel isolated-debris cutoff.
- Paired normalization: `ios/Tools/normalize-baked-team-strips.py` with one shared scale per primary/alternate role pair and the finalized 512-pixel isolated-artifact cutoff.
- Deterministic spacing: the primary receiver source's ten authored 8-connected pose components were nearest-neighbor scaled by `0.82` and placed into a `2172×724` strip at exact slot centers on baseline `424`, leaving 59–81 pixels of horizontal gutter. The alternate defender source's five authored components were translated without resampling (`1.00` scale) into a `1254×1254` strip with 250-pixel slots on baseline `817`, leaving 11–56 pixels of gutter. The receiver output colors are a strict subset of its source; the defender's visible RGBA histogram is byte-identical to its source. No recoloring or despill was used.
- No manual paint, recoloring, masking, or QA-only cleanup is applied.

- Final paired normalization scales: quarterback `0.98888889`, receiver `2.44444444`, defender `0.79265659`.
- Canonical outputs: quarterback `2172×724`, receiver `3620×724`, defender `2103×748`; every canonical strip retains alpha and contains zero visible exact-key `#FF00FF` pixels.
- Runtime export: 34 lossless `384×512` WebPs per uniform, 68 total; independent regeneration was byte-identical to the checked output.
- Visual/component QA: one complete connected player silhouette per frame, with a separate component only for the intentional airborne quarterback football; numbers 7/11/24, frame order, single-ball rules, palette continuity, and primary/alternate distinction pass.
- Review sheet: `../QA/primary-alternate-review.png` (`2048×3780`).
