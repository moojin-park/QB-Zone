# Obsidian Vale Quasars baked-uniform provenance

## Authored direction

- Tool: built-in ImageGen, one complete horizontal strip per role and uniform.
- References: the shipped generic `qb-strip.png`, `receiver-strip.png`, and
  `defender-strip.png` for pose order and slot contract, plus the shipped Nova
  City baked strips for material and pixel-art fidelity.
- Every player was redrawn as authored raster pixel art. No runtime tint,
  recolor mask, or shared grayscale uniform is used.
- Shared constraints: flat `#FF00FF` chroma field, nearest-neighbor pixel
  edges, centered silhouettes, large gutters, no real-team marks, no text
  other than jersey numbers, no watermark, quarterback `7`, receiver `11`,
  defender `24`.
- Role sequences: quarterback 4 frames, receiver 10 frames, defender 5 frames.

## Palette mapping

- Approved palette: obsidian `#0B0D10`, signal red `#E5484D`, brushed silver
  `#C5CFD8`.
- Primary offense: obsidian helmet/jersey, red shoulders/pants, silver
  number/trim/socks. Alternate offense swaps red into helmet/jersey, silver
  into shoulders/pants, and obsidian into number/trim/socks.
- Primary defense: obsidian jersey/pants, red helmet/shoulders/socks, silver
  number/trim. Alternate defense swaps red into jersey/pants, silver into
  helmet/shoulders/socks, and obsidian into number/trim.

## Selected ImageGen outputs

- QB primary: `exec-3701d0f7-41dc-4115-93f6-04054d480634.png`
- QB alternate: `exec-fac6651e-dffd-41d9-b8ac-a5ccbb7e3108.png`
- Receiver primary: `exec-3376490b-e1de-44d3-a3e6-66c96fe9cf32.png`
- Receiver alternate: `exec-ef0f7cfd-e41c-4cdc-8b4c-2cb369e44b6e.png`
- Defender primary: `exec-1cf13fca-c0f5-4039-9a24-82cbc70544b8.png`
- Defender alternate: `exec-5c41715b-0c74-40e5-ab4e-a4ea462d4a43.png`

## Deterministic finish

`extract-flat-pixel-chroma.py` removed bright key-family colors within RGB
distance 128 globally, removed darker magenta edge shades only when connected
to the border, and removed isolated debris components up to 512 raw pixels.
This preserves retained RGBA values and protects authored violet materials.
`normalize-baked-team-strips.py` then removed isolated post-scale components
up to the same 512-pixel limit and used one shared
primary/alternate scale per role: QB `0.96341463`, receiver `1.62645914`,
defender `0.94344473`.

Review sheet: `../QA/primary-alternate-review.png`.
