# Bounty Board Arcade integration

The game talks to Bounty Board only through `ArcadePlatform`. The default build
mode is `StandalonePlatform`: gameplay, results, and local personal-best data
work without a host handshake, account, cloud save, or ad provider. The npm SDK
remains a production dependency so a Bounty Board upload can be built without a
code change.

## Boot wiring

Create the adapter once and inject it into the game controller. Do not import
`BBArcade` in simulation, rendering, input, HUD, or audio modules.

```ts
import { createArcadePlatform } from './game/platform';

const platform = createArcadePlatform({
  onRewardedAdStart: () => audio.pauseSynchronously(),
});

// Safe to await; the adapter resolves after a short timeout if no host answers.
await platform.initialize();
```

Call the lifecycle methods at these authoritative transitions:

- `loadingFinished()` once, after assets are ready and the title screen is
  interactive.
- `gameplayStart()` after the countdown and after a pause or rewarded continue.
- `gameplayStop()` on pause, timer expiry, ad start, and permanent run end.
- `submitScore(score)` only after authoritative integer score changes.
- `gameOver(finalScore)` only after the continue is declined, unavailable,
  dismissed, failed, or its one overtime period ends.

The adapter suppresses duplicate loading, start/stop, unchanged live score, and
final score calls. A `gameplayStart()` after a submitted final score begins a new
run and resets the per-run submission guard.

## Build modes and environment

The normal local or self-hosted artifact is standalone:

```bash
npm run build
```

Build the Bounty Board upload artifact with:

```bash
VITE_ARCADE_PLATFORM=bountyboard npm run build
```

Available build-time values:

| Variable                     | Meaning                                                           | Default                      |
| ---------------------------- | ----------------------------------------------------------------- | ---------------------------- |
| `VITE_ARCADE_PLATFORM`       | `standalone` or `bountyboard`                                     | `standalone`                 |
| `VITE_BB_ALLOWED_HOSTS`      | Comma-separated self-hosted production, staging, or preview hosts | empty                        |
| `VITE_BB_HOST_LOCK`          | Explicit host-lock override                                       | on for non-dev Bounty builds |
| `VITE_BB_SIGNED_HOST_LOCK`   | Request signed origin attestation                                 | `false`                      |
| `VITE_BB_REWARDED_TEST_MODE` | Force test ads for a test artifact                                | `false`                      |

Allowlist values may be plain hosts, `host:port`, or full HTTP(S) URLs. They are
validated, normalized to hosts, and deduplicated. Wildcards, credential-bearing
URLs, non-HTTP protocols, and malformed hosts are ignored. A configured host
also covers its subdomains according to the SDK.

The current 1.1.0 signature is:

```ts
BBArcade.lockToHost({
  allow: ['example.com', 'staging.example.com'],
  signed: false,
});
```

In type terms, it is `lockToHost({ allow?, signed?, onBlocked?, redirect? })`.
The Bounty adapter calls host lock synchronously before `init()`. Without a
custom `onHostBlocked`, the SDK supplies its blocking screen; if the game passes
its own callback, that callback must render a clear, non-crashing blocked-host
screen. Keep host lock off for the default standalone artifact, because its
purpose is to remain playable on arbitrary off-platform hosts.

## Rewarded overtime

The adapter prepares the documented placement and reward:

- Placement: `overtime_continue`
- Reward: `extra_15_seconds`
- Preparation timeout: 6 seconds
- Maximum granted continues: one per run (enforced by game state)

Only show the button when `prepared.status === 'ready'`. The call to `show()`
must be the first ad action in the player's click/pointer handler:

```ts
button.addEventListener(
  'click',
  () => {
    const resultPromise = prepared.show(); // synchronous; do not await first
    continueUi.setPending();
    simulation.freeze();

    void resultPromise.then((result) => {
      audio.resume();
      if (result.status === 'viewed') {
        game.grantRewardedContinue();
      } else {
        game.finishRunWithoutReward();
      }
    });
  },
  { once: true },
);
```

Do not insert an `await`, timeout, animation frame, network call, or unrelated
work before `show()`. The wrapper is one-shot and returns the same promise if
called twice. Only `status === 'viewed'` grants 15 seconds. Dismissed,
unavailable, timed-out, or errored ads grant nothing and must proceed to the
normal results screen. Production rewarded ads remain unavailable until Bounty
Board approves and allowlists the game.

## Persistence

Schema version 1 stores only durable, small data:

- Mute, music/SFX volume, and reduced-motion settings.
- Tutorial completion.
- Personal best.
- Aggregate run/pass/touchdown/interception/score counters.

It never stores an active run or ball positions. Hosted loads try cloud first,
then the local mirror when cloud storage is unsupported, logged out, empty,
malformed, rejected, or unavailable. Saves try cloud first and then update the
local mirror. Standalone mode uses only `localStorage`. All storage access is
caught because opaque or privacy-restricted browser contexts may deny it.

Unversioned/version-zero prototype data is migrated when recognizable. Future,
malformed, negative-counter, invalid-volume, or non-JSON data is ignored and the
game should use `createDefaultPersistedGameData()`.

## Score plausibility settings

The current maximum single scoring play is:

```text
(touchdown lane 2,500 + full-meter bonus 3,000) x maximum 3x streak = 16,500
```

The theoretical fastest configured ball flight is 430 ms. Assuming every play
immediately scores the maximum—even before the meter and streak could really
ramp—gives roughly 38,373 points/second and 2.88 million over the maximum
75-second rewarded run. The checked-in conservative caps are therefore:

- Maximum final score: `3,000,000`
- Maximum scoring rate: `45,000` per second
- Maximum supported run duration: `75,000` ms

These values live in `src/game/config/scoringConfig.ts`. Recalculate the caps
before submission whenever scoring, multipliers, minimum flight time, cooldown,
or rewarded duration changes.

## Submission verification

Before uploading a Bounty build:

1. Build with `VITE_ARCADE_PLATFORM=bountyboard` and the real self-hosted
   allowlist, if any.
2. Confirm the title screen calls `gameLoadingFinished()` once.
3. Confirm start, pause, timer expiry, ad, overtime resume, and permanent end
   produce balanced `gameplayStart()` / `gameplayStop()` signals.
4. Confirm live integer score changes arrive once and `gameOver()` arrives once
   after the final continue decision/overtime.
5. Test guest and logged-in identity, cloud save, cloud rejection, blocked
   storage, and malformed save data.
6. Test viewed, dismissed, unavailable, and error ad results. Only viewed may
   add 15 seconds, and a second continue must be impossible.
7. Verify the host handshake and blocked-host screen using the uploaded build.
8. Configure Bounty Board plausibility limits for a 3,000,000 score cap,
   45,000/second rate cap, and 75-second maximum run.

The adapter's automated tests use an injected SDK stub; the upload handshake,
Google ad availability, site lock, and Bounty cloud account behavior still need
manual verification in Bounty Board's test environment.
