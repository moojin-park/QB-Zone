# Pocket Vector production architecture

Status: implementation contract for version 1

Last updated: 2026-07-18

Implementation baseline: `3ed7598`, the combined Art and Technical gameplay
presentation integration, including the active layered team-field renderer,
refined paused-run controls, explicit gameplay-presentation bridge, online-only
commerce composition, canonical V4 cloud-profile seed, and StoreKit,
player-scoped Game Center, and rewarded-ad foundations. Gameplay renders the
registered neutral base, selected-team paint, and universal markings before
placing actors and the HUD above the field stack.

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
            -> ProductionAccountRuntimeRouter
                 -> durable local-to-cloud claim and committed association
                 -> account-bound CloudKit checkpoint preparation/hydration
                 -> DurableEconomyCoordinator
                 -> StoreKitRuntimeCoordinator
                 -> OnlineCommerceCoordinator
       -> GameplaySessionController
            -> one GameScene for one RunConfiguration
            <- GameplaySceneSnapshot relay after presentation mount
            -> explicit Resume and confirmed Exit Run requests
            <- one CompletedRun callback
  -> owned AppleDiagnosticsRuntime task
       -> privacy-safe OSLog and MetricKit adapters
  -> UIKit GameKit presentation handoff (retained seam; not connected)
```

The following foundations remain outside the retained live runtime graph:

```text
GameCenterDeliveryCoordinator
  -> exact player-bucket preparation, single-flight submission,
     same-player revalidation, and capability-bound acknowledgement
RewardedAdVerificationClient
  -> challenge preparation, server-status correlation,
     process-only verified claim, and durable-delivery request
RewardedAdRecoveryCoordinator
  -> challenge-only two-copy journal, authenticated status recovery,
     exact durable-delivery cleanup, and permanent quarantine barrier
```

`ProductionAppRuntime` advertises purchases and private-cloud sync only when
the complete validated CloudKit and StoreKit configuration can construct the
concrete account runtime graph. Missing or invalid configuration keeps both
capabilities unavailable without blocking local gameplay. Game Center and
rewarded-ad coordinators are not yet retained.

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

`privacySupport` remains a coordinator destination, reached through Settings.
The main menu does not require a separate direct Privacy and Support control.

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

The canonical local envelope is version 4. Versions 1 through 3 stored global
Game Center maxima; migration preserves those values only in durable unbound
quarantine. Version 4 stores at most eight sparse player-bound maxima buckets
plus one unbound bucket. Before Foundation decoding, bounded raw-JSON validation
rejects duplicate decoded member names. Queue decoding also rejects duplicate
typed keys and mixed-version fields. Bound score and achievement maxima may not
exceed locally earned career and achievement authority.

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
8. Evaluate all eight achievements and enqueue newly earned achievement
   progress and natural-completion score into unbound Game Center quarantine.
   Until a proof-bearing Game Center identity spans run start and settlement,
   settlement never assigns that work to whichever player later authenticates.
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

These durability invariants are composed into the configured production
runtime. Every catalog spend and coin-pack request performs a fresh provider
account and network probe, confirms pending gameplay credits, refreshes and
installs the validated authoritative replica, and revalidates again immediately
before the atomic debit or StoreKit sheet. Offline, signed-out, restricted,
stale-account, and connection-loss results use the existing online-only alert;
they do not debit, grant ownership, enqueue a purchase, or open StoreKit.
Production identifiers and App Store product records remain injected release
configuration, so the current repository configuration continues to fail
closed until those values are supplied. Rewarded-ad eligibility is durable
local state, but the ad SDK,
consent runtime, authenticated production verification transport and
server-side-verification backend, provider-transaction deduplication, recovery
coordinator, and retained delivery orchestration are not composed.

The dormant rewarded-ad recovery foundation persists only one immutable
verification challenge in two exact copies under the shared profile transaction
lock. Canonical encoding, exact-shape and duplicate-key preflight, bounded
identifiers, JSON depth and token limits, a 16 KiB document cap, and bounded
quarantine prevent ambiguous or attacker-shaped bytes from becoming authority.
One valid copy repairs the other byte-for-byte; valid unequal copies fail
closed. Invalid evidence is preserved in bounded quarantine, and its presence
is a permanent barrier to a new attempt until a future explicit repair policy.

Installation requires the exact durable owner and original presentation
session. Recovery and status handling require the pinned durable owner;
delivery additionally requires the current profile session. Cross-owner
evidence is never status-polled, repaired, quarantined, or deleted. Relaunch
never re-presents the ad: it re-polls authenticated, replay-stable status and
accepts only a sealed checked-status observation. Journal deletion requires
either an authenticated terminal rejection or a sealed acknowledgement of
exact durable economy delivery. Persisted bytes never include a verified
receipt, provider transaction, transient session, or delivery acknowledgement.
An ambiguous last-copy write or removal is repeated with a fresh durable file
or parent-directory synchronization; observation alone is not proof. Real
constructors remain fileprivate in Release, with only Debug test injection
exposed.

## Offline behavior

| Behavior                                         | Offline policy                                                                 |
| ------------------------------------------------ | ------------------------------------------------------------------------------ |
| Core gameplay                                    | Available                                                                      |
| Settings and tutorial state                      | Available and queued for merge                                                 |
| Equip an already owned team, jersey, or football | Available                                                                      |
| Completed-run record and gameplay reward         | Stored locally; reward remains pending                                         |
| Spend coins or unlock a new item                 | Requires current iCloud economy state                                          |
| Buy a coin pack                                  | Requires current private-iCloud authority; no StoreKit sheet opens offline                                              |
| Watch and receive a rewarded advertisement       | Not enabled; dormant recovery is implemented, while live delivery requires consent, SDK readiness, authenticated server verification, retained orchestration, and current private-iCloud economy authority |
| Game Center authentication                       | Not connected; future authentication remains optional and never blocks gameplay                                      |
| Leaderboard and achievements                     | Exact player-bound maxima may later submit; release policy also authorizes one durable claim of unbound maxima to the first authenticated player |

An iCloud account change closes the current sync context and opens a separate
account-scoped profile. A known profile from one iCloud identity is never
merged into another identity. A previously unbound installation profile is
automatically claimed on its first iCloud association, and offline changes
automatically reconcile whenever that same account returns. Source profiles
remain preserved until the claimed or merged cloud state is durably verified.

Game Center bound buckets are scoped to the exact authenticated player. The
current foundation keeps unknown-provenance work in a separate unbound
quarantine and exposes no claim API yet. Release policy authorizes that future
live integration to claim the unbound score and achievement maxima exactly once
to the first successfully authenticated player, durably preventing a later
player from claiming the same values. Offline work carrying a known player
identity remains player-bound and queues for later submission.

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

The release policy requires automatic reconciliation in the common path. A
first iCloud association combines the canonical unbound installation profile
with any valid private profile for that account, and later same-account
reconnections merge offline work without prompting. Account changes never
combine profiles belonging to different known iCloud identities.

## Initial cloud profile seed

The canonical V4 cloud-profile seed is an account-neutral, one-way `Encodable`
description of an exact canonical local artifact. It independently validates
the source bytes, digest, envelope, profile invariants, collection and identifier
bounds, Game Center queues, initial inventory, runs, ledger, pending credits,
settings, and selection. It deterministically classifies the source as an empty
economy that may be publishable, pending credits that require projection, or
history and ownership that must follow the approved first-association and
same-account reconciliation policy.

The seed is facts only. It does not claim a local profile, publish or write
CloudKit data, bind an iCloud account, Game Center player, profile session, or
transport authority, or compose live Cloud behavior. Its digest is integrity
identity, not mutation authority. Release policy now authorizes the one-time
local-to-cloud claim and automatic same-account reconciliation described above;
their implementation, outbound record construction, publication, and retained
account-scoped runtime remain separate gates.

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
and validation do not block gameplay. Immediately before admission, the
repository revalidates the active session, current document, canonical
persisted source bytes and digest, profile ID, player and economy revisions,
full journal, and transaction-store directory. The store claims the physical
directory identity before waiting for its file lock, then synchronously
installs the actor-owned barrier and revalidates that identity under the lock
before writing the journal. A proven pre-claim failure installs no barrier;
every post-claim failure retains it. Filesystem aliases therefore converge on
one admission decision.

The barrier blocks every profile, economy, settings, and selection mutation
and every operation that can mint mutation authority. Account invalidation may
still retire the repository session, but it cannot mutate profile state or
release the barrier. Once the pending physical claim succeeds, the barrier
remains installed across cancellation, account invalidation, lock contention,
and post-claim ambiguity. Retry is actor-mediated: the repository reuses its
one stored recovery handle only after revalidating the exact source, session,
journal, and store, and never issues a second capability. A confirmation does
not itself release the barrier. The target path clears only after successful
exact-candidate adoption; the predecessor path clears only after repository
acceptance of a sealed abort confirmation against the unchanged source.

A redundant immutable journal binds the source and candidate profile
envelopes, cloud account-derived profile and player identities, scope and
epoch, predecessor checkpoint, exact target checkpoint, transaction ID, and
merge policy version.

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
installed candidate only after cleanup succeeds. If final journal removal is
ambiguous, no release proof is minted. A live-handle retry may reconcile
durable absence but returns no confirmation and cannot release the barrier;
startup recovery is rejected while any live admission identity remains. Only
after the actor and every retained handle are gone may the account coordinator
invoke a later startup pass before ordinary `loadOrCreate`.

Startup recovery is a distinct diagnostic-only path. It rejects any pending,
ready, or attempting live admission, including filesystem aliases. When an
exact durable journal exists, only its exact predecessor or target checkpoint
can authorize deterministic abort or cleanup, and both profile copies must
match the journal's corresponding source or candidate. When no journal or
quarantine evidence exists, startup may return only diagnostic
`noDurableJournal`. It never installs a candidate, releases a live actor
barrier, or turns an ambiguous observation into mutation authority. A wrong
account, profile binding, schema scope, authority epoch, checkpoint state, or
candidate digest can never install. The local repository uses deterministic
account-derived identities for cloud profiles; switching iCloud accounts opens
a separate profile and never silently merges identities.

The exact repository-adoption seam is active in configured account composition. Adoption first
matches the active capability, exact journal and session, sealed target-cleanup
confirmation, and unchanged persisted source. The file store then requires no
journal or quarantine barrier and both profile copies to equal the exact
candidate. Only after account and profile validation does the actor swap its
document and canonical persisted artifact; the session is not rotated and UI
state is not published. Every failed validation retains the barrier.

The process-local account-generation authority is active in configured account composition.
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

The scoped checkpoint-freshness seam is active in configured account composition. A
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

Typed first-zone genesis publication is active for an eligible first association. Genesis begins
with an account-generation-bound metadata preflight and a durable reservation
written before network access. Reservation state advances from
`reservedBeforeNetwork` to `networkMayHaveBeenInvoked`; a process registry keyed
by the physical authority directory and lock shares bounded reservation
issuance and permits only one live network attempt across aliases. A zero or
newly issued duplicate reservation identifier, attempt-sequence overflow, or
exhaustion of the bounded process issuance history fails closed; recovery
deliberately retains the exact durable reservation identifier.

The sealed genesis context is one-shot. Only the nil-cursor request of attempt
one may ask CloudKit to create the zone; continuation pages require the existing
zone. After an ambiguous attempt, a separately minted recovery context durably
increments the monotonic attempt sequence before network access, and every
recovery request uses `requireExisting`, so zone creation is never replayed.
Generation-one checkpoint save requires the exact account generation, account,
scope, epoch, reservation, attempt sequence, and live save lease, then consumes
the reservation under the authority lock.

Typed checkpoint fetching and publication are active for configured account refresh. The
ordinary incremental and cache-loss reconstruction wrappers derive the exact
replica scope from the complete validated production cloud-write configuration
and hard-code `requireExisting`, so callers cannot pair an asserted scope with
an unrelated transport or request zone creation. The raw transport also rejects
zone creation unless the sealed first-zone context presents its opaque permit.

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

Live composition performs a durable one-time local-profile account-claim
transaction, outbound initial profile publication, and account-scoped runtime
activation. It uses the sealed first-zone genesis and repository hydration
barrier without widening either authority. A redundant committed-association
marker reopens the exact account-derived target before local bootstrap; source
and target copies are repaired only from validator-clean lineage, while
different-account, rollback, replacement, and ambiguous evidence fail closed.

A fetch or publication context is minted under bounded generation admission,
network work occurs after leaving that gate, and each durable save later
reacquires fresh matching authority. The coordinator must revalidate the exact
checkpoint, profile, journal, adoption, account generation, and repository
state in crash-recoverable order, then publish authoritative state only after
all required profile and checkpoint durability is proven.

Material hydration advances local player and economy revisions exactly once
without copying a remote root revision. A no-op merge does not advance either
revision. Validated cloud state must be installable without erasing valid
source-only runs, rewards, settings, or ownership; otherwise hydration rejects
the replica and retains the local source.

Hydration preserves every existing player-bound Game Center bucket. Derived
increases whose Game Center provenance is unknown are added only to unbound
quarantine; a no-op merge manufactures no unbound work. Hydration never claims
unbound work for an authenticated player.

## Platform service contracts

- Game Center foundation, dormant: canonical V4 stores sparse maxima under
  exact Game Center player IDs plus a separate unbound quarantine. Preparation
  freezes one exact player bucket; delivery is single-flight, revalidates the
  player before and after submission, and acknowledges only with the exact
  process capability. Unbound work is never submitted. Release exposes no
  delivery-coordinator construction path until a trusted in-file GameKit
  factory and retained composition are added.
- StoreKit online-commerce composition: the runtime owns exactly one account/session
  generation, installs transaction updates before unfinished recovery, loads
  the exact four configured consumables, serializes purchase presentation,
  suppresses stale callbacks, and awaits producer shutdown during account
  replacement. Transactions finish only after durable delivery. The retained
  runtime supplies account-session sourcing, private-cloud economy authority,
  lifecycle management, and bounded UI outcomes. Permanent product identifiers
  and App Store records remain external release configuration.
- Rewarded-ad verification foundation, dormant: a versioned challenge binds the
  exact attempt, verification handle, and provider custom data. Only an exactly
  correlated server result mints a non-Codable process claim, which must match
  the durable account owner and current profile session before delivery. Its
  challenge-only recovery journal uses two exact copies, bounded canonical and
  duplicate-safe decoding, permanent quarantine barriers, last-copy ambiguity
  resynchronization, sealed checked status, and sealed durable-delivery
  acknowledgement. Release constructors remain sealed. No authenticated
  production transport, URL, credential, replay-stable SSV backend with
  provider-transaction deduplication, SDK, consent adapter, or retained runtime
  integration exists yet.
- Telemetry: coarse, deduplicated product events with no player aliases, raw
  profile identifiers, provider transaction identifiers, exact balances, or
  detailed play history.
- Diagnostics: one process-owned, restartable FIFO input mailbox feeding
  privacy-safe `OSLog` categories and Apple MetricKit delivery. Version 1 uses
  Apple-only crash diagnostics and does not add a third-party crash SDK.

Integration state is service-specific. The StoreKit SDK adapter is retained by
the configured production account graph, while GameKit delivery is not. The Game Center
success-capable fake and delivery-coordinator constructor are Debug-only.
Rewarded-ad verification has a transport protocol and Debug injection seam but
no authenticated production transport; its recovery coordinator is also not
retained. Menus therefore continue to expose explicit unavailable states
without blocking gameplay.

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
