# Scoring and run rewards

`GameplayConfig`, `ScoringConfig`, and `GameSimulation.calculatePlayScore` are
authoritative for points. `EconomyConfiguration` and `RunRewardCalculator` are
authoritative for coins. UI copy must present these rules without implementing
a second calculation.

## Lane points

| Target lane | Base points | Adrenaline gain |
| ----------- | ----------: | ---------------: |
| 15 yards    |         500 |               15 |
| 30 yards    |       1,000 |               35 |
| 45 yards    |       1,500 |               50 |
| End zone    |       2,500 |                0 |

A completion or touchdown awards its lane's base points. Incompletions and
interceptions award zero.

## Adrenaline meter

The meter ranges from 0 to 100. Successful passes add the lane value and clamp
at 100. An incompletion or interception resets the meter to zero.

When the meter is already full before a touchdown resolves, that touchdown
receives a 3,000-point TD Bonus. The end-zone catch does not itself add meter,
so a player must fill the meter with prior completions.

## Touchdown streak multiplier

Consecutive touchdowns use these multipliers:

| Touchdown in streak | Multiplier |
| ------------------- | ---------: |
| First               |       1.00 |
| Second              |       1.25 |
| Third               |       1.50 |
| Fourth              |       2.00 |
| Fifth               |       2.50 |
| Sixth and later     |       3.00 |

For a touchdown:

```text
awarded points = round((2,500 + eligible TD Bonus) * streak multiplier)
```

Any non-touchdown outcome resets the touchdown streak. Normal completions keep
the score but reset that streak.

## Statistics

Every resolved throw increments attempts exactly once. Completion percentage is
the rounded percentage of completions plus touchdowns divided by attempts. The
completed run also records touchdowns, incompletions, interceptions, longest
touchdown streak, bonus touchdowns, and final score.

## Gameplay coin reward

A natural run must contain at least three attempts to be reward eligible.
Abandoned and debug-preview runs receive no coins. One eligible run awards:

- 10 completion coins;
- 1 coin per 1,000 score, capped at 25 performance coins;
- 5 accuracy coins at 70% or better with at least 10 attempts.

The resulting range is 10–40 coins. The first eligible run also grants the
one-time 250-coin signing bonus. Run and signing rewards use deterministic
ledger IDs, so duplicate callbacks or retries cannot grant them twice.

## Rewarded-ad cadence

Each eligible completed run advances the optional rewarded-ad counter. At five
runs, one offer may grant 100 coins after provider verification. Declining does
not consume the offer. The counter resets only in the same durable operation
that grants the verified reward; offers do not stack beyond one.

## Verification

Scoring changes require focused `GameCoreTests`, reward changes require
`EconomyAchievementTests` and persistence/economy coordinator coverage, and
the complete simulator suite must pass before release evidence is updated.
