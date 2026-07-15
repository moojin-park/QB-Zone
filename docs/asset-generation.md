# Pocket Vector asset generation

Pocket Vector uses two active local asset pipelines. The Node generator creates
SVG interface art plus original music and SFX. The pixel-character processor
turns the approved transparent source strips into normalized, lossless WebP
animation frames. The former headless Blender character generator remains
available only as a legacy command.

## Regenerate

From the repository root:

```bash
npm run generate:assets
npm run generate:characters
# or regenerate both:
npm run generate:all-assets

# previous 3D character set, if specifically needed:
npm run generate:characters:legacy-3d
```

The package scripts invoke:

```bash
node scripts/generate-assets.mjs
python3 scripts/process-pixel-character-strips.py \
  --qb-strip art/pixel-source/qb-strip.png \
  --receiver-strip art/pixel-source/receiver-strip.png \
  --defender-strip art/pixel-source/defender-strip.png \
  --official-strip art/pixel-source/official-strip.png \
  --force
```

The pixel processor requires Pillow with WebP support. Install it with
`python3 -m pip install Pillow` if it is not already available. It uses
nearest-neighbor resampling, one shared scale per role, a 16-pixel safe area,
and protected replacement through `--force`. Use `--dry-run` to validate every
frame without writing. Generated files are committed, so production builds do
not invoke a generator at runtime.

## Visual direction

The public title is **Pocket Vector**. The offense remains the fictional **Nova
City Comets** and the defense remains the fictional **Iron Bay Phantoms**. The
presentation is grounded, high-detail pixel-art football with no fantasy
elements. It is authored around a 512x384 visual density and presented at 2x
with crisp nearest-neighbor scaling. Warm red/cream offense colors contrast
with stadium blue/cream defense colors, gunmetal/navy cabinets, cream type,
cobalt accents, and restrained gold/red status colors.

Player frames are transparent 384x512 WebPs with a shared `[192, 496]` anchor.
The four QB poses stay in rear view while the throwing arm winds up, releases,
and follows through. Receivers use four sprint phases plus catch, four
post-catch carry phases, and a touchdown pose. The carry cycle keeps the
football tucked against the receiver's body while the legs continue through the
normal running cadence, so a player who has already completed a catch remains
visually distinct from an eligible empty-handed target. Their right-facing
source art is mirrored for leftward travel; jersey 11 remains readable in either
direction.
Defenders use four square shuffle phases plus an interception pose. Both
defender directions reuse the same front-facing art so jersey 24 is never
reversed. The processor also removes a detached ball from the QB release source
frame because the live projectile renderer is the authoritative football.
Sideline officials use two mirrored signal poses at the same 384x512 canvas and
bottom-center anchor, allowing the native SpriteKit port to animate them with
the same crisp nearest-neighbor treatment as the players.
[`public/assets/characters/sprites.json`](../public/assets/characters/sprites.json)
records content bounds, role, pose, direction, byte size, and anchor metadata.
The football is a stepped, rotation-ready PNG with an editable SVG source. Its
foreshortened rear end faces the quarterback/camera, and asymmetric edge
highlights make runtime rotation read as a longitudinal spiral instead of a
side-on tumble. The Canvas field camera remains 1024x768; widescreen modes
letterbox that stage inside decorative pixel-art side rails.

Button artwork deliberately contains no label text. Render localized,
keyboard-readable labels in the DOM or canvas above it. Meter fill is authored
at full width and should be clipped to the authoritative meter ratio. Effects
are static source frames intended for runtime scale, opacity, and rotation
animation; reduced-motion mode can use a short opacity fade alone.

The destination marker and projected trajectory are rendered as stepped canvas
blocks so their center and physics stay authoritative while matching the pixel
presentation.

## Art manifest

The stable runtime paths are:

```text
/assets/art/logo.svg
/assets/art/aim-destination-x.svg
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
/assets/pixel/stadium-field.png
/assets/pixel/logo.png
/assets/pixel/football.png
/assets/pixel/football-source.svg
```

The live title, football, and field use the `/assets/pixel/` files. The older
SVG logo, football, and procedural field remain as legacy/fallback inputs.

Character paths follow this pattern:

```text
/assets/characters/qb-{idle,aim,throw,recovery}.webp
/assets/characters/receiver-{run-1,run-2,run-3,run-4,catch,carry,carry-2,carry-3,carry-4,touchdown}-{left,right}.webp
/assets/characters/defender-{run-1,run-2,run-3,run-4,interception}-{left,right}.webp
/assets/characters/official-{wave-1,wave-2}-{left,right}.webp
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
`/assets/characters/sprites.json` records normalized pixel output. Runtime paths
are centralized in `src/game/assets/assetManifest.ts`. The approved concept and
four transparent production strips live in `art/pixel-source/`; the prompt set
and transformation notes live in
[`docs/pixel-art-direction.md`](pixel-art-direction.md).

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

The pixel stadium and character sources were created for this project with the
built-in image-generation tool, then normalized locally without downloaded
game, league, team, player, or broadcast art. The football source, runtime
rendering, interface styling, melody, sequence, and waveform assets are
project-authored. The visual direction is inspired by high-detail 16-bit-era
pixel craft without copying another game's characters, branding, or scenes.
