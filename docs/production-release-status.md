# Pocket Vector production release status

Status date: 2026-07-15

This is the living delivery board for the first iOS release. Product scope and
rules remain authoritative in
[`production-release-charter.md`](production-release-charter.md); this file
tracks execution, evidence, dependencies, and owner decisions.

## Current outcome

The native foundation, launch rules, durable local repository, production app
shell, first-run tutorial, fail-closed release information, eight-team shipping
visuals, retained production runtime, and Apple-only diagnostics composition
are complete. The latest cloud-replica checkpoint and transactional-hydration
recovery boundary is versioned at `766d5a0` (`Harden cloud checkpoint hydration
recovery`).
The iOS-only repository cleanup is versioned at `24cd2c7` (`Remove legacy
browser project from iOS repository`).

The final Wave 5 simulator pass traversed the main menu, all eight offense
choices, the locker and both cosmetic types, the four-step tutorial, gameplay,
results, all eight achievements, Settings, and Privacy & Support. It confirmed
landscape safe-area behavior, corrected compact selected-team layout, selected
uniform and football presentation, randomized opponent presentation, visible
texture readiness, and an explicit release-blocking state when support or
privacy destinations are missing.

The current foundation passed 577 simulator tests and produced an unsigned
generic-iOS Release archive from an exact detached worktree. It includes
account-, scope-, and epoch-bound CloudKit record-change transport,
crash-recoverable two-phase replica checkpoints, sealed checkpoint
observations, cache-loss reconstruction rules, durable transactional-hydration
journals, and complete-history verification for version 3 durable economy
heads, ledger markers, and reward markers. Cloud capabilities still fail closed
in the Release composition: exact repository adoption, observation freshness,
typed `requireExisting` reconstruction enforcement, local-to-cloud bootstrap,
and account/runtime coordination remain unfinished. Game Center, StoreKit 2,
and rewarded advertisements also remain unavailable. The archive is therefore
an engineering gate, not a release-readiness claim.

## Delivery board

| Milestone                                       | State               | Exit evidence                                                                                                                         |
| ----------------------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Product charter and release gates               | Complete            | Scope, roster, economy, achievements, ads, persistence, devices, and success gates approved                                           |
| Reproducible native foundation                  | Complete            | Clean-checkout tests and unsigned Release archive pass at `49d8a6b`                                                                   |
| Domain, catalog, economy, and achievement rules | Complete            | Eight teams, inventory, matchup, clash, reward, coin-pack, and eight-achievement rules pass exhaustive tests                          |
| Durable local player profile and ledger         | Complete            | Atomic recovery, migration, account isolation, idempotent settlement, unlock, ad reward, and relaunch tests pass                      |
| Account-independent service seams               | In progress         | Cloud transport/checkpoint, hydration recovery, and durable economy foundations pass; live repository adoption, account composition, Game Center, StoreKit, and ads remain |
| Production app shell and menus                  | Complete            | Home, teams, locker, store, leaderboard, achievements, settings, tutorial, privacy/support, gameplay, and results all ship             |
| Retained production runtime and diagnostics     | Complete            | Process-owned coordinator/diagnostics tasks, restartable versioned state, Apple-only telemetry, typed config, and UIKit handoff pass   |
| Gameplay settlement integration                 | Complete            | Release composition persists natural and abandoned runs exactly once and projects authoritative results after settlement             |
| Eight-team presentation system                  | Complete            | Eight motifs, 16 jersey palettes, two footballs, wordmarks, end zones, HUD palettes, raster recoloring, and preload readiness ship     |
| Live Apple and advertising services             | In progress         | Runtime/configuration/UIKit and cloud-replica foundations are complete; hydration, permanent IDs, products, Game Center records, and ads remain |
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
3. Add exact repository adoption, an account-generation freshness lease, and a
   sealed reconstruction/fetch context that makes `requireExisting` enforceable
   by type. Prove that a previously valid observation cannot install after a
   later accepted checkpoint, account switch, or authority revocation.
4. Add the explicit local-to-cloud bootstrap/migration workflow and dormant
   coordinator in the required order: resume epoch, recover checkpoint, recover
   hydration before repository load, fetch and validate, merge, journal,
   checkpoint, install, clean up, adopt, recheck generation, then publish.
   Account switching must isolate account-derived identities and publish no
   candidate until profile and checkpoint durability are proven.
5. Add persistent Game Center delivery and presentation, then StoreKit product
   state, localized prices, unfinished-transaction recovery, and purchases.
6. Add persisted rewarded-ad orchestration and a verified-receipt client. No
   client ad callback may grant coins without a unique server-verified provider
   transaction.

The critical path is safely connecting atomic CloudKit restoration to the live
repository, not basic CloudKit CRUD. Checkpoint and hydration recovery now prove
their durable transitions in isolation, but a fresh device cannot yet bootstrap
the account-derived profile, adopt the exact installed candidate under a fresh
single-writer lease, and publish it through the retained runtime.

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

No external purchase, account enrollment, production identifier creation, or
live service mutation is performed without the owner's involvement when the
workflow reaches that gate.

## Release-candidate scoreboard

| Gate                                 | Target | Current                                         |
| ------------------------------------ | -----: | ----------------------------------------------- |
| Known P0/P1 defects                  |      0 | 0 open in the retained-runtime audited scope; full release audit remains |
| TestFlight sessions                  |   200+ | Not started                                     |
| Valid completed runs                 |   100+ | Not started                                     |
| Crash-free sessions                  | 99.5%+ | Instrumentation decision open                   |
| Results-to-replay rate               |   30%+ | Event contract planned                          |
| Exactly-once economic mutations      |   100% | Local and version 3 cloud-history foundations pass; live transactional hydration/composition pending |
| Clean-checkout archive               |   Pass | Detached unsigned Release archive passes at `766d5a0`; final signed RC proof remains |
| Browser runtime in active repository |   None | Browser runtime, dependencies, tests, and build configuration removed at `24cd2c7` |

The release is ready only when the entire scoreboard is satisfied, the owner
approves representative iPhone and iPad visuals, and App Store review materials
are complete.
