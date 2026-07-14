# Tuning guide

Pocket Vector keeps most product tuning in a small set of TypeScript config
files. Change one behavior cluster at a time, use a fixed seed for comparisons,
and verify actual browser play in addition to unit tests.

## Central configuration files

### `src/game/config/gameplayConfig.ts`

This file controls session timing, lanes, movement, input thresholds, and ball
flight.

| Setting                                         |          Current value | Effect and safe direction                                                                                                                                             |
| ----------------------------------------------- | ---------------------: | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `SESSION_DURATION_MS`                           |                 60,000 | Regulation length. If changed, update UI copy, test expectations, and platform score limits.                                                                          |
| `REWARDED_CONTINUE_SECONDS`                     |                     15 | Granted viewed-ad time. Keep aligned with Bounty reward config and the 75-second plausibility assumption.                                                             |
| `MAX_REWARDED_CONTINUES_PER_RUN`                |                      1 | Hard gameplay cap. Raising it changes monetization and maximum-run assumptions.                                                                                       |
| `FIXED_STEP_MS`                                 |                1000/60 | Simulation frequency. Treat as engine-level; changing it requires frame-partition and collision regression tests.                                                     |
| `MAX_FRAME_DELTA_MS`                            |                    100 | Maximum real-time catch-up per animation frame. Lower values discard more stalled-tab time.                                                                           |
| `FINAL_BALL_GRACE_MS`                           |                  2,000 | Maximum time for an in-flight ball after zero.                                                                                                                        |
| `PASSING_LANES[].normalizedDepth`               | 0.28, 0.48, 0.68, 0.87 | Lane depth from near 0 to far 1. Recheck labels, projection, defenders, and catch timing after changes.                                                               |
| `PASSING_LANES[].receiverCrossingSeconds`       |     4.4, 5.0, 5.7, 6.3 | Lower is a faster runner and requires more lead.                                                                                                                      |
| `PASSING_LANES[].catchWidth`                    | 0.17, 0.15, 0.14, 0.13 | Larger is more forgiving horizontally in both swept lane checks and the final-descent projected catch rectangle. Catch height remains `0.08..0.92` in `collision.ts`. |
| `maximumConcurrentReceivers`                    |             1 per lane | Raise cautiously; target readability and overlapping same-lane catches change.                                                                                        |
| `receiverSpawnDelayMs`                          |               180..620 | Delay after a lane runner despawns before replacement.                                                                                                                |
| `defenderDepths`                                |       0.39, 0.58, 0.73 | Defender interception planes. The deepest defender sits between the deep receiver and the end-zone receiver.                                                          |
| `defenderPatrolHalfWidth`                       |                   0.78 | In-frame horizontal reversal point for defender centers. Keep enough margin for the nearest defender's full sprite.                                                   |
| `defenderCrossingSeconds`                       |          4.7, 5.8, 6.8 | Seconds for one full patrol from the left reversal point to the right. All three defaults remain slower than nearby receivers.                                        |
| `defenderWidthWorld`                            |                   0.22 | Horizontal scale for defender-local hit zones. Larger makes defenders effectively wider.                                                                              |
| `timerWarningMs`                                |                 10,000 | Visual urgency threshold.                                                                                                                                             |
| `adPrepareAtRemainingMs`                        |                 10,000 | Background continue-ad preparation threshold. Keep aligned with product intent and ad load timeout.                                                                   |
| `throw.minimumGestureDistancePx`                |                     34 | Minimum logical drag distance. Higher rejects more taps/short swipes.                                                                                                 |
| `throw.slowSpeedPxPerMs` / `fastSpeedPxPerMs`   |             0.25 / 1.8 | Endpoints for continuous speed normalization; values outside clamp to 0/1.                                                                                            |
| `throw.minimumDurationMs` / `maximumDurationMs` |            430 / 1,180 | Base bullet/lob flight duration before distance scaling.                                                                                                              |
| `throw.minimumArcHeight` / `maximumArcHeight`   |            0.28 / 1.05 | Fast/slow arc endpoints.                                                                                                                                              |
| `throw.catchProgress`                           |                   0.82 | Portion of flight at which horizontal travel reaches the destination X. Lower values begin the on-marker descent earlier.                                             |

Gesture acceptance depends on drag distance and upfield direction, not speed.
Release speed only selects the throw curve: anything at or below the slow
endpoint becomes the maximum-duration, maximum-height lob.

`quarterbackStart`, receiver offscreen/despawn values, and the defender patrol
width use the same normalized world coordinate system and should be tuned
together.
`logicalHeight` is the shared 768-pixel simulation/render height, while
`defaultSeed` selects the initial deterministic spawn sequence. Treat either as
a cross-system change: input thresholds, projection, snapshots, and seeded
tests all depend on them.

Some declarations are currently descriptive or reserved rather than active:

- `PASSING_LANES[].spawnWeight` is not read by the current per-lane spawner.
- `GAMEPLAY_CONFIG.playResolutionCooldownMs` is not read; pass cooldowns are
  currently 250 ms for normal outcomes and 420 ms for touchdowns in
  `resolvePass.ts`.
- `wideLogicalWidth` is reserved and not read. The renderer remains 1024x768 in
  every presentation mode; only the outer shell and its side rails change.
  `classicLogicalWidth` is the authoritative logical render width.

Do not expect a reserved value to change gameplay until its consumer is wired.

### `src/game/config/scoringConfig.ts`

This is the authoritative scoring table. Safe product knobs are lane base
points, lane meter gains, the meter maximum, TD bonus, and multiplier ladder.
Read [scoring.md](scoring.md) before changing them.

Keep `SCORE_CONFIG.lanes` aligned with the duplicated `completionPoints` and
`tdMeterGain` values in `PASSING_LANES`. After any scoring or timing change,
recalculate `PLAUSIBLE_MAXIMUM_SCORE`,
`PLAUSIBLE_MAXIMUM_SCORE_PER_SECOND`, and `MAXIMUM_SUPPORTED_RUN_MS`, then update
the Bounty Board configuration and documentation.

`incompletionPoints` and `interceptionPoints` are currently declared as zero,
while score calculation directly assigns zero to unsuccessful plays. A nonzero
penalty/reward requires a code change and new tests, not only a config edit.

### `src/game/config/visualConfig.ts`

This file owns the public title, runtime color palette, and perspective field
geometry:

- `field.horizonY` / `nearGroundY` set the far and below-screen ground anchors.
- `farHalfWidthPx` / `nearHalfWidthPx` control field convergence without
  exposing a long central trapezoid.
- `depthExponent` controls nonlinear yard-line compression.
- `farActorScale` / `nearActorScale` control the roughly threefold depth range.
- `actorHeightPx` aligns ball height and segmented collision overlays with the
  modeled sprites.
- Palette changes affect canvas-rendered field, aim, warnings, and overlays.

Projection changes alter aiming and hit-zone screen placement, so validate the
same canonical landmarks in exact 4:3, wide side rails, and iPhone landscape.

The current `offenseTeam` and `defenseTeam` fields are not the only team-name
source: title markup and the end-zone label currently contain their own strings,
and `scripts/generate-assets.mjs` writes separate asset metadata. Update all of
them together for a naming change.

### `src/game/config/audioConfig.ts`

This file maps the gameplay music and SFX IDs to shipping paths. Missing or
malformed audio fails safely and cannot block play.

- Default run settings currently use music `0.38` and SFX `0.72` in both this
  config and `createInitialState.ts`. The audio manager currently reads the
  values from game state, not directly from `AUDIO_CONFIG`, so changing only
  the config values does not change the first-run mix.
- A brand-new persisted-data payload has separate defaults in
  `src/game/platform/storage.ts`; keep all default-volume sources intentionally
  aligned if changing the first-run mix.
- `fadeMs` is currently reserved; gain smoothing uses a hardcoded Web Audio time
  constant and does not read this value.

Regenerate audio only through `npm run generate:assets`, then test first-gesture
unlock, music loop, pause/resume, mute, both volume sliders, and missing-audio
fallback on desktop and iOS Safari.

### `src/game/config/bountyBoardConfig.ts`

This file controls the rewarded placement/reward identifiers, SDK timeouts, and
persistence key.

- `placement` and `reward` are consumed by the platform adapter and must match
  the Bounty Board dashboard.
- `initializationTimeoutMs`, `adLoadTimeoutMs`, and `storageKey` are active.
- `enabled`, `addedTimeMs`, `maximumUsesPerRun`, and `prepareAtRemainingMs`
  describe the product contract, but the live controller currently enforces
  matching values from `gameplayConfig.ts` and does not read `enabled`. Keep
  both configs synchronized; disabling rewarded overtime currently requires a
  controller/build decision rather than changing `enabled` alone.
- Changing the storage key starts a new local save namespace. Treat that as a
  migration decision, not a cosmetic rename.

Environment variables select platform behavior at build time; see
[bounty-board-integration.md](bounty-board-integration.md).

## Related tuning hotspots

These are implementation files rather than central configs, but changes here
directly alter game feel:

- `src/game/simulation/defenderHitZones.ts`: interception and explicit
  pass-through body geometry.
- `src/game/simulation/collision.ts`: receiver height window, ball collision
  radius in defender-local space, and out-of-lane logic.
- `src/game/simulation/spawn.ts`: bounded defender reflection and receiver spawn
  randomization.
- `src/game/simulation/resolvePass.ts`: feedback durations and actual per-result
  throw cooldowns.
- `src/game/rendering/projection.ts`: depth scaling, ground projection, target
  world clamping, and quarterback input rectangle.
- `src/styles/main.css`: adaptive shell sizing, safe areas, short-screen HUD,
  portrait overlay, and reduced-motion CSS.
- `src/game/platform/storage.ts`: schema and persisted default settings.
- `src/game/assets/assetManifest.ts`: runtime art paths.
- `scripts/generate-assets.mjs`: generated art palette/team metadata, sprite
  geometry, music arrangement, and SFX synthesis.
- `scripts/generate-character-sprites.py`: modeled player proportions, poses,
  materials, fixed sprite camera, lighting, and WebP output.

## Development tuning panel

Run `npm run dev` and open **TUNE** in the lower-left corner. The panel is hidden
in production builds; its markup, bindings, test hooks, and score-forcing actions
are not available to production players.

The panel contains 46 bounded number controls grouped as:

- **Timing:** session and rewarded-continue duration.
- **Lanes & receivers:** spawn-delay range plus each lane's depth, runner crossing
  time, and catch width.
- **Defenders:** each defender's crossing time and depth plus global hit-zone
  width.
- **Ball & throw curves:** ball radius, slow/fast release thresholds,
  fast/slow flight duration, and minimum/maximum arc.
- **Scoring & multiplier:** every lane's points and meter gain, meter maximum,
  touchdown bonus, and all six multiplier steps.

Edits are clamped to safe ranges. Ordered lane/defender depths, paired minimum
and maximum values, and the nondecreasing multiplier ladder are protected. Live
entities update when a relevant movement/depth/radius control changes. **Reset
run** retains tuning; **Reset all tuning to defaults** restores every mutable
configuration value and current entity synchronization.

The diagnostics section provides:

- **Trajectory** draws the full live ball path.
- **Catch zones** draws receiver target areas.
- **Defender zones** distinguishes intercepting/pass-through body geometry and
  shows the swept ball radius, previous/current ball points, and last exact
  catch or interception point.
- **Speed** scales simulation time from 0.1x to 1x.
- **Seed** sets the deterministic live RNG state.
- **Freeze** stops simulation updates.
- **Reset run** starts a clean run without discarding tuning.
- **Complete / TD / Miss / INT** force the next active-ball resolution, creating
  a representative ball when needed.

Use forced outcomes for UI/scoring checks, but also land real catches and
interceptions before accepting gameplay tuning.

## Verification checklist

1. Record the config values and fixed seed used for the comparison.
2. Run `npm test`, `npm run lint`, `npm run format:check`, and `npm run build`.
3. Use the development overlays to inspect the changed trajectory, catch zone,
   or defender geometry at normal speed and slow motion.
4. Play complete runs with both mouse and real touch. Include a canceled
   gesture, release outside the canvas, rapid repeated input, and an attempted
   second throw while a ball is active.
5. Test 1024x768 (4:3), 1366x768 (wide), an iPhone-class landscape viewport
   such as 844x390, and portrait rotation. Check safe areas and all HUD/menu
   overlays.
6. Verify pause/resume, hidden-tab auto-pause, restart, timer warning, zero with
   no ball, zero with a catch/INT/incompletion during final-ball grace, and a
   ball that exhausts the two-second grace.
7. Exercise every lane and outcome. Confirm the exact score, TD meter, current
   multiplier, run stats, accuracy, and longest streak against
   [scoring.md](scoring.md).
8. Clear `localStorage['pocket-vector-save-v1']` in a test profile and verify the
   first-run tutorial, then verify settings, personal best, and aggregate stats
   after reload.
9. Test audio after a fresh browser load, including autoplay unlock, loop,
   volume controls, mute, pause/ad suspension, and resume.
10. If an asset generator changed, run `npm run generate:all-assets`, inspect
    representative art/audio plus both manifests, and confirm a second
    generation is deterministic.
11. For Bounty Board changes, verify lifecycle call balance, host lock, guest and
    signed-in persistence, and viewed/dismissed/unavailable/error ad results in
    the uploaded environment. Only viewed may grant one 15-second continue.
12. Recheck platform score plausibility limits and update all affected docs
    before release.
