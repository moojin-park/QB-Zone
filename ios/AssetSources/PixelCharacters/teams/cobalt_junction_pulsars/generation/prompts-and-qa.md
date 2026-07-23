# Cobalt Junction Pulsars baked-uniform provenance

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

- Approved palette: deep navy `#14284F`, pulse cyan `#72C9F2`, coral
  `#F26678`.
- Primary offense: navy helmet/jersey, cyan shoulders/pants, coral
  number/trim/socks. Alternate offense swaps cyan into helmet/jersey, coral
  into shoulders/pants, and navy into number/trim/socks.
- Primary defense: navy jersey/pants, cyan helmet/shoulders/socks, coral
  number/trim. Alternate defense swaps cyan into jersey/pants, coral into
  helmet/shoulders/socks, and navy into number/trim.

## Selected ImageGen outputs

- QB primary: `exec-b8c9fed0-3a4d-410b-8910-56f36f57588a.png`
- QB alternate: `exec-c02d15bd-ef2b-4595-92af-728d697042e0.png`
- Receiver primary: `exec-152b4257-c235-47ac-9385-8676c9beef1a.png`
- Receiver alternate: `exec-24cc7f7e-e9f8-4891-a961-ea8d99489a0e.png`
- Defender primary: `exec-b0dcee96-a72d-4233-8d61-c6fa7b19a14c.png`
- Defender alternate: `exec-fa87157e-2700-4876-a58a-6352065f5c52.png`

The first alternate-QB candidate (`exec-c610...`) was rejected for mottled
coral. A second candidate (`exec-bc911427-9138-4dcb-96ee-3c5fd89aa68b.png`)
corrected the uniform but contained a detached football fragment. The selected
third full-strip redraw preserves clean continuous coral and exactly one
football in the release frame.

## Deterministic finish

`extract-flat-pixel-chroma.py` removed bright key-family colors within RGB
distance 128 globally, removed darker magenta edge shades only when connected
to the border, and removed isolated debris components up to 512 raw pixels.
This preserves retained RGBA values and protects authored violet materials.
`normalize-baked-team-strips.py` then removed isolated post-scale components
up to the same 512-pixel limit and used one shared
primary/alternate scale per role: QB `0.99496222`, receiver `1.55970149`,
defender `0.77835052`.

Review sheet: `../QA/primary-alternate-review.png`.
