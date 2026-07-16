# Pocket Vector production release status

Status date: 2026-07-15

This is the living delivery board for the first iOS release. Product scope and
rules remain authoritative in
[`production-release-charter.md`](production-release-charter.md); this file
tracks execution, evidence, dependencies, and owner decisions.

## Current outcome

The native foundation, launch rules, durable local repository, production app
shell, first-run tutorial, fail-closed release information, eight-team shipping
visuals, durable cloud-first economy coordinator, and Apple diagnostics adapters
are now versioned through commit `a38c3f8` (`Complete Wave 5 production
hardening`). That revision passed all 231 simulator tests and produced an
unsigned generic-iOS Release archive.

The final Wave 5 simulator pass traversed the main menu, all eight offense
choices, the locker and both cosmetic types, the four-step tutorial, gameplay,
results, all eight achievements, Settings, and Privacy & Support. It confirmed
landscape safe-area behavior, corrected compact selected-team layout, selected
uniform and football presentation, randomized opponent presentation, visible
texture readiness, and an explicit release-blocking state when support or
privacy destinations are missing.

CloudKit, Game Center, StoreKit 2, and diagnostics now have substantial native
adapters and deterministic tests, but the Release composition remains local
only. A fresh device cannot yet discover and reconstruct the complete CloudKit
profile and ledger history, so sync cannot honestly become current and
commerce must remain disabled. The successful archive is therefore an
engineering gate, not a release-readiness claim.

## Delivery board

| Milestone                                       | State               | Exit evidence                                                                                                                         |
| ----------------------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Product charter and release gates               | Complete            | Scope, roster, economy, achievements, ads, persistence, devices, and success gates approved                                           |
| Reproducible native foundation                  | Complete            | Clean-checkout tests and unsigned Release archive pass at `49d8a6b`                                                                   |
| Domain, catalog, economy, and achievement rules | Complete            | Eight teams, inventory, matchup, clash, reward, coin-pack, and eight-achievement rules pass exhaustive tests                          |
| Durable local player profile and ledger         | Complete            | Atomic recovery, migration, account isolation, idempotent settlement, unlock, ad reward, and relaunch tests pass                      |
| Account-independent service seams               | In progress         | GameKit, CloudKit, StoreKit 2, diagnostics, durable economy, and deterministic ad contracts pass; live ad SDK/verifier remain          |
| Production app shell and menus                  | Complete            | Home, teams, locker, store, leaderboard, achievements, settings, tutorial, privacy/support, gameplay, and results all ship             |
| Gameplay settlement integration                 | Complete            | Release composition persists natural and abandoned runs exactly once and projects authoritative results after settlement             |
| Eight-team presentation system                  | Complete            | Eight motifs, 16 jersey palettes, two footballs, wordmarks, end zones, HUD palettes, raster recoloring, and preload readiness ship     |
| Live Apple and advertising services             | In progress         | Runtime orchestration and CloudKit hydration are next; permanent IDs, capabilities, products, Game Center records, and ads need owner setup |
| iOS-only repository cleanup                     | Next                | Move the remaining native source assets/tools, remove unused native binaries, then delete the separate browser runtime and tooling    |
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

Every implementation wave must add its own focused tests, pass the full native
suite, and archive when it changes resources, capabilities, app composition, or
Release behavior. A wave is not complete merely because its files exist.

## Next engineering dependency order

1. Complete the iOS-only repository cleanup in its own verified commit.
2. Add a retained production runtime, typed fail-closed service configuration,
   lifecycle cancellation, UIKit presentation handoff, and an authoritative
   state stream. Compose Apple-only diagnostics in this layer.
3. Add CloudKit account/profile bootstrap, remote record discovery, cursor
   persistence, complete profile hydration, and deterministic two-device merge.
   A device must verify the full ledger accumulator before sync becomes current.
4. Compose the durable economy and confirm pending gameplay credits only after
   hydration. Account changes must invalidate the old authority before any new
   profile is published.
5. Add persistent Game Center delivery and presentation, then StoreKit product
   state, localized prices, unfinished-transaction recovery, and purchases.
6. Add persisted rewarded-ad orchestration and a verified-receipt client. No
   client ad callback may grant coins without a unique server-verified provider
   transaction.

The critical path is CloudKit restoration, not basic CloudKit CRUD. The current
transport safely mutates caller-known records, but a fresh device cannot yet
discover the complete historical ledger needed to reconstruct and verify the
authoritative economy.

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
| Known P0/P1 defects                  |      0 | 0 open in the Wave 5 audited scope; full release audit remains |
| TestFlight sessions                  |   200+ | Not started                                     |
| Valid completed runs                 |   100+ | Not started                                     |
| Crash-free sessions                  | 99.5%+ | Instrumentation decision open                   |
| Results-to-replay rate               |   30%+ | Event contract planned                          |
| Exactly-once economic mutations      |   100% | Local, cloud-head, purchase, unlock, and verified-ad coordinator tests pass; live hydration/composition pending |
| Clean-checkout archive               |   Pass | Passing through `a38c3f8`; recheck after browser cleanup |
| Browser runtime in active repository |   None | Cleanup deferred until final native asset audit |

The release is ready only when the entire scoreboard is satisfied, the owner
approves representative iPhone and iPad visuals, and App Store review materials
are complete.
