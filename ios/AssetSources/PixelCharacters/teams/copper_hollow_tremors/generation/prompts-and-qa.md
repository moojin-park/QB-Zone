# Copper Hollow Tremors baked-uniform provenance

## Authored direction

- Tool: built-in ImageGen, one complete horizontal strip per role and uniform.
- References: the shipped generic `qb-strip.png`, `receiver-strip.png`, and
  `defender-strip.png` for pose order and slot contract, plus the shipped Nova
  City baked strips for material and pixel-art fidelity.
- Every player was redrawn as authored raster pixel art. No runtime tint,
  recolor mask, or shared grayscale uniform is used.
- Shared constraints: flat magenta chroma field, nearest-neighbor pixel edges,
  centered silhouettes, large gutters, no real-team marks, no text other than
  jersey numbers, no watermark, quarterback `7`, receiver `11`, defender `24`.
- Role sequences: quarterback 4 frames, receiver 10 frames, defender 5 frames.

## Palette mapping

- Approved palette: dark copper-brown `#43271D`, vivid orange `#F57422`, warm
  cream `#F3DFC1`.
- Primary offense: brown helmet/jersey, orange shoulders/pants, cream
  number/trim/socks. Alternate offense swaps orange into helmet/jersey, cream
  into shoulders/pants, and brown into number/trim/socks.
- Primary defense: brown jersey/pants, orange helmet/shoulders/socks, cream
  number/trim. Alternate defense swaps orange into jersey/pants, cream into
  helmet/shoulders/socks, and brown into number/trim.

## Selected ImageGen outputs

- QB primary: `exec-d7fb782c-de8f-4604-85e8-e719ccc9fe11.png`
- QB alternate: `exec-fd3cf50c-cd6e-472a-95f9-95be58c4c558.png`
- Receiver primary: `exec-a6cef947-47fd-43c5-89bb-c3b3495adb52.png`
- Receiver alternate: `exec-09c8bbd0-5cf7-4b56-b196-96e9e64c1e35.png`
- Defender primary: `exec-0e5105df-c424-4ab0-8e33-e62c1359b5d2.png`
- Defender alternate: `exec-26360934-7816-44ff-ac0e-3aa4a750db25.png`

## Deterministic finish

`extract-flat-pixel-chroma.py` removed bright key-family colors within RGB
distance 128 globally, removed darker magenta edge shades only when connected
to the border, and removed isolated debris components up to 512 raw pixels.
This includes the alternate-QB source's shifted key field while preserving
retained RGBA values and protecting authored violet materials.
`normalize-baked-team-strips.py`
then removed isolated post-scale components up to the same 512-pixel limit and
used one shared
primary/alternate scale per role: QB `0.90389016`, receiver `1.51449275`,
defender `0.86556604`.

Review sheet: `../QA/primary-alternate-review.png`.
