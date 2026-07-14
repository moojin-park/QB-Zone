# Character sprite source pipeline

Pocket Vector's shipping player sprites are original pre-rendered Blender art.
The generator builds the arcade-athlete geometry procedurally, so no league,
player, downloaded model, or proprietary QB Zone asset is included.

Generate from the repository root with Blender 5.x:

```bash
blender -b --python scripts/generate-character-sprites.py
```

The command writes only transparent WebP files and `sprites.json` under
`public/assets/characters/`. Generated files are committed; Blender is not
required by the browser or by the normal Vite production build.

All frames share a 384 x 512 canvas and a bottom-center anchor at `[192, 496]`.
The camera, model proportions, palette, lighting, and scale are held constant
across the full pose library. Runners have separate left and right renders so
numbers, uniform details, and directional lighting are never mirrored at
runtime.

The 26-frame pose matrix is:

- Quarterback, square rear view: idle, aim/wind-up, release, recovery.
- Receiver, left and right: four travel-facing sprint phases, catch, touchdown.
- Defender, left and right: four square ready/shuffle phases, interception.

Receiver legs use a 65-degree route-facing turn while the torso counter-rotates
to about 37 degrees and the head stays near 42 degrees toward the quarterback.
They also use a forward full-body lean and distinct flight, reach/contact,
opposite flight, and opposite contact phases. Defenders stay square with flexed
knees, bent elbows, modeled open fingers, and a wide arm span. Runtime cadence
and per-entity phase offsets are handled in `CanvasRenderer.ts`.

The art direction uses stylized pre-rendered arcade-football proportions:
exaggerated helmets and faces sit above tapered jerseys, flattened individual
pad caps, long segmented legs, and readable open hands. Restrained stadium
lighting defines the forms without thick comic outlines or plastic-toy glare.
