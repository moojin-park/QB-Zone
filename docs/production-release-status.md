# Pocket Vector production release status

Status date: 2026-07-15

This is the living delivery board for the first iOS release. Product scope and
rules remain authoritative in
[`production-release-charter.md`](production-release-charter.md); this file
tracks execution, evidence, dependencies, and owner decisions.

## Current outcome

The native foundation is reproducible and versioned. Commit `49d8a6b`
(`Establish reproducible native iOS baseline`) passed 40 of 40 simulator tests
and produced an unsigned Release archive from a detached clean checkout. The
archive contains the curated 6.1 MB `GameAssets` bundle with 60 runtime binaries
and one provenance manifest, and it does not depend on the browser asset tree.

Production feature work is now proceeding behind pure domain contracts and one
actor-isolated player repository. SwiftUI owns app navigation and durable state;
SpriteKit remains the renderer for one disposable gameplay run.

## Delivery board

| Milestone                                       | State               | Exit evidence                                                                                                                         |
| ----------------------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Product charter and release gates               | Complete            | Scope, roster, economy, achievements, ads, persistence, devices, and success gates approved                                           |
| Reproducible native foundation                  | Complete            | Clean-checkout tests and unsigned Release archive pass at `49d8a6b`                                                                   |
| Domain, catalog, economy, and achievement rules | In progress         | Pure Swift rules compile; boundary and exhaustive matchup tests pass                                                                  |
| Durable local player profile and ledger         | In progress         | Corruption recovery, migration, idempotent settlement, unlock, and relaunch tests pass                                                |
| Account-independent service seams               | In progress         | Game Center, StoreKit, ads, sync, telemetry queues pass deterministic fake-service tests                                              |
| Production app shell and menus                  | Queued              | Launch, home, teams, store, leaderboard, achievements, settings, privacy/support, gameplay, and results flows pass UI review          |
| Gameplay settlement integration                 | Queued              | Every completed run settles once and drives rewards, records, achievements, telemetry, replay, and home flows                         |
| Eight-team presentation system                  | Queued              | All 16 offense jerseys, randomized contrast-safe defenses, logos, end zones, and HUD palettes pass device review                      |
| Live Apple and advertising services             | Blocked on accounts | Capabilities, permanent identifiers, sandbox products, Game Center records, AdMob configuration, and verified rewards work end to end |
| iOS-only repository cleanup                     | Queued              | Browser runtime, browser tooling, obsolete assets, and Bounty Board integration removed after final native asset audit                |
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

Every implementation wave must add its own focused tests, pass the full native
suite, and archive when it changes resources, capabilities, app composition, or
Release behavior. A wave is not complete merely because its files exist.

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
| Known P0/P1 defects                  |      0 | Not yet measured                                |
| TestFlight sessions                  |   200+ | Not started                                     |
| Valid completed runs                 |   100+ | Not started                                     |
| Crash-free sessions                  | 99.5%+ | Instrumentation decision open                   |
| Results-to-replay rate               |   30%+ | Event contract planned                          |
| Exactly-once economic mutations      |   100% | Foundation in progress                          |
| Clean-checkout archive               |   Pass | Passing at native baseline                      |
| Browser runtime in active repository |   None | Cleanup deferred until final native asset audit |

The release is ready only when the entire scoreboard is satisfied, the owner
approves representative iPhone and iPad visuals, and App Store review materials
are complete.
