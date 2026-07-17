# Pocket Vector production release status

Status date: 2026-07-16

This is the living delivery board for the first iOS release. Product scope and
rules remain authoritative in
[`production-release-charter.md`](production-release-charter.md); this file
tracks execution, evidence, dependencies, and owner decisions.

## Current outcome

The native foundation, launch rules, durable local repository, production app
shell, first-run tutorial, fail-closed release information, eight-team shipping
visuals, retained production runtime, and Apple-only diagnostics composition
are complete. The latest typed Cloud replica publication boundary is versioned
at `20e1cbc` (`Add typed cloud replica publication`); the scoped
checkpoint-freshness boundary immediately beneath it is `1ea542c` (`Add scoped
checkpoint freshness lease`).
The iOS-only repository cleanup is versioned at `24cd2c7` (`Remove legacy
browser project from iOS repository`).

The final Wave 5 simulator pass traversed the main menu, all eight offense
choices, the locker and both cosmetic types, the four-step tutorial, gameplay,
results, all eight achievements, Settings, and Privacy & Support. It confirmed
landscape safe-area behavior, corrected compact selected-team layout, selected
uniform and football presentation, randomized opponent presentation, visible
texture readiness, and an explicit release-blocking state when support or
privacy destinations are missing.

The typed Cloud publication gate passed 278 focused simulator tests and 623
full simulator tests and produced an unsigned generic-iOS Release archive from
exact frozen patch `e3551a5e...`. Three independent reviews of that exact patch
found no P0/P1/P2 defects. The environment review also verified that missing,
invalid, and ambiguous CloudKit build-environment conditions fail compilation.

The foundation now includes account-, scope-, epoch-, and build-environment-
bound CloudKit record-change transport; crash-recoverable two-phase
checkpoints; durable hydration journals; exact repository adoption;
account-generation and scoped checkpoint-freshness authorities; sealed
nil-cursor `requireExisting` full-snapshot reconstruction; and sealed
exact-predecessor ordinary incremental publication. Both publication paths
carry opaque generation provenance and revalidate the canonical authority,
account, scope, epoch, durable predecessor, and pending candidate before
mutation. Release code no longer exposes raw checkpoint publication.

Debug builds are sealed to the Development CloudKit environment and Release
builds to Production through one build setting shared by the compiler condition
and entitlement expansion. The environment is included in the transport and
replica-scope fingerprint and cannot be supplied by Info.plist configuration.

Cloud capabilities still fail closed in the retained Release composition
because first-zone initialization, one-time local-to-cloud account migration,
outbound profile publication, and the account-scoped runtime coordinator are
not yet implemented. Game Center, StoreKit 2, and rewarded advertisements also
remain unavailable. The unsigned archive proves the Release compiler selected
Production, but it does not prove the final codesigned entitlement payload;
that remains a release-candidate gate.

## Delivery board

| Milestone                                       | State               | Exit evidence                                                                                                                         |
| ----------------------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Product charter and release gates               | Complete            | Scope, roster, economy, achievements, ads, persistence, devices, and success gates approved                                           |
| Reproducible native foundation                  | Complete            | Clean-checkout tests and unsigned Release archive pass at `49d8a6b`                                                                   |
| Domain, catalog, economy, and achievement rules | Complete            | Eight teams, inventory, matchup, clash, reward, coin-pack, and eight-achievement rules pass exhaustive tests                          |
| Durable local player profile and ledger         | Complete            | Atomic recovery, migration, account isolation, idempotent settlement, unlock, ad reward, and relaunch tests pass                      |
| Account-independent service seams               | In progress         | Cloud transport/checkpoint, transactional hydration recovery, exact repository adoption, account-generation authority, scoped checkpoint freshness, sealed reconstruction, and typed incremental publication pass; first-zone/local migration, account composition, Game Center, StoreKit, and ads remain |
| Production app shell and menus                  | Complete            | Home, teams, locker, store, leaderboard, achievements, settings, tutorial, privacy/support, gameplay, and results all ship             |
| Retained production runtime and diagnostics     | Complete            | Process-owned coordinator/diagnostics tasks, restartable versioned state, Apple-only telemetry, typed config, and UIKit handoff pass   |
| Gameplay settlement integration                 | Complete            | Release composition persists natural and abandoned runs exactly once and projects authoritative results after settlement             |
| Eight-team presentation system                  | Complete            | Eight motifs, 16 jersey palettes, two footballs, wordmarks, end zones, HUD palettes, raster recoloring, and preload readiness ship     |
| Live Apple and advertising services             | In progress         | Runtime/configuration/UIKit, Cloud replica, typed checkpoint publication, and hydration transaction foundations are complete; live bootstrap/coordinator composition, permanent IDs, products, Game Center records, and ads remain |
| iOS-only repository cleanup                     | Complete            | Native sources/tools are retained under `ios/`; browser runtime, dependencies, tests, build files, and unused assets are removed      |
| TestFlight release candidate                    | Queued              | Device, accessibility, sandbox, sync, replay, crash, and economy gates pass                                                           |
| App Store submission                            | Queued              | Signed archive, privacy report, metadata, review notes, screenshots, and owner approval complete                                      |

## Active ownership lanes

- Domain lane: stable IDs, eight-team catalog, inventory rules, matchup and
  uniform-clash resolution, reward math, and eight achievement evaluators.
- Persistence lane: versioned local profile, backups and corruption recovery,
  immutable ledger, exactly-once run settlement, unlock/equip validation, and
  aggregate statistics.
- Platform-seam lane: protocol-backed queues and state machines for CloudKit,
  Game Center, StoreKit, rewarded ads and consent, telemetry, and diagnostics.
- Integration lane: Xcode project ownership, cross-lane review, build/test gates,
  commits, app composition, and release-board maintenance.

Only the integration lane edits `project.pbxproj` or shared app/game entry
points. This prevents concurrent work from silently overwriting build settings
or runtime ownership boundaries.

## Verification ledger

| Date       | Revision  | Gate                                             | Result                                                        |
| ---------- | --------- | ------------------------------------------------ | ------------------------------------------------------------- |
| 2026-07-15 | `49d8a6b` | Detached clean-checkout simulator suite          | 40 passed, 0 failed                                           |
| 2026-07-15 | `49d8a6b` | Detached clean-checkout unsigned Release archive | Passed                                                        |
| 2026-07-15 | `49d8a6b` | Archived runtime-resource audit                  | 60 binaries plus manifest; 6.1 MB; no browser asset directory |
| 2026-07-15 | `9b3782d` | Service-contract simulator suite and archive     | 84 passed, 0 failed; unsigned Release archive passed           |
| 2026-07-15 | `cd6151e` | Durable-profile simulator suite and archive      | 109 passed, 0 failed; unsigned Release archive passed          |
| 2026-07-15 | `8c4e8d9` | Shell, gameplay, GameKit, and visuals full suite | 150 passed, 0 failed, 0 skipped; unsigned archive passed       |
| 2026-07-15 | `8c4e8d9` | iPhone 17 Pro landscape launch smoke             | Main menu rendered without safe-area clipping                  |
| 2026-07-15 | `504f562` | Composition, CloudKit, StoreKit, and icon suite  | 179 passed, 0 failed, 0 skipped; unsigned archive passed       |
| 2026-07-15 | `a38c3f8` | Tutorial, diagnostics, visuals, and economy focus | 56 passed, 0 failed, 0 skipped                                 |
| 2026-07-15 | `a38c3f8` | Frozen full native simulator suite                | 231 passed, 0 failed, 0 skipped                                |
| 2026-07-15 | `a38c3f8` | iPhone 17 Pro landscape accessibility/visual pass | Menus, eight teams, locker, tutorial, gameplay, results, achievements, settings, and release blockers reviewed |
| 2026-07-15 | `a38c3f8` | Unsigned generic-iOS Release archive              | Passed; iPhone/iPad, landscape-only, iOS 17+, privacy manifest, encryption declaration, and resource package verified |
| 2026-07-15 | `24cd2c7` | Exact native-resource inventory                   | 1 focused test passed; 58 declared assets exactly match 58 physical resources, 6,168,312 bytes |
| 2026-07-15 | `24cd2c7` | iOS-only cleanup full simulator suite             | 231 passed, 0 failed, 0 skipped                                |
| 2026-07-15 | `24cd2c7` | iOS-only cleanup unsigned Release archive         | Passed; 58 runtime assets plus manifest; no browser, source-art, or asset-tool content bundled |
| 2026-07-15 | `59de4a7` | Runtime, config, diagnostics, and UIKit focused gates | 99 passed, 0 failed, 0 skipped across four focused bundles     |
| 2026-07-15 | `59de4a7` | Retained-runtime full native simulator suite      | 296 passed, 0 failed, 0 skipped                                |
| 2026-07-15 | `59de4a7` | Unsigned generic-iOS Release archive              | Passed; arm64, iPhone/iPad, landscape-only, iOS 17 minimum     |
| 2026-07-15 | `701c069` | Cloud-checkpoint focused simulator suite          | 41 passed, 0 failed, 0 skipped; independent post-audit found no P0/P1/P2 defects |
| 2026-07-15 | `701c069` | Cloud/economy foundation full simulator suite     | 372 passed, 0 failed, 0 skipped                                |
| 2026-07-15 | `701c069` | Unsigned generic-iOS Release archive              | Passed at `/tmp/PocketVectorCloudFoundation-20260715-3.xcarchive`; archive and app metadata valid; 22 MB app |
| 2026-07-16 | `766d5a0` | Checkpoint/hydration focused detached suite       | 140 passed, 0 failed, 0 skipped; exact frozen patch independently audited with no P0/P1/P2 defects |
| 2026-07-16 | `766d5a0` | Checkpoint/hydration detached full suite          | 577 passed, 0 failed, 0 skipped                                |
| 2026-07-16 | `766d5a0` | Detached unsigned generic-iOS Release archive     | Passed at `/tmp/PocketVectorCommitGateArchive-20260716-01.xcarchive` |
| 2026-07-16 | `8188cfc` | Repository-adoption focused detached suite        | 75 passed, 0 failed, 0 skipped; three independent latest-diff audits found no P0/P1/P2 defects |
| 2026-07-16 | `8188cfc` | Repository-adoption detached full suite           | 588 passed, 0 failed, 0 skipped                                |
| 2026-07-16 | `8188cfc` | Detached unsigned generic-iOS Release archive     | Passed at `/tmp/PocketVectorAdoptionCommitGateArchive-20260716-01.xcarchive` |
| 2026-07-16 | `afe5bc0` | Account-generation focused detached suite         | 21 passed, 0 failed, 0 skipped; exact patch `4391e19c…` independently audited three times with no P0/P1/P2 defects |
| 2026-07-16 | `afe5bc0` | Account-generation detached full suite            | 602 passed, 0 failed, 0 skipped                               |
| 2026-07-16 | `afe5bc0` | Detached unsigned generic-iOS Release archive     | Passed at `/tmp/PocketVectorAccountGenerationDetachedArchive-20260716-01.xcarchive` |
| 2026-07-16 | `1ea542c` | Checkpoint-freshness focused detached suite        | 227 passed, 0 failed, 0 skipped; exact patch `7beb6363…` independently audited three times with no P0/P1/P2 defects |
| 2026-07-16 | `1ea542c` | Checkpoint-freshness detached full suite           | 612 passed, 0 failed, 0 skipped                               |
| 2026-07-16 | `1ea542c` | Detached unsigned generic-iOS Release archive     | Passed at `/tmp/PocketVectorCheckpointLeaseDetachedArchive-20260716-01.xcarchive` |
| 2026-07-16 | `20e1cbc` | Typed reconstruction/publication focused detached suite | 278 passed, 0 failed, 0 skipped; exact patch `e3551a5e...` independently audited three times with no P0/P1/P2 defects |
| 2026-07-16 | `20e1cbc` | Typed reconstruction/publication detached full suite | 623 passed, 0 failed, 0 skipped                               |
| 2026-07-16 | `20e1cbc` | Detached unsigned generic-iOS Release archive     | Passed at `/tmp/PocketVectorTypedPublicationDetachedArchive-20260716-01.xcarchive`; Production CloudKit compiler condition, archive metadata, and iOS-only resource audit passed |

Every implementation wave must add its own focused tests, pass the full native
suite, and archive when it changes resources, capabilities, app composition, or
Release behavior. A wave is not complete merely because its files exist.

## Next engineering dependency order

1. **Complete:** retain the production runtime, typed fail-closed service
   configuration, lifecycle cancellation, UIKit presentation handoff,
   authoritative state subscriptions, and Apple-only diagnostics.
2. **Complete:** bind the canonical profile, transport, and economy contracts
   into one versioned scope fingerprint; add epoch revocation, two-phase
   checkpoint recovery, sealed observations, cache-loss reconstruction, and
   durable hydration journals without enabling the live capability.
3. **Complete:** seal the CloudKit build environment into entitlement,
   compiler, transport, and replica scope; add a configuration-derived fetcher
   that always requires an existing zone; add nil-cursor full-snapshot
   reconstruction and exact-predecessor ordinary incremental publication; and
   bind both results to the issuing account generation. Network fetch remains
   outside the bounded account-generation gate.
4. **Next:** add the sealed first-zone genesis fetch/save path, the repository
   hydration-mutation barrier, a durable one-time local-to-cloud account-claim
   transaction, outbound initial profile publication, and the dormant
   coordinator in the required order: resume or establish epoch, recover
   checkpoint, recover migration/hydration before repository load, fetch and
   validate, merge, journal, checkpoint, install, clean up, adopt, recheck
   generation, then publish. Account switching must isolate account-derived
   identities and publish no candidate until profile and checkpoint durability
   are proven.
5. Add persistent Game Center delivery and presentation, then StoreKit product
   state, localized prices, unfinished-transaction recovery, and purchases.
6. Add persisted rewarded-ad orchestration and a verified-receipt client. No
   client ad callback may grant coins without a unique server-verified provider
   transaction.

The critical path is now composing the proven CloudKit restoration and
publication seams into the retained runtime. A returning device has typed,
fixed-policy checkpoint reconstruction and incremental publication primitives,
but a new account cannot yet create and initialize its first zone, durably
claim a local-only profile into the account-derived identity, publish the
initial outbound profile, or expose the result through an account-scoped
coordinator.

## Owner decisions and external dependencies

These do not block the current account-independent implementation waves:

1. Permanent bundle identifier, iCloud container, privacy URL, and support URL.
   Domain and email setup are tracked in the separate user-owned Codex task.
2. Verified rewarded-ad infrastructure. AdMob client callbacks alone cannot
   meet the exactly-once, crash/reinstall-safe reward gate; production requires
   a small server-side-verification endpoint with provider-transaction
   deduplication.
3. Crash KPI instrumentation. Apple diagnostics support crash and session
   review, but an exact crash-free-session percentage requires a provider such
   as Crashlytics; otherwise the gate must be renamed to an Apple-only proxy.
4. Final audience-policy declarations for AdMob and App Store privacy. The
   product remains general audience and outside Apple's Kids Category; the
   shipping SDK configuration and disclosures still require final review.
5. Apple Developer enrollment, Paid Apps agreement, tax and banking, live
   consumable products, Game Center records, AdMob app/ad unit, UMP message,
   `app-ads.txt`, and production CloudKit schema deployment.
6. Final codesigned-entitlement verification. After the permanent iCloud
   container and signing profile exist, inspect the exported release candidate
   and confirm `com.apple.developer.icloud-container-environment` is
   `Production` and the expected iCloud container identifiers and services are
   present. An unsigned archive cannot satisfy this gate.

No external purchase, account enrollment, production identifier creation, or
live service mutation is performed without the owner's involvement when the
workflow reaches that gate.

## Release-candidate scoreboard

| Gate                                 | Target | Current                                         |
| ------------------------------------ | -----: | ----------------------------------------------- |
| Known P0/P1 defects                  |      0 | 0 open in the exact typed Cloud publication audited scope; full release audit remains |
| TestFlight sessions                  |   200+ | Not started                                     |
| Valid completed runs                 |   100+ | Not started                                     |
| Crash-free sessions                  | 99.5%+ | Instrumentation decision open                   |
| Results-to-replay rate               |   30%+ | Event contract planned                          |
| Exactly-once economic mutations      |   100% | Local, version 3 cloud-history, and typed checkpoint-publication foundations pass; live bootstrap/hydration composition remains |
| Clean-checkout archive               |   Pass | Detached unsigned Release archive passes at `20e1cbc`; final signed entitlement/export proof remains |
| Browser runtime in active repository |   None | Browser runtime, dependencies, tests, and build configuration removed at `24cd2c7` |

The release is ready only when the entire scoreboard is satisfied, the owner
approves representative iPhone and iPad visuals, and App Store review materials
are complete.
