# Gameplay and run flow

This document describes the implemented runtime in `src/app/GameApp.ts` and
`src/game/simulation/`. It is the behavior to preserve when changing screens,
timing, input, or platform integration.

## Core interaction

Pocket Vector is a lead-the-receiver passing game viewed from behind the
quarterback. Receivers run horizontally in four fixed depth lanes while three
slower defenders patrol sideline-to-sideline at intermediate depths. Defenders
reverse before their sprites leave the visible field instead of recycling from
offscreen.

To throw with a mouse, trackpad, stylus, or touchscreen:

1. Press inside the quarterback's on-screen rectangle.
2. Drag upfield. A destination X and stepped pixel trajectory arc track the pointer.
3. Release at the desired destination, normally ahead of a moving receiver.

The release destination maps into world X/depth coordinates. Release speed is
continuous rather than bucketed: faster releases shorten the flight and lower
the arc; slower releases lengthen the flight and raise the arc. The ball reaches
the destination's X/depth at 82% of its flight while still at catchable height.
If no player touches it, the final 18% descends at that same marked location so
the football lands on the displayed X instead of carrying beyond it.

The X may be placed directly on a receiver's visible body. Because screen-space
body height and field depth overlap in this camera, that marker can map to a
ground point beyond the receiver's fixed lane. The final descent therefore also
checks the ball against the receiver's projected catch rectangle. Players still
lead a receiver horizontally, but they do not need to compensate by aiming below
him just to make the catch register.

A gesture is accepted only when it:

- starts on the quarterback;
- travels at least 34 logical pixels;
- points upfield (`directionY < -0.08`).

Release speed shapes the pass instead of deciding whether it throws. A
sufficient-distance upfield drag always releases the ball; a speed at or below
the configured slow endpoint clamps to the highest, longest lob.

Only one pointer owns a gesture, only one ball may be active, and a short
post-play cooldown prevents accidental duplicate throws. Pointer cancellation
clears the gesture without throwing. If mouse or trackpad capture is lost after
a valid drag, the last sampled destination completes the release. An invalid
release shows the **SWIPE UPFIELD** prompt.

## Pass resolution

The fixed-step simulation advances receivers, defenders, and the ball before
checking swept collisions, which prevents a fast throw from tunneling through a
target between frames.

- A receiver catch occurs when the ball crosses that receiver's lane within its
  configured horizontal catch width and a world height of `0.08..0.92`.
- That swept lane check remains primary. Once the ball begins its final descent
  at the destination X, a ball visibly inside the same projected receiver catch
  rectangle also registers. This reconciles body-aimed X placement with what is
  shown on screen without widening defender collisions or normal flight.
- A catch in the touchdown/end-zone lane is a touchdown. Catches in the other
  three lanes are completions.
- Defender head, arm, torso, and hip zones intercept the ball. Explicit helmet
  top, hand, lower-leg, and foot regions are pass-through zones.
- A pass is incomplete when it reaches its trajectory end, travels beyond world
  X `+/-1.3`, or passes depth `1.06` without an earlier catch/interception.
- If more than one collision is possible in a simulation step, the earliest
  swept collision wins.

Receivers keep moving during ball flight, so the destination X is a lead point,
not a lock-on target.

## Run phases

The authoritative phases are:

```text
loading
  -> title
  -> instructions (first Play, or How to Throw)
  -> countdown
  -> playing <-> paused
  -> resolving-final-ball <-> paused
  -> continue-offer -> rewarded-ad -> playing (viewed only)
  -> results
```

Important transition details:

- Assets load before `loading -> title`. Missing optional audio/art is reported
  without preventing the title screen from becoming usable.
- Pressing **Play 60** prepares a fresh run. A first-time player sees the
  instructions; tutorial completion is then persisted. Returning players enter
  the countdown directly.
- The countdown lasts three seconds. Gameplay time, music, and the platform
  gameplay session start only after it reaches zero.
- Pause stores the active phase and stops platform gameplay/audio. Resume
  restores either `playing` or `resolving-final-ball`. Hiding the document while
  actively playing also pauses the run.
- Restart replaces the run state, retains settings and development options,
  clears the prepared ad/final-submission guards, and starts a new countdown.
- Results are final for that run: score submission, aggregate stats, personal
  best, and persistence happen once.

## Timer and final ball

- Regulation starts at exactly `60,000 ms`.
- Time is authoritative only during `playing`; loading, title, instructions,
  countdown, pause, ad, continue offer, and results consume no gameplay time.
- The HUD rounds remaining time up to a displayed whole second.
- At 10 seconds, the HUD/field warning activates and a continue ad may begin
  preparing in the background.
- When regulation reaches zero, the phase becomes `resolving-final-ball`. A new
  throw cannot begin.
- If a ball is already in flight, it may resolve normally for up to `2,000 ms`.
  The run proceeds as soon as that pass resolves; if it does not resolve within
  the grace period, the ball is removed.
- If no ball is active at zero, the run is ready to finish immediately.

The 100 ms browser-frame delta cap prevents a suspended or overloaded tab from
consuming a large chunk of the clock in one render frame. The simulation itself
runs at a fixed 60 Hz step.

## Rewarded continue flow

The continue is optional platform behavior; the standalone game remains fully
playable without it.

1. At 10 seconds remaining, the Bounty adapter may prepare placement
   `overtime_continue` with reward `extra_15_seconds`.
2. After the final ball, a continue offer appears only if the preparation is
   ready and the run has not used a continue.
3. The player may finish immediately or press **Watch ad for +15 seconds**.
4. `show()` is invoked synchronously from that button handler. Gameplay and
   audio remain paused while the result is pending.
5. Only `status === 'viewed'` grants exactly 15 seconds, resumes gameplay, and
   marks overtime used.
6. Dismissed, unavailable, timed-out, or errored ads grant no time and proceed
   to results.
7. A run can receive at most one continue. When overtime reaches zero and its
   final ball resolves, the run finishes without another offer.

Standalone ad preparation always reports unavailable, so standalone runs skip
the offer and proceed directly to results. Production rewarded ads may also be
unavailable until the uploaded game is approved and allowlisted by Bounty
Board.

## Settings and persistence

The pause screen exposes music volume, SFX volume, reduced motion,
high-contrast aim X, and Adaptive/Classic/Wide playfield fit. Mute is also
available in the gameplay HUD.

The versioned persistent payload stores mute, music/SFX volume, reduced motion,
tutorial completion, personal best, and aggregate stats. It deliberately does
not save a live run or ball position. High-contrast aim and playfield fit are
currently run-local settings and are not part of persistence schema version 1.

## Results

The results screen reports final score, touchdowns, longest touchdown streak,
completed passes (ordinary completions plus touchdowns), incompletions,
interceptions, rounded completion accuracy, whether overtime was used, and the
persisted personal best.

See [scoring.md](scoring.md) for the exact point, meter, and multiplier rules.
