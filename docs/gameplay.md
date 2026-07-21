# Gameplay contract

Pocket Vector is a 60-second, landscape arcade passing run. The native Swift
implementation under `ios/PocketVector/Game/` is authoritative.

## Input

1. Press anywhere in the unobstructed lower-field activation band.
2. Drag upfield toward open space.
3. Release ahead of a moving receiver.

The activation band spans the landscape safe width from the bottom safe-area
boundary through logical scene `y = 225`, covering the first two major yardage
markers. Pause and mute controls and the complete scorebug/feedback footprint
remain excluded. Only the initial press is constrained to this band; the drag
and release may continue anywhere upfield.

The release position selects the target. Gesture distance and elapsed time
determine release speed; a quick release produces a flatter, shorter flight and
a slow release produces a higher, longer arc. A drag shorter than 34 logical
pixels, a drag that does not move upfield, a canceled touch, or a second touch
does not create a throw.

Only one football is authoritative at a time. Input is disabled while textures
are preparing, during countdown, while paused, while a play resolves, and after
the run enters its final-ball state.

## Run lifecycle

The app validates the selected owned team, jersey, and football before creating
an immutable run configuration. The opponent is randomized from the other seven
teams, and uniform clash resolution chooses a readable defensive combination.

The gameplay lifecycle is:

```text
texture readiness -> 3-second countdown -> 60-second run
  -> final-ball grace (when needed) -> immutable completed run
  -> durable settlement -> results
```

The first gameplay launch is preceded by a two-page How to Play tutorial. The
Rules page explains the 60-second clock, completion and touchdown scoring, the
interception penalty, and Adrenaline / touchdown-multiplier behavior. The
Passing page presents three stages in order: Pick a spot, Throw to it, and Avoid
the defenders. Its gesture lesson starts on the quarterback, drags to open grass
away from defenders, and releases so the receiver runs under the throw. The
demonstration can be replayed; Reduced Motion keeps it on its initial static
state.

On a first run, Start Run durably persists tutorial completion before the run is
created or launched. Leaving early does not mark the tutorial complete. Settings
can reopen it for review without rewriting completion. Exiting an active run
uses the same durable completion path but marks the run abandoned and ineligible
for rewards.

## Simulation

- The simulation advances at a fixed 60 Hz step.
- Frame deltas are capped at 100 milliseconds before accumulation.
- One seeded `XorShift32` stream controls deterministic receiver and defender
  movement.
- Four receivers cross the 15-yard, 30-yard, 45-yard, and end-zone lanes.
- Three defenders patrol fixed depths and can intercept a flight segment.
- Collision uses swept ball motion so a long render frame cannot tunnel through
  a receiver or defender.
- Receivers spawn and despawn outside the widest supported field plate.

The deterministic core does not know about SwiftUI navigation, persistence,
coins, Game Center, StoreKit, ads, or telemetry.

## Field presentation

Gameplay renders four registered 1728 x 768 field textures in this order:
the neutral stadium base, the selected offense team's end-zone paint, that
team's flat midfield branding, and the shared field markings. All four use the
same bottom-center anchor, unit scale, and viewport-centered origin. They are
part of visual readiness, so the countdown cannot begin until the complete
field stack and run-uniform textures have preloaded.

The neutral base owns the grass, stadium, sidelines, and baked goalpost.
SpriteKit adds only retained gameplay elements such as pylons, officials,
characters, effects, and HUD above the field stack. Team field presentation is
cosmetic and never changes projection, collision, scoring, or input authority.

## Outcomes

A throw resolves exactly once as a completion, touchdown, incompletion, or
interception. A completed non-touchdown pass preserves the touchdown multiplier
chain, while an incompletion or interception resets it. An interception also
applies `max(0, score - 250)`. Back-to-back-touchdown statistics remain strictly
consecutive: any non-touchdown outcome resets that separate counter. A new
throw cannot begin until the resolution cooldown ends.

When regulation expires, no new throw can start. An already airborne ball may
finish within the bounded final-ball grace period; otherwise the run ends.

Scoring and coin rewards are documented separately in `scoring.md`.

## Pause and audio

The HUD exposes pause and mute controls inside the landscape safe area. Pause
freezes simulation and the game clock. A paused run publishes a live immutable
statistics snapshot containing attempts, successful completions (normal catches
plus touchdowns), rounded completion percentage, and touchdowns. The app-owned
paused presentation must provide explicit Resume and Exit Run actions. Resume
is idempotent, and gameplay touches never resume a paused run.

Exit Run from the paused presentation remains a confirmed abandon action.
Canceling that confirmation leaves the run paused. Confirmation creates at most
one immutable abandoned run, which must complete the normal durable settlement
path before navigation changes. Mute state affects music and sound effects and
persists through the profile settings model.

The gameplay snapshot requests bottom-edge system-gesture deferral only during
active play and final-ball resolution. It clears that request during countdown,
pause, results, and every non-gameplay state. The app-owned gameplay adapter
must apply the platform deferral; this reduces accidental exits but does not disable
the deliberate repeat gesture provided by iOS.

## Authoritative files

- `ios/PocketVector/Game/Core/GameplayConfig.swift`: run, lane, movement, throw,
  and score constants.
- `ios/PocketVector/Game/Core/GameSimulation.swift`: deterministic state
  transitions, collision resolution, outcomes, and scoring application.
- `ios/PocketVector/Game/Core/GameplaySession.swift`: immutable completed-run
  projection.
- `ios/PocketVector/Game/Rendering/GameScene.swift`: SpriteKit input,
  presentation, readiness, audio events, and completion callback.
- `ios/PocketVector/UI/LegacyGameplayAdapterView.swift`: SwiftUI/SpriteKit
  boundary and navigation handoff.
