# Pocket Vector production architecture

Status: implementation contract for version 1

Last updated: 2026-07-16

This document translates the approved release charter into ownership and data
boundaries. It is deliberately narrower than a feature specification: it says
which layer may change durable state, how a run settles, and which behavior must
remain available offline.

## Runtime ownership

```text
ProductionAppRuntime (one retained process graph)
  -> owned AppCoordinator task
       -> ProductionAppComposition
            -> LocalPlayerProfileRepository actor
                 -> atomic local profile store
                 -> durable local profile and economy operations
            -> dormant transactional CloudKit hydration,
               reconstruction, and incremental-publication seams
            -> future account-scoped bootstrap/coordinator
       -> GameplaySessionController
            -> one GameScene for one RunConfiguration
            <- one CompletedRun callback
  -> owned AppleDiagnosticsRuntime task
       -> privacy-safe OSLog and MetricKit adapters
  -> UIKit GameKit presentation handoff
```

- SwiftUI owns launch, navigation, menus, settings, locker, store, results, and
  service presentation.
- `ProductionAppRuntime` retains the composition graph and owns the only
  long-lived coordinator and diagnostics tasks. View teardown never leaves an
  unowned state-stream consumer behind; runtime teardown cancels both tasks.
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

## Authoritative presentation state

The coordinator accepts only complete `AuthoritativeAppStateSnapshot` values.
Every snapshot is bound to an immutable profile session and carries both player
and economy revisions. Same-session updates must be componentwise monotonic.
An unchanged player revision cannot carry changed player fields, and an
unchanged economy revision cannot carry changed balances, inventory ownership,
ledger state, or rewarded-ad eligibility. Inventory and rewarded-ad state
intentionally belong to both partitions because production mutations couple
them to durable economy operations.

The presentation channel creates a fresh subscription for each consumer and
replays its latest complete snapshot. It may coalesce complete projections, but
it must never carry transaction receipts, StoreKit deliveries, CloudKit deltas,
or ledger operations. Those remain lossless repository/service concerns.

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

## Cloud replica and economy authority

The implemented cloud foundation discovers private-zone record changes,
validates provider record names, filters internal operation markers, and binds
every replica to the current iCloud account, zone, schema scope, and authority
epoch. The replica checkpoint uses redundant primary and backup documents, a
durable watermark, accepted/pending two-phase authority metadata, an advisory
file lock, and bounded quarantine. A stale process, revoked epoch, corrupt
watermark, interrupted promotion, or mismatched account fails closed before it
can replace accepted state.

The CloudKit backend environment is a sealed build property. Debug selects
Development and Release selects Production through one configuration-specific
build setting that expands into both a compiler condition and the iCloud
container-environment entitlement. Missing, invalid, or ambiguous conditions
fail compilation. Shipping configuration uses only the sealed build value;
tests may select an environment only through a Debug-only seam. The environment
participates in the transport fingerprint and therefore separates Development
and Production checkpoint authority.

Durable economy history uses version 3 heads plus immutable ledger and reward
markers. Validation replays the complete ordered history and verifies canonical
revisions, batch positions, operation-ID uniqueness, per-revision bindings,
nonnegative balances, unlocks, rewarded-ad pairings, and the final accumulator.
Only the narrow, explicitly tested version 1 to version 2 legacy path is
accepted; incomplete or ambiguous histories never become spend authority.

The current transport scope identifier is version 2; record envelopes remain
version 3 and operation markers version 2. This is a deliberate pre-release
scope break. The fingerprint binds the complete transport, profile, and
economy contracts, including the build-sealed CloudKit environment, provider
address domains, and immutable-marker algorithms. Checkpoints carrying the
prior transport fingerprint are not migrated in place: their authority epoch
is revoked and Development data is reset or moved to versioned identifiers
before live integration.

## Transactional cloud hydration

A validated cloud replica is installed as one recoverable transaction. Fetch
and validation do not block gameplay. Immediately before installation, the
repository compares the exact profile session, profile ID, player/economy
revisions, and source digest; only then does it enter a narrow mutation gate.
A redundant immutable journal binds source and candidate profile envelopes,
the cloud account-derived profile and player identities, scope and epoch,
predecessor checkpoint, exact target checkpoint, transaction ID, and merge
policy version.

Installation first durably writes both immutable journal copies, then commits
and reloads the exact target checkpoint. While the outer account-generation
commit permit remains borrowed, the caller enters an authority-bound
checkpoint-freshness lease. The checkpoint store verifies the remembered
account, scope, and epoch, performs any checkpoint recovery outside the outer
file lock, then reacquires that lock and revalidates the exact accepted
checkpoint or exact durable absence with no pending publication. It holds the
checkpoint account lock while the synchronous profile-file mutation runs. Only
the borrowed lease may authorize candidate installation, predecessor-confirmed
abort, or target-confirmed journal cleanup; raw checkpoint observations remain
diagnostic and recovery values, not mutation authority. Both journal copies are
removed after the candidate is durable, and the repository may adopt the exact
installed candidate only after cleanup succeeds. Startup recovery runs before
ordinary `loadOrCreate`, accepts only the exact predecessor or target
checkpoint, and deterministically completes or cleans up the interrupted
transaction. A wrong account, profile binding, schema scope, authority epoch,
checkpoint state, or candidate digest can never install. The local repository
uses deterministic account-derived identities for cloud profiles; switching
iCloud accounts opens a separate profile and never silently merges identities.

The exact repository-adoption seam is implemented but dormant. It validates the
journal before file-system I/O, requires no journal or quarantine barrier,
requires both profile copies to equal the exact candidate, and then swaps only
the actor's document and canonical persisted artifact without rotating the
profile session or publishing UI state.

The process-local account-generation authority is also implemented but dormant.
It binds one opaque, nonpersistable token to the exact cloud account, all
account-derived service ownership, schema scope, and replica epoch. Exact
duplicate activation preserves the token; every account, scope, epoch,
invalidation/reactivation, or authority-instance transition mints a distinct
generation. Compare-and-swap invalidation cannot retire a newer generation. A
cancellation-safe FIFO gate keeps account transitions outside bounded local
commit, adoption, and publication work while preserving the exact outcome of
an admitted commit. Admission delivers a borrowed, noncopyable
`AccountGenerationCommitLease` bound to the exact authority instance and active
generation. It is Sendable only so the borrow can cross an actor boundary
during bounded commit work; callers cannot construct, copy, retain, or return
it. The admitted body preserves its exact success or error outcome, including
cancellation that arrives after admission. Network work is forbidden inside
that gate.

The scoped checkpoint-freshness seam is implemented but dormant. A
mutation-capable checkpoint store must be composed with the canonical
account-generation authority; an unbound store or a permit from a foreign
authority fails closed before checkpoint path derivation or I/O. The store
requires its exact epoch to be remembered locally, revalidates durable authority
before and after recovery, and invokes the synchronous callback while holding
the checkpoint account lock. The inner lease is noncopyable and non-Sendable
and exposes only its relationship to a hydration journal. Checkpoint publication
or revocation racing an admitted callback linearizes after that callback, while
a later accepted checkpoint rejects a stale journal before profile mutation.
The enforced lock order is checkpoint account lock followed by profile-file
lock.

Typed checkpoint fetching and publication are implemented but dormant. Release
code obtains `CloudReplicaScopedChangeFetcherV1` only from the complete
validated production cloud-write configuration. The wrapper derives the exact
replica scope and hard-codes `requireExisting`, so callers cannot pair an
asserted scope with an unrelated transport or request zone creation.

Cache-loss reconstruction begins only when durable accepted history exists and
no usable accepted checkpoint copy remains. Its sealed context owns the nil
cursor and every subsequent page, rejects a scope mismatch before network
access, and emits only a sealed full-snapshot artifact branded with the exact
account generation and accepted history.

Reconstruction is saved as a replacement cache baseline before the coordinator
starts a new ordinary fetch. It cannot directly authorize a hydration journal:
the durable accepted-history watermark proves the prior generation and digest,
but does not carry the full predecessor checkpoint identity required by the
journal.

Ordinary incremental publication begins only from one exact usable accepted
checkpoint; it cannot create a genesis checkpoint or reconstruct missing cache.
Its sealed context owns the predecessor cursor and all subsequent pages and
emits a result branded with the exact generation and predecessor. Saving either
artifact requires a fresh lease from the canonical authority with the same
opaque generation token, account, scope, and epoch. Ordinary save additionally
revalidates the exact durable predecessor and any pending candidate under the
account lock. Raw checkpoint save is private in Release and exposed only as a
Debug test seam.

Live composition now requires a separately sealed first-zone genesis path, a
repository hydration-mutation barrier, a durable one-time local-profile
account-claim transaction, outbound initial profile publication, and the
account-scoped runtime coordinator. The barrier must verify the exact source
and prevent gameplay, settings, or economy mutations from racing journal
creation and candidate installation. Existing hydration deliberately rejects
changing a local profile's account-derived identity, and the Release fetcher
deliberately cannot create a zone, so neither boundary may be widened as a
shortcut. A fetch context is minted under bounded generation admission,
network work occurs after leaving that gate, and durable publication later
reacquires a fresh lease that must match the context's opaque generation
provenance. The coordinator must then perform checkpoint publication, leased
profile mutation, journal cleanup, repository adoption, generation recheck,
and authoritative state publication in the documented crash-recoverable order.

Material hydration advances local player and economy revisions exactly once
without copying a remote root revision. A no-op merge does not advance either
revision. Validated cloud state must be installable without erasing valid
source-only runs, rewards, settings, or ownership; otherwise hydration rejects
the replica and retains the local source.

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
- Diagnostics: one process-owned, restartable FIFO input mailbox feeding
  privacy-safe `OSLog` categories and Apple MetricKit delivery; third-party
  crash reporting remains an explicit release decision.

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
- An unsigned archive may prove that Release compilation selected the
  Production CloudKit condition, but it does not prove codesigned entitlements.
  Before TestFlight, inspect the signed/exported app and verify the Production
  container environment plus the expected iCloud container identifiers and
  CloudKit services.
- The repository is iOS-only. Native asset sources and regeneration tools stay
  outside the shipping resource bundle, whose manifest must exactly match its
  physical files.
