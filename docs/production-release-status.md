# Pocket Vector production release status

Status date: 2026-07-17

This is the living delivery board for the first iOS release. Product scope and
rules remain authoritative in
[`production-release-charter.md`](production-release-charter.md); this file
tracks execution, evidence, dependencies, and owner decisions.

## Current outcome

The native foundation, launch rules, durable local repository, production app
shell, first-run tutorial, fail-closed release information, eight-team shipping
visuals, retained production runtime, and Apple-only diagnostics composition
are complete. Typed first-zone Cloud replica genesis is versioned at `a584b65`
(`Add typed cloud replica genesis`), and the repository hydration mutation
barrier is versioned at `1a8036e` (`Add hydration mutation barrier`). The typed
ordinary publication boundary immediately beneath them is `20e1cbc` (`Add
typed cloud replica publication`). The account-neutral, one-way canonical V4
cloud-profile seed is versioned at `c5d6710` (`Add canonical V4 cloud profile
seed`).
The iOS-only repository cleanup is versioned at `24cd2c7` (`Remove legacy
browser project from iOS repository`).

Shipping GameAssets membership is corrected at `1ae59b5` (`Fix GameAssets
bundle membership`). The app now copies only `native-assets.json` and the
declared `art`, `audio`, `characters`, and `pixel` runtime directories. The
repository-owned `GameAssets/AGENTS.md` remains in source but is absent from the
app bundle. The focused resource test passed, the exact full simulator suite
passed 770 of 771 tests with the existing conditional filesystem skip, and an
unsigned generic-iOS Release archive contains all 58 declared assets plus the
manifest with no extra GameAssets files.

The dormant StoreKit runtime foundation is versioned at `ce69388` (`Add dormant
StoreKit runtime coordination`), player-scoped Game Center persistence and
delivery at `9d749bc` (`Add player-scoped Game Center delivery`), the dormant
rewarded-ad verification boundary at `bbd1bc7` (`Add dormant rewarded ad
verification`), and its crash-recoverable journal at `d6c2b4a` (`Add durable
rewarded ad recovery journal`). These are proven service foundations, not live
production composition.

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

The typed first-zone genesis gate passed 135 focused tests and 642 full-suite
tests with no failure or skip. Its exact path-scoped patch was
`3b473f2f6fc891badb999123e4c4ccc1bf9a1cebf92ae7225646c4b663c2a383`.
The hydration mutation-barrier gate passed 151 tests with one conditional
case-alias skip in its 152-test focus and 648 tests with the same skip in its
649-test full suite; neither run had a failure. Its exact path-scoped patch was
`bddf1a053eabca4b14461c36858e5ff34b73ff9d33bac7794d25f3b85d6d2dd1`.

The exact combined nine-path patch
`a07db41b85fb85a2781788ff67ca5e25e9d475bbae8bcd4bc711c5dd9516aa36`
passed an independent integration audit with no P0/P1/P2 defects, then passed
667 of 668 simulator tests with the same conditional filesystem skip and no
failure. Its unsigned generic-iOS Release archive passed at
`/tmp/PocketVectorBootstrapCombinedArchive-20260716-01.xcarchive`.

The canonical V4 cloud-profile seed gate passed 19 of 19 focused tests and 4 of
4 V4 compatibility tests. The exact current suite passed 748 of 749 tests with
no failure and the same existing conditional filesystem case-alias skip. Fresh
generic-iOS Debug and Release builds both passed. The exact staged patch was
`c5138c4ba7f1415de995c37b54a8b6977056afc964c55720fa4406bb052da356`,
and an independent post-fix audit found no P0/P1/P2 defect. These were build
gates, not archive gates; no archive is claimed for `ce69388`, `9d749bc`,
`bbd1bc7`, or `c5d6710`.

The durable rewarded-ad recovery gate passed 62 of 62 focused tests and 770 of
771 tests in the exact full simulator suite, with no failure and the same
existing conditional filesystem case-alias skip. The simulator Debug
build-for-testing, generic-iOS Release build, and Release symbol scans passed.
The exact staged patch was
`eb0113ca47c8a516333696742e2d8d08305b9098589952445b480e190578d4bb`,
and the final independent audits found no P0/P1/P2 defect. These were build
gates, not an archive gate; no archive is claimed for `d6c2b4a`.

The foundation now includes account-, scope-, epoch-, and build-environment-
bound CloudKit record-change transport; crash-recoverable two-phase
checkpoints; durable hydration journals; exact repository adoption;
account-generation and scoped checkpoint-freshness authorities; sealed
nil-cursor `requireExisting` full-snapshot reconstruction; and sealed
exact-predecessor ordinary incremental publication. Both publication paths
carry opaque generation provenance and revalidate the canonical authority,
account, scope, epoch, durable predecessor, and pending candidate before
mutation. Release code no longer exposes raw checkpoint publication. The V4
seed independently authenticates an exact canonical local artifact and emits a
deterministic facts-and-eligibility description for future bootstrap policy.
It does not claim, publish, write, bind an account, player, or session, or
compose live Cloud behavior.

Rewarded-ad recovery now persists only the immutable verification challenge in
two exact copies behind bounded canonical and duplicate-safe decoding. Durable
owner and profile-session checks, permanent quarantine evidence, a sealed
authenticated-status observation, a sealed durable-delivery acknowledgement,
and fresh durable resynchronization after last-copy ambiguity prevent local
bytes or an ad callback from becoming coin authority. Release construction
remains sealed and the recovery coordinator is not retained by the app.

First-zone genesis now uses a durable before-network reservation, bounded
process-local issuance with duplicate rejection, and one live attempt lease per
physical authority directory-and-lock identity. That lease spans network fetch
through successful generation-one checkpoint save, while every post-ambiguity
recovery is `requireExisting` only. Hydration claims the physical profile
directory before waiting for its file lock, synchronously installs the
actor-owned barrier after that pending claim, and supports actor-mediated retry
with the same recovery handle after exact source, session, journal, and store
revalidation. Target adoption and source-preserving abort require distinct
sealed confirmations; startup recovery is diagnostic only and cannot release a
live barrier.

Debug builds are sealed to the Development CloudKit environment and Release
builds to Production through one build setting shared by the compiler condition
and entitlement expansion. The environment is included in the transport and
replica-scope fingerprint and cannot be supplied by Info.plist configuration.

Cloud capabilities still fail closed in the retained Release composition
because the durable one-time local-to-cloud account claim, outbound initial
profile publication, explicit local/cloud merge policy, and account-scoped
runtime coordinator are not yet implemented. The seed, typed first-zone
genesis, and hydration mutation barrier remain dormant until that composition
exists. Player-scoped Game Center delivery, StoreKit 2 runtime coordination,
and rewarded-ad verification and recovery are likewise implemented but
unavailable in the live app. The earlier unsigned archive proves the Release
compiler selected Production, but it does not prove the final codesigned
entitlement payload; that remains a release-candidate gate.

## Delivery board

| Milestone                                       | State               | Exit evidence                                                                                                                         |
| ----------------------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Product charter and release gates               | Complete            | Scope, roster, economy, achievements, ads, persistence, devices, and success gates approved                                           |
| Reproducible native foundation                  | Complete            | Clean-checkout tests and unsigned Release archive pass at `49d8a6b`                                                                   |
| Domain, catalog, economy, and achievement rules | Complete            | Eight teams, inventory, matchup, clash, reward, coin-pack, and eight-achievement rules pass exhaustive tests                          |
| Durable local player profile and ledger         | Complete            | Atomic recovery, migration, account isolation, idempotent settlement, unlock, ad reward, and relaunch tests pass                      |
| Account-independent service foundations         | Complete            | Cloud transport/checkpoint, typed genesis/publication/hydration, canonical V4 seed, player-scoped Game Center delivery, StoreKit runtime, and challenge-only rewarded-ad verification/recovery foundations pass; none implies live composition |
| Production app shell and menus                  | Complete            | Home, teams, locker, store, leaderboard, achievements, settings, tutorial, privacy/support, gameplay, and results all ship             |
| Retained production runtime and diagnostics     | Complete            | Process-owned coordinator/diagnostics tasks, restartable versioned state, Apple-only telemetry, typed config, and UIKit handoff pass   |
| Gameplay settlement integration                 | Complete            | Release composition persists natural and abandoned runs exactly once and projects authoritative results after settlement             |
| Eight-team presentation system                  | Complete            | Eight motifs, 16 jersey palettes, two footballs, wordmarks, end zones, HUD palettes, raster recoloring, and preload readiness ship     |
| Live Apple and advertising services             | In progress         | Listed foundations pass; approved Cloud merge/claim implementation, outbound bootstrap, retained service composition, permanent IDs, products, records, authenticated production transport/SSV and deduplication, SDK/consent, and signed-device gates remain |
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
| 2026-07-16 | `a584b65` | Typed first-zone genesis focused detached suite | 135 passed, 0 failed, 0 skipped; exact patch `3b473f2f...` independently audited with no P0/P1/P2 defects |
| 2026-07-16 | `a584b65` | Typed first-zone genesis detached full suite | 642 passed, 0 failed, 0 skipped |
| 2026-07-16 | `1a8036e` | Hydration mutation-barrier focused detached suite | 152 total: 151 passed, 0 failed, 1 conditional case-alias skip; exact patch `bddf1a05...` independently audited with no P0/P1/P2 defects |
| 2026-07-16 | `1a8036e` | Hydration mutation-barrier detached full suite | 649 total: 648 passed, 0 failed, 1 conditional case-alias skip |
| 2026-07-16 | `1a8036e` | Combined genesis/hydration integration audit | Exact nine-path patch `a07db41b...`; no P0/P1/P2 findings |
| 2026-07-16 | `1a8036e` | Combined full native simulator suite | 668 total: 667 passed, 0 failed, 1 conditional case-alias skip on iPhone 17 Pro |
| 2026-07-16 | `1a8036e` | Combined unsigned generic-iOS Release archive | Passed at `/tmp/PocketVectorBootstrapCombinedArchive-20260716-01.xcarchive`; arm64, iPhone/iPad, landscape-only, iOS 17+, Production CloudKit, privacy manifest, and iOS-only artifact audit passed |
| 2026-07-16 | `ce69388` | Dormant StoreKit runtime focused gate | 13 passed, 0 failed; final audit found no P0/P1/P2 findings |
| 2026-07-16 | `ce69388` | Dormant StoreKit runtime full simulator suite | 682 total: 681 passed, 0 failed, 1 existing conditional case-alias skip |
| 2026-07-16 | `9d749bc` | Player-scoped Game Center focused gate | 145 total: 144 passed, 0 failed, 1 existing conditional case-alias skip; independent audits found no P0/P1/P2 findings |
| 2026-07-16 | `9d749bc` | Player-scoped Game Center full simulator suite | 721 total: 720 passed, 0 failed, 1 existing conditional case-alias skip; generic-iOS Release build passed |
| 2026-07-16 | `bbd1bc7` | Rewarded-ad verification focused and compatibility gates | 9 verification tests and 43 compatibility tests passed; Debug and Release build/symbol gates passed; independent audit found no P0/P1/P2 findings |
| 2026-07-16 | `bbd1bc7` | Rewarded-ad verification combined full simulator suite | 730 total: 729 passed, 0 failed, 1 existing conditional case-alias skip |
| 2026-07-16 | `c5d6710` | Canonical V4 cloud-profile seed focused gate | 19 passed, 0 failed |
| 2026-07-16 | `c5d6710` | Canonical V4 compatibility gate | 4 passed, 0 failed |
| 2026-07-16 | `c5d6710` | Exact current simulator suite | 749 total: 748 passed, 0 failed, 1 existing conditional case-alias skip |
| 2026-07-16 | `c5d6710` | Generic-iOS Debug and Release build gates | Both passed; build evidence only, no archive claimed |
| 2026-07-16 | `c5d6710` | Canonical seed independent audit | Exact staged patch `c5138c4ba7f1415de995c37b54a8b6977056afc964c55720fa4406bb052da356`; no P0/P1/P2 findings |
| 2026-07-17 | `d6c2b4a` | Durable rewarded-ad recovery focused gate | 62 passed, 0 failed; final independent audits found no P0/P1/P2 findings |
| 2026-07-17 | `d6c2b4a` | Exact current simulator suite | 771 total: 770 passed, 0 failed, 1 existing conditional case-alias skip |
| 2026-07-17 | `d6c2b4a` | Debug test-build and generic-iOS Release gates | Simulator Debug build-for-testing, generic-iOS Release build, and Release symbol scans passed; build evidence only, no archive claimed |
| 2026-07-17 | `d6c2b4a` | Durable rewarded-ad recovery independent audit | Exact staged patch `eb0113ca47c8a516333696742e2d8d08305b9098589952445b480e190578d4bb`; no P0/P1/P2 findings |
| 2026-07-17 | `1ae59b5` | Explicit GameAssets membership focused gate | 1 passed, 0 failed; 58 declared assets exactly match 58 physical bundle assets and `AGENTS.md` is excluded |
| 2026-07-17 | `1ae59b5` | Explicit GameAssets membership full simulator suite | 771 total: 770 passed, 0 failed, 1 existing conditional case-alias skip |
| 2026-07-17 | `1ae59b5` | Unsigned generic-iOS Release archive | Passed at `/tmp/pocketvector-pm-archive-gate.gfsYVe/PocketVector.xcarchive`; arm64, iPhone/iPad, landscape-only, iOS 17+, 58 declared assets plus manifest, no bundled repository documentation |

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
   compiler, transport, and replica scope; add an ordinary
   configuration-derived fetcher that always requires an existing zone; add
   nil-cursor full-snapshot reconstruction and exact-predecessor ordinary
   incremental publication; and bind both results to the issuing account
   generation. Network fetch remains outside the bounded account-generation
   gate.
4. **Complete:** add typed first-zone genesis with durable before-network
   reservation, physical-authority process single-flight, collision defense,
   require-existing recovery, and exact generation-one publication; add the
   repository hydration mutation barrier with pending physical claim,
   actor-mediated same-handle retry, distinct sealed target and predecessor
   confirmations, and diagnostic startup recovery that rejects live admission.
5. **Complete foundation:** authenticate an exact canonical V4 local artifact
   and derive an account-neutral, one-way cloud-profile seed with deterministic
   facts, eligibility, bounds, and digest. The seed does not claim, publish,
   write, bind an account, player, or session, or compose live Cloud.
6. **Complete foundation:** persist only the immutable rewarded-ad verification
   challenge in a bounded two-copy crash-recovery journal. Relaunch re-queries
   authenticated replay-stable server status to mint a fresh process-only
   claim; no verified receipt, provider transaction, transient session, or
   delivery acknowledgement becomes persisted authority. The barrier remains
   through ambiguous delivery and clears only after sealed exact durable
   completion or an authenticated terminal rejection.
7. **Owner policy approved; live Cloud integration pending:** implement the
   approved automatic first-association claim, same-account offline
   reconciliation, account-switch isolation, and outbound initial-profile
   publication.
   Compose them with typed genesis and hydration in the account-scoped runtime
   coordinator, preserving all generation, checkpoint, journal, and final
   durability rechecks.
8. **Complete Game Center foundation; live integration pending:** V4 persistence,
   exact player buckets, unbound quarantine, and capability-bound single-flight
   delivery are implemented. Add the trusted Release factory, retained
   authentication/foreground/presentation composition, App Store Connect
   records, a proof-bearing settlement attribution path, and the approved
   durable exactly-once claim of unbound maxima to the first authenticated
   player. A later player may never claim the same values.
9. **Complete StoreKit foundation; live integration pending:** localized product
   validation, verified updates, unfinished recovery, durable finish gating,
   account-generation retirement, and serialized purchases are implemented.
   Add live account-session sourcing, private-cloud economy composition,
   retained lifecycle and presentation state, and permanent consumable IDs.
10. **Complete rewarded-ad verification foundation; live integration pending:**
   exact challenge/status correlation, process-only verified claims, and
   crash-recoverable challenge journaling are implemented. Add authenticated
   production transport and replay-stable SSV backend with provider-transaction
   deduplication, provider SDK and consent adapters, retained orchestration, and
   authoritative presentation state. A client callback alone never grants
   coins.

The core account-independent Cloud, Game Center, StoreKit, and rewarded-ad
verification/recovery boundaries are proven. The owner has approved the
local/cloud reconciliation and Game Center attribution policies. The release
critical path is now their durable implementation, followed by outbound cloud
publication and retained account-scoped composition. Game Center, StoreKit,
and rewarded-ad foundations remain dormant until their listed live integration
and external-service gates are complete.

## Owner decisions and external dependencies

These decisions and external dependencies gate the live integration path; the
account-independent service foundations above are complete:

1. **Locked account-isolation rule:** known profiles from different iCloud
   identities are never merged. Account changes preserve separate profiles and
   never transfer coins, purchases, ownership, or progress between identities.
2. **Owner-approved iCloud policy:** automatically claim and reconcile the
   canonical unbound installation profile on its first iCloud association, and
   automatically merge locally saved offline work whenever the same account
   reconnects. Preserve the source until the cloud result is durably verified.
3. **Owner-approved Game Center policy:** durably claim legacy or otherwise
   unbound score and achievement maxima exactly once to the first successfully
   authenticated Game Center player. Never offer those values to a later
   player. Queue offline results directly to a known player identity when one
   is available to the run.
4. **Owner-approved Privacy and Support route:** Settings is the main-menu entry
   point for Privacy and Support. The destination remains required and must
   preserve its fail-closed configuration, but it does not require a separate
   main-menu control.
5. Permanent bundle identifier, iCloud container, privacy URL, and support URL.
   Domain and email setup are tracked in the separate user-owned Codex task.
6. Verified rewarded-ad infrastructure. The dormant correlation client,
   process-only verified claim, and challenge-only recovery journal are
   complete, but an authenticated production transport and replay-stable
   server-side-verification endpoint, provider-transaction deduplication, the ad
   SDK, consent orchestration, and retained runtime integration remain. AdMob
   client callbacks alone never grant coins.
7. **Owner-approved Apple-only diagnostics:** use OSLog, Apple crash reports,
   and MetricKit without a third-party crash SDK. The release gate is zero known
   reproducible gameplay crashes, no recurring multi-tester crash signature,
   and completed Apple diagnostics review rather than an exact percentage.
8. Final audience-policy declarations for AdMob and App Store privacy. The
   product remains general audience and outside Apple's Kids Category; the
   shipping SDK configuration and disclosures still require final review.
9. Apple Developer enrollment, Paid Apps agreement, tax and banking, live
   consumable products, Game Center records, AdMob app/ad unit, UMP message,
   `app-ads.txt`, and production CloudKit schema deployment.
10. Final codesigned-entitlement verification. After the permanent iCloud
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
| Known P0/P1 defects                  |      0 | 0 open in the exact audited StoreKit, Game Center, rewarded-ad verification/recovery, and canonical V4 seed scopes; full release audit remains |
| TestFlight sessions                  |   200+ | Not started                                     |
| Valid completed runs                 |   100+ | Not started                                     |
| Apple gameplay-crash review          |   Pass | Not started                                     |
| Results-to-replay rate               |   30%+ | Event contract planned                          |
| Exactly-once economic mutations      |   100% | Local/cloud-history, typed publication/genesis, hydration, StoreKit delivery, server-verified rewarded-ad delivery/recovery, and account-neutral seed foundations pass; approved policy implementation and live composition remain |
| Clean-checkout archive               |   Pass | Unsigned archive for the exact `1ae59b5` project content passed; a detached post-commit clean-checkout rerun and final signed entitlement/export proof remain |
| Browser runtime in active repository |   None | Browser runtime, dependencies, tests, and build configuration removed at `24cd2c7` |

The release is ready only when the entire scoreboard is satisfied, the owner
approves representative iPhone and iPad visuals, and App Store review materials
are complete.
