# Pocket Vector production architecture

Status: implementation contract for version 1

Last updated: 2026-07-15

This document translates the approved release charter into ownership and data
boundaries. It is deliberately narrower than a feature specification: it says
which layer may change durable state, how a run settles, and which behavior must
remain available offline.

## Runtime ownership

```text
SwiftUI AppCoordinator
  -> PlayerRepository actor
       -> atomic local profile store
       -> CloudKit private-zone adapter
       -> Game Center queue
       -> StoreKit transaction coordinator
       -> rewarded-ad verification coordinator
       -> telemetry and diagnostics clients
  -> GameplaySessionController
       -> one GameScene for one RunConfiguration
       <- one CompletedRun callback
```

- SwiftUI owns launch, navigation, menus, settings, locker, store, results, and
  service presentation.
- `PlayerRepository` is the only production authority allowed to mutate player
  ownership, selections, records, coins, ledger entries, achievement progress,
  or pending service queues.
- SpriteKit receives an immutable `RunConfiguration`. It renders and simulates
  gameplay, then emits one immutable `CompletedRun`.
- SpriteKit never writes the profile, grants coins, unlocks inventory, submits
  Game Center data, starts purchases, presents advertisements, or chooses app
  navigation.
- SDK adapters never mutate a balance directly. They report verified outcomes
  to the repository, which applies an idempotent ledger mutation.

## App flow

The coordinator has one top-level state at a time:

```text
launching
  -> menu(home | teams | store | leaderboard | achievements | settings | privacySupport)
  -> gameplay(runConfiguration)
  -> settlingRun(runID)
  -> results(runPresentation)
```

Starting a run validates the current owned offense team, its remembered owned
jersey, and the selected owned football. The matchup generator selects a
defense from the other seven teams using the run seed, then chooses the
contrast-safe primary or alternate defensive jersey. Defensive jersey choice
does not depend on player ownership.

`GameScene` begins its countdown automatically after it is presented. When the
timer and final-ball grace period finish, the scene emits one `CompletedRun`.
The coordinator enters `settlingRun` and disables duplicate navigation until
the repository returns the existing or newly created settlement. Results use
that settlement snapshot. Play Again creates a new run ID, seed, and randomized
opponent; Home never grants an additional reward.

## Durable profile

The local profile is a versioned Codable envelope written atomically. It holds:

- stable profile and device identifiers;
- stamped settings and player selection;
- owned teams, jerseys, and footballs;
- immutable completed runs keyed by `RunID`;
- immutable coin ledger entries keyed by `LedgerEntryID`;
- confirmed and pending coin state;
- derived career records and personal best;
- achievement progress;
- rewarded-ad eligibility state;
- pending CloudKit and Game Center work.

Writes use a temporary file plus atomic replacement. The previous valid
document is retained as a backup. Decode or validation failure attempts backup
recovery; unrecoverable data is quarantined instead of overwritten silently.
Schema migrations are explicit, deterministic, and covered by fixture tests.

The default profile owns the four approved free teams and their primary
jerseys, the standard football, and selects Nova City. It begins with zero
coins. Music defaults to `0.38`, SFX to `0.72`, mute and reduced motion are off,
and the tutorial is incomplete.

## Exactly-once run settlement

Settlement is serialized inside `PlayerRepository`:

1. Reject debug previews and mark abandoned runs without rewards.
2. If the `RunID` already exists, return its stored settlement unchanged.
3. Validate statistics, score, finish reason, and configuration identifiers.
4. Store the immutable run record.
5. Apply career aggregates and personal best once.
6. For a reward-eligible run, create `run/<run-id>/reward` as a pending positive
   ledger entry and advance rewarded-ad eligibility once.
7. On the first reward-eligible run only, also create `signing-bonus/v1` for 250
   pending coins.
8. Evaluate all eight achievements and coalesce pending Game Center progress.
9. Persist the complete transaction atomically before returning results.

Duplicate callbacks, relaunch retries, sync redelivery, and repeated button
taps must all return the same settlement without changing statistics, coins,
ad eligibility, achievements, or queues.

## Coin authority

`Int64` is used for every coin amount. All mutations have deterministic ledger
identifiers:

| Mutation               | Identifier form                         |
| ---------------------- | --------------------------------------- |
| Gameplay payout        | `run/<run-id>/reward`                   |
| Signing bonus          | `signing-bonus/v1`                      |
| Rewarded advertisement | `rewarded-ad/<provider-transaction-id>` |
| StoreKit consumable    | `storekit/<transaction-id>`             |
| Catalog unlock         | `unlock/<catalog-item-id>`              |

Positive gameplay entries may exist locally as pending coins. Pending coins are
visible but cannot be spent. Purchases, advertisement delivery, and new catalog
spends require a current private-iCloud economy state. A catalog debit and its
inventory unlock commit together; neither may survive alone. Equipping an
already owned cosmetic remains available offline.

StoreKit transactions are finished only after the durable ledger confirms that
their transaction ID was committed or already existed. Rewarded-ad eligibility
clamps at five valid runs, does not bank additional offers, survives a decline,
and resets only in the same durable operation that grants the verified 100
coins.

## Offline behavior

| Behavior                                         | Offline policy                                                                 |
| ------------------------------------------------ | ------------------------------------------------------------------------------ |
| Core gameplay                                    | Available                                                                      |
| Settings and tutorial state                      | Available and queued for merge                                                 |
| Equip an already owned team, jersey, or football | Available                                                                      |
| Completed-run record and gameplay reward         | Stored locally; reward remains pending                                         |
| Spend coins or unlock a new item                 | Requires current iCloud economy state                                          |
| Buy a coin pack                                  | Requires current iCloud economy state                                          |
| Watch and receive a rewarded advertisement       | Requires consent, ad readiness, verification, and current iCloud economy state |
| Game Center authentication                       | Optional; never blocks gameplay                                                |
| Leaderboard and achievements                     | Highest pending values queue for later submission                              |

An iCloud account change closes the current sync context and opens a separate
account-scoped profile. Data from two iCloud identities is never merged
silently. Game Center pending queues are likewise scoped to the authenticated
Game Center player.

## Cloud merge rules

- Immutable runs and ledger entries merge by unique identifier.
- Personal best is the maximum valid score.
- Career aggregates are recomputed from the unique immutable run set.
- Settings and selections use field-level last-writer-wins stamps with device
  ID as a deterministic tie-breaker.
- Merged cosmetic selections are revalidated against merged ownership.
- Economy heads and debits use CloudKit change-tag protection and retry after a
  fresh read; balances are never resolved with last-writer-wins.
- Pending coins become confirmed only after their ledger entries are committed
  to the private zone.

Private CloudKit protects normal synchronization and two-device conflicts. It
is not a trusted anti-cheat server; version 1 accepts that limitation while
keeping all scoring and cosmetic purchases free of gameplay advantage.

## Platform service contracts

- Game Center: authentication state, presenter handoff, maximum pending global
  score, maximum pending achievement percentage, account-scoped reconciliation,
  leaderboard presentation, and achievement presentation.
- StoreKit: localized product loading, verified transaction stream, unfinished
  transaction recovery, account-token validation, durable delivery, and finish.
- Rewarded ads: consent-blocked/loading/ready/showing/reward-pending/unavailable
  states, explicit presentation, pause/resume hooks, and server-verified reward.
- Telemetry: coarse, deduplicated product events with no player aliases, raw
  profile identifiers, provider transaction identifiers, exact balances, or
  detailed play history.
- Diagnostics: privacy-safe `OSLog` categories and Apple MetricKit delivery;
  third-party crash reporting remains an explicit release decision.

Real adapters and in-memory fakes implement the same contracts. Menus and tests
must support loading, unavailable, offline, pending, restricted, declined, and
retry states without blocking gameplay.

## Integration guardrails

- Only the integration owner edits `project.pbxproj`, app entry points, or
  shared gameplay files during parallel work.
- Each implementation wave lands with focused tests and a full native-suite run.
- Resource, capability, dependency, or Release-composition changes also require
  an unsigned archive before commit.
- Production IDs, entitlements, SDK credentials, ad units, CloudKit schema, and
  App Store Connect records remain injected configuration, never test literals
  embedded in a Release build.
- The repository is iOS-only. Native asset sources and regeneration tools stay
  outside the shipping resource bundle, whose manifest must exactly match its
  physical files.
