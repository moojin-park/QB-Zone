# Pocket Vector production release charter

Status: **v1 product charter, launch roster, and TestFlight economy baseline approved**

Last updated: 2026-07-15

This document is the product-management source of truth for the first iOS
release. It records release goals, scope boundaries, validation gates, and open
product decisions. It does not authorize implementation changes by itself.

## Product promise

Pocket Vector is a fast, 60-second arcade passing game built around replaying
for a higher score. Teams, jerseys, and footballs are cosmetic only. No team,
cosmetic, purchase, or advertisement may change scoring, timing, player speed,
collision behavior, difficulty, or leaderboard eligibility.

## Locked launch scope

| Area                     | Version 1 requirement                                                                                                                             |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Public title             | Pocket Vector                                                                                                                                     |
| Audience                 | General audience; do not enroll in or market as Apple's Kids Category                                                                             |
| Devices                  | iPhone and iPad                                                                                                                                   |
| Orientation              | Landscape only                                                                                                                                    |
| Minimum OS               | iOS 17                                                                                                                                            |
| Gameplay                 | Preserve the current 60-second core game                                                                                                          |
| Teams                    | Eight total: four free and four unlocked with coins                                                                                               |
| Matchup                  | Player selects the offense; defense is randomized from the other seven teams                                                                      |
| Locked opponents         | A locked team may still appear as a randomized opponent                                                                                           |
| Team presentation        | The selected offense controls uniforms, logo, end-zone branding, and HUD colors                                                                   |
| Jerseys                  | Every team includes its primary jersey and has one separately unlockable alternate jersey                                                         |
| Footballs                | One default football and one unlockable alternate football; unlocked footballs work with every team                                               |
| Currency                 | Coins are earned through gameplay, rewarded advertisements, and StoreKit purchases                                                                |
| Purchases                | Consumable coin packs only; no remove-ads purchase in version 1                                                                                   |
| Ads                      | Optional rewarded advertisement after every five completed valid runs; never automatic                                                            |
| Game Center              | One all-time global high-score leaderboard and exactly eight achievements                                                                         |
| Local persistence        | Personal best, aggregate statistics, tutorial completion, settings, selected team, selected jersey, selected football, inventory, and coin ledger |
| Cross-device persistence | Private CloudKit synchronization; purchases require available iCloud state, while core gameplay remains playable offline                          |
| Saved settings           | Music level, SFX level, mute, reduced motion, and tutorial completion                                                                             |
| Diagnostics              | Apple crash diagnostics plus minimal privacy-conscious gameplay and commerce events                                                               |
| Browser project          | Not part of this repository's active product; a separate browser project already exists                                                           |

## Launch menu structure

The production menu must expose:

- Play
- Teams / Locker
- Store
- Leaderboard
- Achievements
- Settings

Privacy and Support must remain reachable from Settings. Version one does not
require a separate Privacy and Support control on the main menu.

The results screen must expose:

- Play Again
- Home
- A rewarded-coin offer when the five-run eligibility threshold is met

## Rewarded-ad rules

- Only a completed, valid run advances the five-run counter.
- Eligibility clamps at five; advertisements do not bank into a queue.
- The advertisement never opens automatically.
- If the player declines, the offer remains available after a later run.
- The counter resets only after a verified completed view.
- Each verified reward grants coins exactly once.
- No advertisement appears during active gameplay.

## Team identity direction

The league uses original retro-science identities rather than real league,
team, player, logo, or uniform likenesses. The NFL clubs below are color and
regional mood references only. The owner approved these working identities on
2026-07-15. Names and emblems remain subject to formal trademark clearance.

Nova City currently has conflicting project palettes. Its brand palette in the
asset manifest is cyan, violet, and white, while its current red uniforms came
from the old role-based offense/defense treatment. Selectable teams require
team-driven colors. The canonical Comets palette is cyan/violet/white.

| Reference     | Approved working team    | Primary               | Secondary              | Accent                | Identity direction                                                |
| ------------- | ------------------------ | --------------------- | ---------------------- | --------------------- | ----------------------------------------------------------------- |
| Existing      | Nova City Comets         | `#1DE6EF` cyan        | `#7D4DFF` violet       | `#F7FCFF` white       | Comet and orbital trail                                           |
| Denver        | High Mesa Helions        | `#F06A3B` ember       | `#2B234D` indigo       | `#D8F0EC` glacier     | Solar disk over an angular mesa; no horse imagery                 |
| Los Angeles   | Luma Coast Prisms        | `#63CFE7` sky aqua    | `#30214F` deep plum    | `#F4C64E` sun gold    | Prism splitting a light beam; no lightning bolt                   |
| Green Bay     | Foundry Reach Orbiters   | `#146353` forge green | `#D4A73E` brass        | `#F0E8CF` cream       | Riveted orbital ring; no letter or cheese motif                   |
| Las Vegas     | Neon Basin Eclipses      | `#171923` carbon      | `#ADB5C2` mercury      | `#A05CFF` ultraviolet | Offset disks and corona; no pirate imagery                        |
| Kansas City   | Meridian Plains Radiants | `#C72F4F` ruby        | `#F0A253` solar copper | `#FFF0DD` cream       | Geometric reactor or sun core; no arrowhead or Indigenous imagery |
| Seattle       | Rainport Auroras         | `#0B3A4A` storm teal  | `#9DD643` aurora lime  | `#E5F2EA` mist        | Aurora bands over a grid wave; no bird imagery                    |
| San Francisco | Bayline Redshifts        | `#842C4B` garnet      | `#C87845` copper       | `#DFE5E2` fog         | Receding wavelength bars; no bridge, miner, or SF monogram        |

Approved free teams for launch palette variety:

1. Nova City Comets
2. High Mesa Helions
3. Foundry Reach Orbiters
4. Rainport Auroras

The other four teams are coin unlocks.

### Uniform production constraint

Eight teams with two jerseys each must use shared master sprites plus a
data-driven palette or mask workflow. The release should not depend on manually
maintaining hundreds of independent animation images. Defense jersey selection
must automatically choose the primary or alternate treatment with the best
light/dark and color contrast against the selected offense.

## Approved TestFlight coin-economy baseline

The owner approved these starting values on 2026-07-15. They remain tunable
until validated in TestFlight and are not permanent live-economy commitments.

### Earning coins

- One-time signing bonus: 250 coins after the first valid completed run.
- A valid rewarded run reaches Results and includes at least three pass attempts.
- Per-run payout:
  - 10 completion coins;
  - plus `min(floor(score / 1,000), 25)` performance coins;
  - plus 5 accuracy coins for at least 10 attempts and at least 70% accuracy.
- Normal payout range: 10 to 40 coins per run.
- Rewarded advertisement: 100 coins after every five valid completed runs.
- No daily login reward, random chest, paid gameplay advantage, or achievement
  coin reward in version 1.

### Initial unlock prices

| Item                                  | Coin price | Launch quantity | Total catalog cost |
| ------------------------------------- | ---------: | --------------: | -----------------: |
| Locked team, including primary jersey |      1,500 |               4 |              6,000 |
| Alternate jersey                      |        500 |               8 |              4,000 |
| Global alternate football             |        750 |               1 |                750 |
| Full launch catalog                   |            |                 |             10,750 |

An alternate jersey for a locked team can be purchased only after that team is
owned.

### Initial StoreKit coin packs

US prices are launch hypotheses; Apple supplies localized storefront prices.

| Pack   | Coins | Proposed US price |
| ------ | ----: | ----------------: |
| Pocket |    750 |             $0.99 |
| Team   |  2,500 |             $2.99 |
| Bundle |  6,000 |             $5.99 |
| Vault  | 11,000 |             $9.99 |

Each successive tier provides strictly more coins per US dollar. No combination
of lower-tier packs at or below $9.99 provides as many coins as the Vault. The
Vault covers the 10,750-coin launch catalog with a 250-coin remainder.

Purchased credits never expire. Every gameplay, advertisement, purchase, and
spend mutation must have an idempotent ledger identifier so a retry, crash,
reinstall, or device merge cannot grant or spend twice.

### Economy validation targets

- Median first alternate jersey: no later than eight completed runs.
- Median first locked team: between 25 and 35 completed runs.
- Rewarded ads should not exceed roughly 45% of coins earned by regular viewers.
- Track payout percentiles, first-unlock timing, coin source, unlock order,
  balance, advertisement acceptance, purchase completion, and replay behavior.
- Rebalance costs or payouts before submission if the first jersey takes more
  than 10 runs or the first team takes more than 40 runs for the median tester.

## Game Center achievements

| Achievement            | Requirement                                                 | Points |
| ---------------------- | ----------------------------------------------------------- | -----: |
| First Read             | Complete any successful pass                                |     25 |
| Paydirt                | Score a touchdown                                           |     50 |
| Cash the Charge        | Score a touchdown while TD Bonus is active                  |     75 |
| Full Route Tree        | Complete a pass in all four lanes during one run            |     75 |
| Dialed In              | Finish with at least 80% accuracy over at least 12 attempts |     75 |
| Hot Hand               | Score four consecutive touchdowns during one run            |    100 |
| Light Up the Board     | Reach 25,000 points during one run                          |    100 |
| Century of Connections | Complete 100 career passes, including touchdowns            |    100 |

The set totals 600 Game Center points. Validate the 25,000-point threshold
against TestFlight score distributions before making permanent App Store
Connect identifiers.

## Release success and quality gates

Before App Store submission:

- Owner approves all menu and visual-polish issues on representative iPhones
  and iPads.
- Zero known P0 or P1 defects.
- At least 200 TestFlight sessions and 100 completed runs.
- Zero known reproducible gameplay crashes, no recurring crash signature across
  multiple testers, and completed review of Apple crash reports and MetricKit
  diagnostics during the release-candidate test window.
- At least 30% results-to-replay rate among eligible completed runs.
- Game Center authentication failure never blocks offline play.
- Scores and achievements queue safely while offline and submit once.
- Purchases, advertisement rewards, gameplay rewards, and spends grant exactly
  once.
- Coins and ownership survive relaunch, reinstall, offline reconciliation, and
  iPhone/iPad synchronization.
- The native app archives from a clean checkout.
- The active repository contains no browser runtime or obsolete browser build
  artifacts.

App Store approval is the release outcome. Revenue is a post-launch health
metric; set a numeric 30-day revenue target only after coin-pack prices and an
acquisition baseline are approved.

## Repository-cleanup gate

The recoverable native baseline, curated iOS resource bundle, retained native
source art and tools, and iOS-only repository cleanup were completed on
2026-07-15. The historical browser product remains available in its separate
project and is not a build or asset dependency of this repository.

Required order:

1. **Complete:** establish a recoverable native baseline in version control.
2. **Complete:** move every current native runtime asset into a curated iOS
   resource location.
3. **Complete:** retarget Xcode and add resource-presence tests.
4. **Complete:** prove build, tests, and archive from a clean checkout.
5. **Complete:** remove browser source, browser tests/configuration, Bounty Board
   integration, browser-only dependencies, build output, and unused web assets.
6. **Complete:** rewrite the root documentation for the iOS-only project.

## Delivery sequence

1. Enroll in the Apple Developer Program as an individual and establish the
   permanent bundle identity, support URL, and privacy URL.
2. Make the native project reproducible and complete repository cleanup.
3. Establish the versioned player profile and CloudKit ledger model.
4. Establish the production menu and navigation architecture.
5. Produce the eight-team identity, uniform, field, logo, and HUD asset system.
6. Configure the leaderboard and eight achievements after scoring is frozen.
7. Add StoreKit coin packs, rewarded ads, and minimal product telemetry.
8. Complete visual QA, device testing, sandbox testing, and TestFlight gates.
9. Prepare and submit the App Store release.

## Explicitly deferred beyond version 1

- More teams, jerseys, footballs, or cosmetic categories
- Weekly, seasonal, or team-specific leaderboards
- New gameplay modes, power-ups, stat differences, or paid gameplay advantages
- Forced interstitial advertising, banner advertising, or stadium ad inventory
- Remove-ads purchase
- Browser release work in this repository

## Open owner approvals

- Choose the permanent bundle identifier.
- Provide or approve the privacy and support domains before App Store setup.

## Decision log

- **2026-07-15:** Locked Pocket Vector as a general-audience iPhone/iPad game,
  landscape-only on iOS 17 and later, with cosmetic-only monetization.
- **2026-07-15:** Locked eight teams, four free teams, four coin-unlocked teams,
  one alternate jersey per team, and one universal alternate football.
- **2026-07-15:** Approved the eight-team working roster, cyan/violet/white Nova
  City identity, and the free-team split documented above.
- **2026-07-15:** Approved the initial gameplay rewards, rewarded-ad value,
  unlock costs, and four StoreKit coin packs as the TestFlight baseline.
- **2026-07-15:** Locked private CloudKit synchronization, saved settings, one
  all-time leaderboard, eight achievements, and rewarded ads only after every
  five valid completed runs.
- **2026-07-17:** Locked automatic local/private-iCloud reconciliation for the
  first iCloud association and for subsequent synchronization with the same
  account. Offline progress merges automatically after reconnect. A known
  profile from one iCloud identity is never transferred to another identity;
  account-scoped profiles are preserved separately during account changes.
- **2026-07-17:** Locked a durable, exactly-once claim of legacy or otherwise
  unbound Game Center score and achievement maxima to the first successfully
  authenticated Game Center player. The same unbound values may never be
  claimed by a later player. Future offline work is queued to the already-known
  authenticated player whenever that identity is available to the run.
- **2026-07-17:** Locked Apple-only production diagnostics using OSLog, Apple
  crash reports, and MetricKit. The numerical 99.5% crash-free-session target
  is replaced by the release-candidate crash-review gate above.
- **2026-07-17:** Approved Settings as the main-menu entry point for Privacy and
  Support. The destination remains required, but a separate Privacy and Support
  control on the main menu is not required.
