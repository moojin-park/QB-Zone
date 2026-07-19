# Baked launch-team gameplay sprites

Every launch team has independently authored primary and alternate source
strips for the quarterback, receiver, and defender. The raster colors are final
materials, not inputs to a runtime recoloring mask.

## Source and runtime contract

Each team directory contains:

```text
primary/qb-strip.png
primary/receiver-strip.png
primary/defender-strip.png
alternate/qb-strip.png
alternate/receiver-strip.png
alternate/defender-strip.png
generation/...
```

- QB: `2172 x 724`, four `543 x 724` slots, rear-facing number 7.
- Receiver: `3620 x 724`, ten `362 x 724` slots, right-facing number 11.
- Defender: `2103 x 748`, five 420-pixel slots plus three transparent
  compatibility columns, square/front-facing number 24.
- Runtime: 34 lossless `384 x 512` WebPs per uniform, bottom-center anchor
  `[192, 496]`, with receiver mirrors and identical defender direction pairs.
- Officials remain universal and are never duplicated into team directories.

Raw chroma generations and exact selected prompts remain under `generation/`
for provenance. Rejected generations are not retained in the project tree.
Role-wide approved review sheets live under `QA/`.

## Team palettes

| Team ID | Primary | Secondary | Accent |
| --- | --- | --- | --- |
| `nova_city_comets` | `#1DE6EF` | `#7D4DFF` | `#F7FCFF` |
| `high_mesa_helions` | `#F06A3B` | `#2B234D` | `#D8F0EC` |
| `luma_coast_prisms` | `#63CFE7` | `#30214F` | `#F4C64E` |
| `foundry_reach_orbiters` | `#146353` | `#D4A73E` | `#F0E8CF` |
| `neon_basin_eclipses` | `#171923` | `#ADB5C2` | `#A05CFF` |
| `meridian_plains_radiants` | `#C72F4F` | `#F0A253` | `#FFF0DD` |
| `rainport_auroras` | `#0B3A4A` | `#9DD643` | `#E5F2EA` |
| `bayline_redshifts` | `#842C4B` | `#C87845` | `#DFE5E2` |

Primary offense uses primary helmet/jersey, secondary shoulder panels/pants,
and accent numbers/trim/socks. Alternate offense uses secondary helmet/jersey,
accent shoulder panels/pants, and primary numbers/trim/socks.

Primary defense uses primary jersey/pants, secondary helmet/shoulder
panels/socks, and accent numbers/trim. Alternate defense uses secondary
jersey/pants, accent helmet/shoulder panels/socks, and primary numbers/trim.

Skin, football leather, facemasks, gloves, tape, and cleats remain independent
natural or neutral materials in every strip. Runtime tinting, semantic masks,
uniform projection, and color blending are prohibited for these assets.
