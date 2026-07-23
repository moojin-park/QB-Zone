# Sunreef Currents baked-uniform provenance

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

- Approved palette: deep teal `#003F3C`, coral `#FF8C72`, shell white
  `#F4E8D8`.
- Primary offense: teal helmet/jersey, coral shoulders/pants, shell-white
  number/trim/socks. Alternate offense swaps coral into helmet/jersey,
  shell-white into shoulders/pants, and teal into number/trim/socks.
- Primary defense: teal jersey/pants, coral helmet/shoulders/socks, shell-white
  number/trim. Alternate defense swaps coral into jersey/pants, shell-white
  into helmet/shoulders/socks, and teal into number/trim.

## Selected ImageGen outputs

- QB primary: `exec-f33b7e69-2893-4778-af26-93e6d80531be.png`
- QB alternate: `exec-59a638b2-821f-4e82-a298-bad910cd0faf.png`
- Receiver primary: `exec-baed7fac-3717-465c-b269-f8653864155e.png`
- Receiver alternate: `exec-436c1ac3-a9eb-47a1-8087-a7562c6722ea.png`
- Defender primary: `exec-bf529e1d-e9d9-4815-82ec-7fe60900f6b7.png`
- Defender alternate: `exec-9f45f3e0-bac3-41ce-90f4-55fc9fd7ca18.png`

The first primary-defender candidate (`exec-e648...`) was rejected because it
substituted dark helmets for the approved coral. The selected full-strip redraw
restores coral helmets in every pose.

## Deterministic finish

`extract-flat-pixel-chroma.py` removed bright key-family colors within RGB
distance 128 globally, removed darker magenta edge shades only when connected
to the border, and removed isolated debris components up to 512 raw pixels.
This preserves retained RGBA values and protects authored violet materials.
`normalize-baked-team-strips.py` then removed isolated post-scale components
up to the same 512-pixel limit and used one shared
primary/alternate scale per role: QB `0.92289720`, receiver `1.42396313`,
defender `0.85747664`.

Review sheet: `../QA/primary-alternate-review.png`.
