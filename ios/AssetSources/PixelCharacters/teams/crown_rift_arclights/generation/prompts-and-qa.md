# Crown Rift Arclights baked-uniform provenance

## Selected ImageGen sources

| Runtime strip | Selected ImageGen file |
| --- | --- |
| Primary quarterback | `exec-a64b0f6a-8c9b-4980-88f0-a8cecceef8d7.png` |
| Alternate quarterback | `exec-bd8c2c9f-3088-41a0-a3f4-dc0d2ddb6c6b.png` |
| Primary receiver | `exec-dcd23aa7-74ff-4faa-92a2-a01f59c30bef.png` |
| Alternate receiver | `exec-1e571eb1-a371-4ad3-b7e2-8541e76bb2db.png` |
| Primary defender | `exec-b8035bd8-df64-4232-bb93-8d84197f53d3.png` |
| Alternate defender | `exec-0ed6044c-7fff-43a9-901c-585071368fcc.png` |

The six selected files were generated with the built-in ImageGen tool and copied verbatim to `generation/*-chroma.png`. Role references were the generic source strip and the matching Nova City Comets primary baked strip. The common prompt required brand-new authored high-resolution pixel art, a single horizontal row on a flat `#FF00FF` field, exact role frame order, adult Black male athletes, consistent anatomy and uniform construction, large empty cell gutters, no logos or team text, and no masks, stains, spots, holes, duplicate equipment, or detached fragments.

Role-specific prompt contracts were: quarterback number 7 in four rear-view idle/aim/release/recovery frames; receiver number 11 in ten right-facing run/catch/carry/touchdown frames with one football per applicable frame; defender number 24 in five square/front run/interception frames with a football only in the interception. The selected receiver touchdown frames raise one football and leave the other hand open.

## Palette mapping

- Approved team colors: royal violet `#40215F`, reward gold `#D9AE36`, ivory `#F2EAF8`.
- Generated violet materials use `#40215F` as the deep base/shadow with clearly visible royal-violet midtones and highlights so the uniform reads purple rather than black at gameplay scale.
- Primary offense: violet helmet/jersey, gold shoulders/pants, ivory number/trim/socks.
- Alternate offense: gold helmet/jersey, ivory shoulders/pants, violet number/trim/socks.
- Primary defense: violet jersey/pants, gold helmet/shoulders/socks, ivory number/trim.
- Alternate defense: gold jersey/pants, ivory helmet/shoulders/socks, violet number/trim.

## Rejected candidates

- `exec-7e34b4d4-e5c8-4d42-bf88-76ee4fa7e205.png`, `exec-35334c91-b757-4f67-8abd-7ecb351dc1bb.png`, `exec-b6d07fea-fb63-441d-b749-5f255f237421.png`, `exec-e5473ba9-8b19-486b-aee0-91f616bd31ed.png`, `exec-7903f75a-b899-4783-a0c9-e7c661decc76.png`, and `exec-d7c117ac-5e01-4c41-bfc0-099207bcb328.png` were rejected because their violet collapsed toward black after extraction and did not satisfy the approved palette.
- Earlier receiver attempts `exec-bfab5dd9-2ad0-4ed3-ad25-576c00ea908a.png` and `exec-3292995c-daf4-4d88-8323-7ed1ba22264c.png` were also rejected for poor cell separation.
- `exec-2d57f291-d94e-4759-a499-ed550b0efbe3.png` was rejected because recovery frame 4 retained a partial football fragment. `exec-956041b4-39a0-4884-9638-92ceb74452c6.png` and `exec-8323166d-6532-456a-a2e0-36598ac9bae1.png` were rejected because silhouettes crossed equal-slot boundaries. All three whole strips were regenerated with larger cell gutters rather than retouched.
- `exec-7469e0a7-3ef4-4ed7-b211-08bee6412225.png` was rejected after canonical component inspection found a detached foot in release frame 3. The whole alternate quarterback strip was regenerated with a connected-silhouette contract.

## Deterministic processing and QA

- Chroma extraction: `ios/Tools/extract-flat-pixel-chroma.py` with the checked-in default settings and the finalized 512-pixel isolated-debris cutoff.
- Paired normalization: `ios/Tools/normalize-baked-team-strips.py` with one shared scale per primary/alternate role pair and the finalized 512-pixel isolated-artifact cutoff.
- Final scales: populated from the final accepted normalization run below.
- No manual paint, recoloring, masking, or QA-only cleanup is applied.

- Final paired normalization scales: quarterback `0.98503741`, receiver `1.31446541`, defender `0.75983437`.
- Canonical outputs: quarterback `2172×724`, receiver `3620×724`, defender `2103×748`; every canonical strip retains alpha and contains zero visible exact-key `#FF00FF` pixels.
- Runtime export: 34 lossless `384×512` WebPs per uniform, 68 total; independent regeneration was byte-identical to the checked output.
- Visual/component QA: one complete connected player silhouette per frame, with a separate component only for the intentional airborne quarterback football; numbers 7/11/24, frame order, single-ball rules, palette continuity, and primary/alternate distinction pass.
- Review sheet: `../QA/primary-alternate-review.png` (`2048×3780`).
