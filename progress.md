Original prompt: Build the complete browser game described in QB_ZONE_CODEX_BUILD_SPEC.md, using the linked QB Zone footage as a gameplay reference while creating original branding and assets.

# Pocket Vector build progress

## Confirmed direction

- Ground-up build in this empty repository.
- Vite + strict TypeScript + Canvas 2D; no Phaser, React, Three.js, or physics engine.
- Standalone-first with the Bounty Board SDK isolated and ready for a hosted upload.
- High-detail pixel-art characters, stadium, football, logo treatment, HUD, and menus with original team colors.
- Mouse, touch, pen, and stylus share Pointer Events.
- A canonical 4:3 gameplay camera at every device size; adaptive/wide modes may add side rails but never widen or zoom out the field.
- Visible destination X while aiming.
- Original procedural music and synthesized SFX; no voice acting.

## Baseline

- Repository initially contained only `.git`, with no commits, source, package manifest, tests, or remote.
- No pre-existing validation commands could run.
- Node 22.15.0, npm 10.9.2, FFmpeg, ImageMagick, Blender CLI, Playwright, and Chromium are available.
- Blender MCP tools are registered but the Blender add-on is not connected; the installed Blender CLI is the reproducible character-rendering path.

## Visual-direction reset (2026-07-13)

The first complete build passed functional QA but missed the requested visual reference. The user correctly identified two foundational problems: the SVG athletes read as flat outlined stickers instead of pseudo-3D model sprites, and responsive wide mode changed the gameplay camera instead of preserving the source-like 4:3 composition.

- [x] Rectify and measure reference gameplay frames at 1024x768.
- [x] Confirm the intended style is pre-rendered stylized 3D, not vector illustration.
- [x] Prototype transparent Blender/Eevee player rendering and validate web asset size.
- [x] Lock simulation/rendering to one 1024x768 low behind-QB camera.
- [x] Keep optional wide presentation as letterboxed side rails around the fixed game stage.
- [x] Replace full-body foreground QB with a large rear-view, waist-cropped model render.
- [x] Replace SVG runners with direction-specific Blender-rendered WebP sprites.
- [x] Rebuild the stadium, field perspective, midfield mark, and arcade HUD.
- [x] Re-run functional, responsive, screenshot, and production-build QA.

## Implementation checklist

- [x] Scaffold and install toolchain.
- [x] Centralize gameplay/scoring/visual/audio/platform configuration.
- [x] Deterministic state machine, timer, RNG, entities, and fixed-step update.
- [x] Sampled pointer gesture and continuous bullet/lob trajectory.
- [x] Horizontal receiver lanes and segmented defender hit zones.
- [x] Pass resolution, score, TD meter, and touchdown multiplier.
- [x] Reproducible original visual/audio assets.
- [x] Title, instructions, HUD, pause/settings, continue, and results flows.
- [x] Bounty Board adapter, rewarded overtime, and persistence fallback.
- [x] Unit tests and deterministic browser hooks.
- [x] Mouse/touch/responsive browser playtest with inspected screenshots.
- [x] Documentation and final validation.

## Trackpad and trajectory refinement (2026-07-13)

- [x] Reproduce the Mac trackpad failure: drag to a target, pause, then release at the same coordinate.
- [x] Keep repeated stationary release samples from diluting the last meaningful movement speed.
- [x] Accept every sufficient-distance upfield drag; sub-slow releases now clamp to the highest lob.
- [x] Consume coalesced pointer samples and complete mouse/trackpad capture loss from the last destination.
- [x] Preserve touch cancellation and single-pointer ownership.
- [x] Replace the straight dotted aim guide with the exact projected ball arc while retaining the destination X.
- [x] Add unit and browser regressions for paused trackpad release and slow/fast arc shape.

## Final verification

- 218 deterministic unit and integration tests pass.
- Strict TypeScript compilation, ESLint, Prettier, and Vite production builds pass.
- Standalone and Bounty Board build modes both compile successfully.
- Automated browser playtest passes with paused trackpad, mouse, and touch-style pointer input, responsive viewport coverage, rewarded-ad outcomes, and final-ball grace behavior.
- All captured title, instructions, gameplay, destination-X, pause, bonus, results, overtime, landscape-phone, and portrait-warning screens were visually inspected after the visual reset.
- The shipping character set contains 26 original lossless 384x512 transparent WebP frames at about 1.7 MiB total, with a shared bottom-center anchor, mirrored direction-specific receivers, and number-safe square defenders reused in both directions.

## On-field motion refinement (2026-07-13)

- [x] Keep all three defenders on a deterministic in-frame patrol instead of recycling offscreen.
- [x] Reflect defender position at both sideline bounds without frame-partition drift.
- [x] Make defender patrol speeds slower than receivers at comparable depths.
- [x] Reuse the same patrol behavior in title attract mode and live gameplay.
- [x] Preserve per-defender crossing-time tuning as the actual sideline-to-sideline duration.

## End-zone field cleanup (2026-07-13)

- [x] Expand the projected end zone from a compressed 13-pixel strip to a readable 52-pixel band.
- [x] Center the NOVA CITY wordmark within the band with at least 15 pixels of projected clearance.
- [x] Remove the 0.72 and 0.82 yard stripes so no yard line duplicates or crosses the goal line.
- [x] Leave the next field stripe 54 pixels in front of the goal line at the canonical 4:3 projection.
- [x] Add deterministic geometry tests and visually inspect the live canvas after the change.

## Source-matched character motion (2026-07-13)

User request: "Look at the YouTube video of the game play starting at 17 seconds and mimic the angle of the players and the way they're turned, the animation of the individual characters."

- [x] Extract and inspect the linked footage from 0:17 onward, including the receiver sprint, defender ready stance, and QB wind-up/release.
- [x] Replace the camera-square receiver shuffle with a 68-degree travel-facing three-quarter profile.
- [x] Expand receivers from two leg-swap frames to a four-phase sprint: flight, reach/contact, opposite flight, and opposite contact.
- [x] Separate defender motion from receiver motion with a slower four-phase square stance, flexed knees, bent elbows, and open hands.
- [x] Rebuild the QB as a nearly square rear view with distinct idle, wind-up, release, and short recovery poses.
- [x] Add deterministic per-entity cadence variation and phase offsets so characters do not animate in lockstep.
- [x] Reset action animation time on catches, touchdowns, and interceptions, then return visually to the run cycle after a short held pose.
- [x] Expose pose and animation time in `render_game_to_text` and add frame-selector/asset coverage.
- [x] Regenerate all 26 direction-specific WebP frames and refresh `sprites.json`.
- [x] Verify 209 tests, ESLint, Prettier, TypeScript/Vite production build, and the full desktop/wide/mobile browser playtest.
- [x] Inspect final 4:3 gameplay, aim, touchdown, wide, iPhone landscape, role-specific sprite sheets, and deterministic title-attract captures; no console errors were reported.

## Character source-match correction (2026-07-14)

The first motion pass changed frame cadence and travel direction but retained the wrong chunky pawn anatomy. After the user rejected that result, the reference and live game were compared side by side again and the player model itself was rebuilt.

- [x] Decouple the receiver pose: route-facing legs at 65 degrees, chest opened back to about 37 degrees, and gaze held near 42 degrees toward the quarterback.
- [x] Add a source-like forward full-body lean while preserving long, separated arm and leg diagonals through all four sprint phases.
- [x] Rebuild all roles with tapered torsos, narrower limbs, smaller gloves, exposed necks/faces, and individual flattened shoulder-pad caps.
- [x] Keep defenders square to the quarterback with a wide open-hand span, visible knee flex, and faster weight-transfer cadence.
- [x] Rebuild the QB as a nearly square rear silhouette without the floating collar or rear robot-face badge.
- [x] Restore the source role hierarchy with warm red offense and blue defense while retaining the fictional Nova City/Iron Bay branding.
- [x] Remove runtime bitmap bob so each baked contact shadow remains planted while the pose frames provide the body motion.
- [x] Regenerate all 26 WebPs and metadata from the revised Blender model.
- [x] Re-run 209 deterministic tests, formatting, lint, production build, and the complete desktop/mobile browser playtest.
- [x] Inspect the final gameplay, aim, action, animation sequence, and responsive screenshots against the 0:17+ source footage; the final browser report contains no failures or console errors.

## High-detail pixel-art transformation (2026-07-14)

User direction: preserve all gameplay mechanics and functionality while completely replacing the presentation with grounded, high-detail pixel-art football visuals. Keep Pocket Vector, Nova City Comets, Iron Bay Phantoms, and the existing fictional branding. Do not introduce fantasy elements.

- [x] Audit the renderer, collision geometry, animation contracts, and responsive camera.
- [x] Approve a representative 4:3 gameplay concept at a 512x384 authored density with 2x crisp presentation.
- [x] Build and normalize the full QB, receiver, and defender pixel animation set.
- [x] Replace the stadium/field, football, aim guide, effects, HUD, menus, logo treatment, and side rails.
- [x] Add crisp pixel scaling without changing simulation, hit zones, timing, scoring, or input.
- [x] Run unit, lint, format, production-build, and full screenshot-based gameplay verification.

The approved concept and production strips were generated with the built-in
image-generation tool and checked into `art/pixel-source/`. The reproducible
processor emits the unchanged 26-frame runtime contract with a shared anchor.
The final browser QA covers title, instructions, live play, aim, pause,
touchdown bonus, results, widescreen, touch landscape, portrait warning,
continue offer, and overtime results with no console errors.

## End-on football spiral correction (2026-07-14)

User direction: "The ball should spiral with the end of the ball towards the
quarterback. Right now, it's spinning with the laces of the ball facing the
quarterback."

- [x] Replace the side-profile, lace-forward football with a foreshortened rear-end pixel view.
- [x] Keep trajectory, collision radius, flight timing, and spin rate unchanged.
- [x] Render the end-on asset square so the existing rotation reads as longitudinal spiral rather than tumbling.
- [x] Move the mobile playtest capture to mid-flight so orientation remains visually inspectable.

## Destination-X landing correction (2026-07-14)

User direction: "The ball doesn't land on the spot of the X making it feel
inaccurate."

- [x] Trace the pointer marker through screen-to-world projection and released-ball trajectory.
- [x] Remove the hidden 18% horizontal overshoot after the configured catch point.
- [x] Preserve the original route/collision timing by reaching the X at catch progress, then descending at that marked location.
- [x] Keep the destination X visible for the entire flight and paint it beneath the arriving football.
- [x] Add endpoint projection tests and a frozen browser capture asserting the ball center reaches the X within four logical pixels.
- [x] Re-run the full mouse, trackpad, touch, responsive, results, and overtime browser playtest with no console errors.

## Destination-X catch reconciliation (2026-07-14)

User direction: "The ball is going where the X is but the catch isn't
registering" and "the ball still wants to travel higher than the X making me
have to aim lower in order to have the receiver catch it."

- [x] Trace the mismatch to torso-height screen coordinates being interpreted as deeper height-zero field destinations.
- [x] Preserve the original swept receiver-lane collision as the primary catch path.
- [x] Add a final-descent screen-space check against the same projected receiver catch rectangle shown by the debug overlay.
- [x] Keep defender collision, scoring, trajectory, horizontal lead timing, and exact valid-field X landing unchanged.
- [x] Cover slow lobs, fast throws, pre-descent non-catches, clear misses, endpoint resolution, and end-zone body targets above the horizon.
- [x] Add a real browser regression that places the X 70 pixels up the receiver's body and requires a genuine completion.
- [x] Inspect the completion and destination-X captures; the full browser report passes with no failures or console errors.
