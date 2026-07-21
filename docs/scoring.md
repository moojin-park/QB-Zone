# Scoring and run rewards

`GameplayConfig`, `ScoringConfig`, and `GameSimulation.calculatePlayScore` are
authoritative for points. `CompletedRun.rewardBreakdown()` resolves the run's
immutable economy version and is authoritative for its completion, performance,
accuracy, and total coins. UI copy must present these rules without implementing
a second calculation.

## Lane points

| Target lane | Base points | Adrenaline gain |
| ----------- | ----------: | ---------------: |
| 15 yards    |         500 |               15 |
| 30 yards    |       1,000 |               35 |
| 45 yards    |       1,500 |               50 |
| End zone    |       2,500 |                0 |

A completion or touchdown awards its lane's base points. An incompletion awards
zero. Every interception applies this score adjustment:

```text
score after = max(0, score before - 250)
```

## Adrenaline meter

The meter ranges from 0 to 100. Successful passes add the lane value and clamp
at 100. An incompletion or interception resets the meter to zero.

When the meter is already full before a touchdown resolves, that touchdown
receives a 3,000-point TD Bonus. The end-zone catch does not itself add meter,
so a player must fill the meter with prior completions.

## Touchdown multiplier chain

Touchdowns within an active multiplier chain use these multipliers:

| Touchdown in chain | Multiplier |
| ------------------ | ---------: |
| First              |       1.00 |
| Second             |       1.25 |
| Third              |       1.50 |
| Fourth             |       2.00 |
| Fifth              |       2.50 |
| Sixth and later    |       3.00 |

For a touchdown:

```text
awarded points = round((2,500 + eligible TD Bonus) * touchdown multiplier)
```

A completed non-touchdown pass preserves the chain and its next touchdown
multiplier without advancing it. Only an incompletion or interception resets
the multiplier chain to zero.

## Statistics

Every resolved throw increments attempts exactly once. Completion percentage is
the rounded percentage of completions plus touchdowns divided by attempts. The
completed run also records touchdowns, incompletions, interceptions, longest
back-to-back touchdown streak, bonus touchdowns, and final score. A normal
completion breaks the back-to-back statistic even though it preserves the
touchdown multiplier chain.

## Gameplay coin reward

A natural run must contain at least three attempts to be reward eligible.
Abandoned and debug-preview runs receive no coins. One eligible run awards:

- 10 completion coins;
- 1 coin per 1,000 score, capped at 25 performance coins;
- 5 accuracy coins at 70% or better with at least 10 attempts.

The resulting range is 10–40 coins. The first eligible run also grants the
one-time 250-coin signing bonus. Run and signing rewards use deterministic
ledger IDs, so duplicate callbacks or retries cannot grant them twice.

The per-run breakdown resolves `RunConfiguration.economyVersion` against the
immutable supported rule set. Unsupported versions fail closed. For every
supported version, `RunRewardBreakdown.totalCoins` must equal the reward total
used by durable settlement. The one-time signing bonus is separate from this
per-run breakdown.

## Rewarded-ad cadence

Each eligible completed run advances the optional rewarded-ad counter. At five
runs, one offer may grant 100 coins after provider verification. Declining does
not consume the offer. The counter resets only in the same durable operation
that grants the verified reward; offers do not stack beyond one.

## Verification

Scoring changes require focused `GameCoreTests`, reward changes require
`EconomyAchievementTests` and persistence/economy coordinator coverage, and
the complete simulator suite must pass before release evidence is updated.
