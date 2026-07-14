# Pocket Vector

Pocket Vector is a standalone-first, high-detail pixel-art arcade passing game
for modern desktop and mobile browsers. Press the quarterback, drag toward open
grass, and release ahead of a moving receiver. Throw speed continuously changes
the ball's flight time and arc. The same Pointer Events path supports a mouse,
trackpad, stylus, and touchscreen.

The game is written in TypeScript, built with Vite, rendered with Canvas 2D, and
ships with an optional Bounty Board Arcade adapter. Standalone is the default:
no account, ad provider, or platform handshake is required to play.

## Prerequisites

- Node.js 22.12 or newer. The project is currently verified with Node.js
  22.15.0 and npm 10.9.2.
- A current browser with Canvas 2D, Pointer Events, Web Audio, and ES2022
  support.
- Landscape orientation is strongly recommended on phones.

Pillow with WebP support is needed only to regenerate the checked-in pixel
character sprites (`python3 -m pip install Pillow`). Blender is not required to
install, run, test, build, or regenerate the current game; Blender 5.1 or newer
is used only by the explicitly named legacy 3D character command. Runtime
rendering remains Canvas 2D.

## Install and run

```bash
npm ci
npm run dev
```

Vite serves the game at `http://127.0.0.1:5173` by default. Audio unlocks after
the first player gesture, as required by mobile browsers.

Useful commands:

```bash
npm run dev              # local development server
npm test                 # run the Vitest suite once
npm run test:watch       # rerun tests while editing
npm run playtest         # run browser QA against the local Vite server
npm run lint             # ESLint, with zero warnings allowed
npm run format:check     # verify Prettier formatting
npm run format           # format the repository
npm run build            # type-check and create dist/
npm run preview          # serve the production artifact locally
npm run generate:assets  # regenerate SVG interface art and original audio
npm run generate:characters # normalize the approved pixel strips into WebP players
npm run generate:characters:legacy-3d # regenerate the retired 3D character set
npm run generate:all-assets # run both asset pipelines
```

Generated assets are committed under `public/assets/`; production builds do not
run the generator. See [docs/asset-generation.md](docs/asset-generation.md).

## Controls

### Mouse, trackpad, stylus, or touch

1. Press directly on the quarterback at the bottom of the field.
2. Drag upfield. The destination X follows the pointer, and the stepped pixel
   guide previews the throw's current arc.
3. Release ahead of a receiver, accounting for the receiver's movement while
   the ball is in flight.

A faster release produces a flatter, quicker throw. A slower release produces a
higher, longer lob. Only one pointer and one football are authoritative at a
time; canceled gestures do not create a throw.

### Keyboard and HUD

- `Escape`: pause during regulation, or resume a paused run.
- `F`: enter or leave fullscreen where the browser supports the Fullscreen API.
- Pause button: open audio, accessibility, and playfield-fit settings.
- Mute button: toggle all game audio.

## Phone and aspect-ratio behavior

The gameplay camera is always the same canonical 1024x768 (4:3) composition.
Wider screens add original cabinet-style side rails around that fixed stage;
they never reveal extra field, zoom the camera out, or change gesture mapping.
The shell respects iPhone safe-area insets and dynamic viewport height.
For an iPhone browser:

1. Rotate the phone to landscape. Portrait and near-portrait viewports show a
   rotate prompt instead of compressing the playfield.
2. Start with **Auto side rails** under Pause -> Cabinet fit.
3. Choose **Exact 4:3** to remove the rails or **Wide side rails** to use more
   of a landscape display without altering the playfield camera.

Mouse and touchscreen input use the same gameplay rules. Always smoke-test both
after changing projection, CSS, or gesture thresholds.

## Gameplay references

- [Gameplay and phase flow](docs/gameplay.md)
- [Exact scoring rules](docs/scoring.md)
- [Tuning guide](docs/tuning.md)
- [Original asset pipeline](docs/asset-generation.md)
- [Pixel-art direction and prompt set](docs/pixel-art-direction.md)
- [Bounty Board integration](docs/bounty-board-integration.md)

## Architecture

| Area                                        | Responsibility                                                                                              |
| ------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `src/app/GameApp.ts`                        | Application orchestration, phase transitions, platform lifecycle, input wiring, persistence, and test hooks |
| `src/game/state/`                           | Authoritative run state, settings, stats, phases, and selectors                                             |
| `src/game/simulation/`                      | Fixed-step timer, seeded spawning, ball trajectory, swept collision, pass resolution, and scoring           |
| `src/game/rendering/`                       | Canvas 2D field projection, depth scaling, sprites, football, aim X, and development overlays               |
| `src/game/ui/`                              | DOM HUD, menus, instructions, settings, continue flow, and results                                          |
| `src/game/input/`                           | Single-pointer sampling and continuous gesture-speed calculation                                            |
| `src/game/audio/`                           | Web Audio loading, music/SFX buses, mute, pause, and resume                                                 |
| `src/game/platform/`                        | Standalone, fake-test, and Bounty Board implementations behind one `ArcadePlatform` contract                |
| `public/assets/`                            | Shipping pixel stadium/logo/football, lossless WebP characters, SVG interface art, and WAV audio            |
| `scripts/generate-assets.mjs`               | Deterministic SVG interface-art and audio generator                                                         |
| `scripts/process-pixel-character-strips.py` | Pixel strip validation, normalization, mirroring, and lossless WebP/metadata output                         |
| `scripts/generate-character-sprites.py`     | Legacy headless Blender/Eevee character renderer                                                            |
| `tests/`                                    | Simulation and platform unit coverage                                                                       |

The render loop advances gameplay at a fixed 60 Hz simulation step and caps a
single browser-frame delta at 100 ms. Rendering, DOM UI, audio, and platform
signals consume the authoritative state rather than calculating score or time
independently.

## Build modes

### Standalone (default)

```bash
npm run build
```

This creates `dist/` with local persistence and no external account, cloud save,
rewarded ad, or host lock. A standalone run proceeds directly to results when
time and any final ball have resolved.

The current asset URLs are root-absolute (`/assets/...`), so deploy the artifact
at the web origin root. A subdirectory deployment requires a coordinated Vite
base-path and asset-path change.

### Bounty Board upload

```bash
VITE_ARCADE_PLATFORM=bountyboard npm run build
```

The Bounty Board SDK is already a production dependency. Optional build-time
settings are:

| Variable                     | Purpose                                       | Default                              |
| ---------------------------- | --------------------------------------------- | ------------------------------------ |
| `VITE_ARCADE_PLATFORM`       | Select `standalone` or `bountyboard`          | `standalone`                         |
| `VITE_BB_ALLOWED_HOSTS`      | Comma-separated allowed hosts or HTTP(S) URLs | empty                                |
| `VITE_BB_HOST_LOCK`          | Override production host locking              | on for non-development Bounty builds |
| `VITE_BB_SIGNED_HOST_LOCK`   | Request signed host attestation               | `false`                              |
| `VITE_BB_REWARDED_TEST_MODE` | Use test rewarded ads                         | `false`                              |

Do not enable rewarded test mode in a public production artifact. Host locking,
cloud persistence, identity, and rewarded-ad availability must be verified in
Bounty Board's uploaded test environment. The full lifecycle contract and
score-plausibility limits are in
[docs/bounty-board-integration.md](docs/bounty-board-integration.md).

`npm run playtest` expects `npm run dev` to be running at
`http://127.0.0.1:5173` (override with `PLAYTEST_URL`). It captures inspected QA
screenshots and a machine-readable report under the ignored `output/playtest/`
folder.

## Browser test hooks

Development builds install these hooks after art and audio preparation
completes:

```js
window.render_game_to_text(); // JSON snapshot of authoritative visible game state
window.advanceTime(5000); // fixed-step simulation advance; clamped to 0..120000 ms
window.setGameSeed(5293287); // set the live seeded RNG state to a positive integer
```

`npm run dev` also exposes the **TUNE** panel. It contains bounded live controls
for timing, lanes, receiver/defender movement, collision sizing, throw curves,
scoring, meter gains, and the touchdown multiplier, plus overlays, slow motion,
freeze, seed, forced outcomes, and reset actions. Development query values
`?mockAd=viewed`, `dismissed`, `error`, or `unavailable` exercise overtime UI
without a provider. The panel, mock-ad path, debug actions, and all three hooks
are omitted or inert in production builds.

## Production and upload checklist

1. Run `npm ci`, `npm test`, `npm run lint`, `npm run format:check`, and
   `npm run build` from a clean checkout.
2. Serve `dist/` over HTTPS and verify title, tutorial, a complete 60-second run,
   restart, audio unlock, mute, pause/resume, and persisted personal best.
3. Test mouse input and real touch input. Include 4:3 desktop, 16:9 desktop, an
   iPhone-class landscape viewport, device safe areas, and the portrait rotate
   prompt.
4. Verify short, medium, deep, and touchdown catches; incompletions;
   interceptions; TD Bonus activation/loss; and every touchdown multiplier.
5. Confirm a throw already in flight gets up to two seconds to resolve after
   the timer reaches zero, while a new throw cannot start.
6. For Bounty Board, build with `VITE_ARCADE_PLATFORM=bountyboard`, production
   host settings, and rewarded test mode off. Upload the generated `dist/`
   artifact using the platform's current upload workflow.
7. In the uploaded environment, verify loading/start/stop/game-over signals,
   player identity, cloud-save fallback, host blocking, and viewed, dismissed,
   unavailable, and errored rewarded-ad outcomes. Only a viewed ad may add 15
   seconds, once per run.
8. Configure and recheck the documented score cap, score-rate cap, and 75-second
   maximum rewarded run whenever scoring or timing changes.
9. Check the browser console and network panel for runtime errors or missing
   assets, then test the final uploaded artifact rather than only the local
   preview.

## Working title and original assets

**Pocket Vector is a working title, not a completed trademark clearance.** Run
normal name, store-listing, domain, and trademark checks before public release.

All checked-in interface art, modeled character frames, music, and sound effects
are generated locally by the two repository asset pipelines. Neither downloads
source assets or embeds external samples. The build contains no voice acting
and uses fictional teams rather than real league, team, or player likenesses.

The fictional matchup is **Nova City Comets vs Iron Bay Phantoms**. Keep those
names aligned across runtime copy, generated asset metadata, and release notes.
