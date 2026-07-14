# Scoring rules

`src/game/config/scoringConfig.ts` and
`src/game/simulation/scoring.ts` are authoritative for points, TD Bonus, and
touchdown streaks.

## Lane values

| Result lane          | Base points | TD Bonus meter gain |
| -------------------- | ----------: | ------------------: |
| Short / 15           |         500 |                   1 |
| Medium / 30          |       1,000 |                   2 |
| Deep / 45            |       1,500 |                   3 |
| Touchdown / end zone |       2,500 |                   4 |

An incompletion or interception awards 0 points.

## TD Bonus meter

- The meter begins at `0` and is full at `12`.
- Every successful completion adds the caught lane's meter gain, capped at 12.
- An incompletion or interception immediately resets the meter to 0.
- Ordinary completions do not spend a full meter and do not receive the
  3,000-point TD bonus.
- A touchdown receives the 3,000-point bonus only when the meter was already
  full before that touchdown. Filling the meter with the touchdown itself does
  not retroactively activate the bonus for that play.
- A successful play leaves a full meter full. It remains active until an
  incompletion or interception resets it.

The pre-play check is intentional. For example, a meter at 8 gains 4 from a
touchdown and reaches 12, but that touchdown has no TD bonus. The next touchdown
can receive the bonus if no miss/interception occurs first.

## Touchdown streak multiplier

The touchdown multiplier depends on the number of consecutive touchdowns
completed before the current touchdown:

| Consecutive touchdown being scored | Multiplier |
| ---------------------------------- | ---------: |
| First                              |         1x |
| Second                             |      1.25x |
| Third                              |       1.5x |
| Fourth                             |         2x |
| Fifth                              |       2.5x |
| Sixth and later                    |         3x |

Only touchdowns advance the streak. Any non-touchdown result—including a
successful short, medium, or deep completion—resets the current touchdown streak
to zero. The longest streak reached during the run remains in the results stats.

## Award formula

For an ordinary completion:

```text
awarded points = lane base points
```

For a touchdown:

```text
bonus = meter was full before play ? 3,000 : 0
awarded points = round((2,500 + bonus) x touchdown multiplier)
```

The multiplier applies to both the touchdown lane's 2,500 base points and an
active 3,000-point TD Bonus. The result is rounded to the nearest integer before
being added to the run total.

## Touchdown examples

| Situation                               |            Calculation |  Award |
| --------------------------------------- | ---------------------: | -----: |
| First TD, meter not full                |              2,500 x 1 |  2,500 |
| Second consecutive TD, meter not full   |           2,500 x 1.25 |  3,125 |
| Fourth consecutive TD, meter not full   |              2,500 x 2 |  5,000 |
| First TD with active bonus              |    (2,500 + 3,000) x 1 |  5,500 |
| Second consecutive TD with active bonus | (2,500 + 3,000) x 1.25 |  6,875 |
| Sixth-or-later TD with active bonus     |    (2,500 + 3,000) x 3 | 16,500 |

The maximum configured single-play award is therefore 16,500 points.

## Score reporting and plausibility limits

The platform receives a live score only after an authoritative score change;
0-point outcomes do not submit a changed score. The final score is a
non-negative safe integer and is submitted once when the run permanently ends.

The checked-in conservative platform limits are:

- maximum final score: `3,000,000`;
- maximum score rate: `45,000` points/second; and
- maximum supported rewarded run: `75,000 ms`.

These limits assume the configured minimum 430 ms flight and the maximum 15
rewarded seconds. Recalculate all three before a Bounty Board submission if
points, multipliers, minimum flight time, cooldown, regulation time, or rewarded
time changes. See
[bounty-board-integration.md](bounty-board-integration.md#score-plausibility-settings)
for the current rationale.

## Duplicate configuration warning

`PASSING_LANES` in `src/game/config/gameplayConfig.ts` repeats each lane's point
and meter values for descriptive consistency and tests, but the score calculator
reads `SCORE_CONFIG.lanes`. Keep both tables identical when tuning. A mismatch
can make UI/gameplay documentation disagree with awarded points even if the game
still builds.
