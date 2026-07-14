# Pocket Vector asset generation

Pocket Vector uses two local asset pipelines. The Node generator creates SVG
interface art plus original music and SFX. The headless Blender generator
creates the transparent pre-rendered football-player sprites. Neither pipeline
downloads source material or embeds external samples.

## Regenerate

From the repository root:

```bash
npm run generate:assets
npm run generate:characters
# or regenerate both:
npm run generate:all-assets
```

The package scripts invoke:

```bash
node scripts/generate-assets.mjs
blender -b --python scripts/generate-character-sprites.py
```

Generation writes into `public/assets/` and does not require a browser. Blender
5.1 or newer is needed only for the character command. Generated files are
committed, so production builds never invoke either generator at runtime.

## Visual direction

The public title is **Pocket Vector**. The offense is the fictional **Nova City
Comets** and the defense is the fictional **Iron Bay Phantoms**. The palette uses
warm red/cream offense colors and stadium blue/cream defense colors. The
athletes use original exaggerated arcade-football proportions with tapered
torsos, exposed faces and necks, long segmented limbs, modeled pads and
helmets, restrained highlights, and soft contact shadows. The result is
pre-rendered stylized 3D rather than a flat outlined illustration or a set of
chunky toy pawns.

Player frames are transparent 384x512 WebPs with a shared `[192, 496]` anchor.
The four QB poses stay square in rear view while the throwing arm winds up,
releases, and follows through. Receiver legs use a 65-degree route-facing turn
while the torso counter-rotates to about 37 degrees and the head stays near 42
degrees toward the quarterback across four sprint phases; defenders use four
square ready/shuffle phases. Every receiver and
defender pose has explicit left and right renders, so the runtime never mirrors
jersey numbers or baked lighting.
[`public/assets/characters/sprites.json`](../public/assets/characters/sprites.json)
records content bounds, role, pose, direction, byte size, and anchor metadata.
The football remains a rotation-ready SVG. The Canvas field camera is always
1024x768; widescreen modes letterbox that stage inside decorative side rails.

Button artwork deliberately contains no label text. Render localized,
keyboard-readable labels in the DOM or canvas above it. Meter fill is authored
at full width and should be clipped to the authoritative meter ratio. Effects
are static source frames intended for runtime scale, opacity, and rotation
animation; reduced-motion mode can use a short opacity fade alone.

The reference-style coral destination X lives at
`/assets/art/aim-destination-x.svg`. Scale and fade it based on the gesture, but
keep its center at the actual destination point.

## Art manifest

The stable runtime paths are:

```text
/assets/art/logo.svg
/assets/art/aim-destination-x.svg
/assets/art/football.svg
/assets/art/effect-score.svg
/assets/art/effect-completion.svg
/assets/art/effect-touchdown.svg
/assets/art/effect-interception.svg
/assets/art/meter-frame.svg
/assets/art/meter-fill.svg
/assets/art/multiplier.svg
/assets/art/timer-warning.svg
/assets/art/button.svg
/assets/art/icon-mute.svg
/assets/art/icon-unmute.svg
/assets/art/icon-pause.svg
/assets/art/avatar-frame.svg
```

Character paths follow this pattern:

```text
/assets/characters/qb-{idle,aim,throw,recovery}.webp
/assets/characters/receiver-{run-1,run-2,run-3,run-4,catch,touchdown}-{left,right}.webp
/assets/characters/defender-{run-1,run-2,run-3,run-4,interception}-{left,right}.webp
/assets/characters/sprites.json
```

Additional original controls are supplied for menus and alternate surfaces:

```text
/assets/art/ui-button-secondary.svg
/assets/art/icon-play.svg
/assets/art/icon-restart.svg
/assets/art/icon-info.svg
```

`/assets/asset-manifest.json` records the Node-generated SVG/audio source set.
`/assets/characters/sprites.json` records Blender output. Runtime paths are
centralized in `src/game/assets/assetManifest.ts`.

## Audio

`/assets/audio/music/pocket-vector-drive.wav` is a deterministic, mono,
16-bit PCM loop at 22,050 Hz. It is 32 bars of original material at 140 BPM
(about 54.86 seconds). Synth tails wrap around the PCM buffer, so the loop seam
does not truncate the final beat. The arrangement combines synthesized kick,
snare, hats, bass, chord stabs, arpeggios, and a short original digital hook.

The generated sound effects are:

```text
/assets/audio/sfx/ui-hover.wav
/assets/audio/sfx/ui-select.wav
/assets/audio/sfx/countdown.wav
/assets/audio/sfx/snap.wav
/assets/audio/sfx/throw.wav
/assets/audio/sfx/flight.wav
/assets/audio/sfx/catch.wav
/assets/audio/sfx/deep-completion.wav
/assets/audio/sfx/touchdown.wav
/assets/audio/sfx/bonus-active.wav
/assets/audio/sfx/multiplier.wav
/assets/audio/sfx/incomplete.wav
/assets/audio/sfx/interception.wav
/assets/audio/sfx/meter-loss.wav
/assets/audio/sfx/timer-warning.wav
/assets/audio/sfx/game-over.wav
/assets/audio/sfx/continue-success.wav
```

All audio is one-channel PCM. The runtime should unlock playback from the first
player gesture, loop music with the Web Audio or HTML audio loop control, and
route music and effects through separate gain controls. Flight is a short
one-shot whoosh, not an infinite audio loop; begin it at release and stop or
fade it when the pass resolves. `ui-hover.wav` is optional on touch devices.

## Originality and redistribution

Every model, pose, material, shape, melody, sequence, and waveform in this asset
set is expressed in the repository generators. No proprietary QB Zone, Merit,
Megatouch, league, team, player, broadcast, music, sample-pack, or downloaded
asset is included. The generated output is original project source material.
