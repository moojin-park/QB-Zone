# Pocket Vector pixel-art direction

## Approved direction

The complete presentation is grounded, high-detail pixel-art football. It is
not a fantasy setting. Gameplay, timing, scoring, input, collision geometry,
camera projection, team names, and Pocket Vector branding remain unchanged.

The visual target is a 512x384 authored pixel density presented crisply at 2x
inside the canonical 1024x768 game camera. The palette combines red/cream Nova
City offense, blue/cream Iron Bay defense, deep navy and gunmetal cabinets,
cream typography, cobalt accents, and limited gold/red callouts.

## Built-in image-generation prompt set

All source generations used the built-in image-generation tool. The
approved concept was used as the visual and composition reference for the
production assets.

### Approved concept

Reimagine the supplied Pocket Vector gameplay frame as grounded, high-detail
pixel-art American football. Preserve the exact behind-the-quarterback 4:3
composition, field geometry, gameplay readability, Pocket Vector identity,
Nova City Comets red/cream offense, and Iron Bay Phantoms blue/cream defense.
Use richly shaded 16-bit-era pixel craft at a 512x384 logical density, crisp
edges, expressive football poses, a detailed night stadium, and a matching
pixel HUD. No fantasy imagery, magic, swords, monsters, licensed teams, or real
players.

### Stadium and field plate

Perform a precise object removal from the approved concept. Remove every
player, quarterback, player shadow, football, aim marker, HUD, score, timer,
meter, icon, and debug control. Reconstruct a clean night stadium and football
field while preserving the exact 4:3 camera, yard-line perspective, goalposts,
Nova City end-zone treatment, NC Comets midfield identity, detailed crowd, and
approved high-detail pixel style. No fantasy elements and no UI text.

### Quarterback strip

Create one exact horizontal four-frame sprite strip on a flat #00ff00
background. Show the same rear-view Nova City quarterback, red/cream uniform,
helmet, and jersey 7 in every equally spaced slot on one consistent baseline:
idle, aim/wind-up, throw release, recovery. Preserve identity, proportions,
palette, lighting, crisp pixel clusters, and readable silhouette. One complete
athlete per slot; no labels, overlap, shadows, effects, extra objects, or
fantasy elements.

### Receiver strip

Create one exact horizontal ten-frame sprite strip on a flat #00ff00
background. Show the same right-facing Nova City receiver, red/cream uniform
and jersey 11, on one consistent baseline: four distinct running phases, catch,
four post-catch carry phases, and touchdown celebration. Every carry phase must
show the football tucked securely against the receiver's body while the legs
repeat the established four-phase sprint cycle. Preserve identity, scale,
palette, lighting, crisp pixel clusters, separated limbs, and football-readable
motion. One athlete per slot; no duplicate or floating footballs, labels,
overlap, shadows, effects, extra objects, or fantasy elements.

### Defender strip

Create one exact horizontal five-frame sprite strip on a flat #00ff00
background. Show the same square/front-facing Iron Bay defender, blue/cream
uniform and jersey 24, on one consistent baseline: four lateral ready/shuffle
phases and an interception pose. Preserve identity, scale, palette, lighting,
crisp pixel clusters, wide stance, and open hands. One athlete per slot; no
labels, overlap, shadows, effects, extra objects, or fantasy elements.

### Sideline official strip

Create one isolated full-body American football sideline official using the
approved receiver and defender sprites as exact pixel-density, proportion,
lighting, and rendering references. Use a black cap, black-and-white striped
shirt, black pants, and black shoes; pose both arms lowered naturally in the
resting frame. Keep a crisp bottom-center silhouette on a perfectly
flat #00ff00 background with no shadow, floor, text, number, logo, watermark,
football, or extra character. For the second frame, raise both arms together in
a balanced touchdown signal while preserving identity, stance, clothing, scale,
canvas placement, and every other visual detail. Chroma-key both frames, align
them to one baseline, and join them into the two-slot source strip.

## Local post-processing

The source strips were chroma-keyed locally, then processed by
`scripts/process-pixel-character-strips.py`. The processor validates slot
counts and transparency, normalizes all frames in a role to one scale, uses
nearest-neighbor sampling, preserves a 16-pixel safe area, anchors at
`[192, 496]`, and writes 38 lossless 384x512 WebPs plus metadata. Receiver and
official art is mirrored for direction; square defender art is reused unchanged
in both directions to preserve jersey number 24. A detached ball in the QB release
source is removed during normalization because the simulated runtime projectile
is rendered independently.

The live background was normalized to 1024x768 through nearest-neighbor 2x
presentation. The logo was pixel-normalized from the existing Pocket Vector
mark, retaining the name and branding. The football is an original stepped SVG
source rasterized to a small transparent PNG. It shows the foreshortened rear
end toward the quarterback, with off-axis highlights that visibly rotate around
the longitudinal spiral.

## Source and runtime paths

```text
art/pixel-source/concept-approved.png
art/pixel-source/qb-strip.png
art/pixel-source/receiver-strip.png
art/pixel-source/defender-strip.png
art/pixel-source/official-strip.png
public/assets/pixel/stadium-field.png
public/assets/pixel/logo.png
public/assets/pixel/football-source.svg
public/assets/pixel/football.png
public/assets/characters/*.webp
public/assets/characters/sprites.json
```
