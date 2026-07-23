# Gilded Delta Monarchs baked-uniform provenance

## Selected ImageGen sources

| Runtime strip | Selected ImageGen file |
| --- | --- |
| Primary quarterback | `exec-bc021e88-99dd-484e-905d-37cd3b8b1c89.png` |
| Alternate quarterback | `exec-18dace27-c753-4c3b-a203-4e6cd234d940.png` |
| Primary receiver | `exec-5540e965-7dcd-4421-9cb3-c3159a5140e1.png` |
| Alternate receiver | `exec-a491d94d-fcbe-4385-9748-dd1577a895f8.png` |
| Primary defender | `exec-58517711-e5db-465c-a92b-a79a81d26234.png` |
| Alternate defender | `exec-1940ee8c-9140-4f16-8ef5-4c2e6f1f856f.png` |

The selected files were generated with the built-in ImageGen tool and copied verbatim to `generation/*-chroma.png`. Each prompt used the generic role strip and matching Nova City Comets primary strip as pose, proportion, pixel-density, and strip-grammar references only. The prompts required new authored pixel art on a flat `#FF00FF` field, clean anatomy, exact frame order and numbers 7/11/24, large cell gutters, one football per applicable frame, and no logos, masks, stains, holes, fragments, or duplicate equipment.

## Palette mapping

- Team colors: blue-charcoal `#26303B`, champagne `#C2A36A`, ivory `#F6F0E4`.
- Primary offense: blue-charcoal helmet/jersey, champagne shoulders/pants, ivory number/trim/socks.
- Alternate offense: champagne helmet/jersey, ivory shoulders/pants, blue-charcoal number/trim/socks.
- Primary defense: blue-charcoal jersey/pants, champagne helmet/shoulders/socks, ivory number/trim.
- Alternate defense: champagne jersey/pants, ivory helmet/shoulders/socks, blue-charcoal number/trim.

## Rejected candidates

- `exec-8c0fa0a7-4611-4919-afec-6344d0c1e856.png` and `exec-458b071f-40bc-4305-801e-1ccf3a91019f.png` were rejected because quarterback release frame 3 contained a detached second football fragment beside the intended airborne ball. Both complete strips were regenerated rather than retouched.
- `exec-fd1d2eb7-0811-4570-9c4e-21b5e90a3f56.png` was rejected after canonical component inspection found body fragments crossing equal receiver-slot boundaries. The complete alternate receiver strip was regenerated with fixed cell centers and larger gutters.
- `exec-5f34ad11-a39b-44de-a26e-04bf1326ab77.png` improved spacing but still left fragments in canonical frames 4 and 6. The selected strip uses the accepted Arclights receiver spacing as its explicit cell-placement reference.

## Deterministic processing and QA

- Chroma extraction: `ios/Tools/extract-flat-pixel-chroma.py` with checked-in defaults and the finalized 512-pixel isolated-debris cutoff.
- Paired normalization: `ios/Tools/normalize-baked-team-strips.py` with one shared scale per primary/alternate role pair and the finalized 512-pixel isolated-artifact cutoff.
- No manual paint, recoloring, masking, or QA-only cleanup is applied.

- Final paired normalization scales: quarterback `0.99246231`, receiver `1.41216216`, defender `0.80748663`.
- Canonical outputs: quarterback `2172×724`, receiver `3620×724`, defender `2103×748`; every canonical strip retains alpha and contains zero visible exact-key `#FF00FF` pixels.
- Runtime export: 34 lossless `384×512` WebPs per uniform, 68 total; independent regeneration was byte-identical to the checked output.
- Visual/component QA: one complete connected player silhouette per frame, with a separate component only for the intentional airborne quarterback football; numbers 7/11/24, frame order, single-ball rules, palette continuity, and primary/alternate distinction pass.
- Review sheet: `../QA/primary-alternate-review.png` (`2048×3780`).
