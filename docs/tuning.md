# Native tuning guide

Version-one gameplay is considered feature-frozen. Tuning changes should fix a
measured fairness, readability, accessibility, or performance problem without
adding new mechanics. Change one coherent rule at a time and verify both the
deterministic core and the rendered result.

## Authoritative tuning surfaces

| Area | Native source |
| ---- | ------------- |
| Run duration, lanes, receiver/defender motion, throw thresholds and arcs | `ios/PocketVector/Game/Core/GameplayConfig.swift` |
| Outcome resolution, scoring, meter, streak, feedback timing | `ios/PocketVector/Game/Core/GameSimulation.swift` |
| World-to-screen projection and safe-area conversion | `ios/PocketVector/Game/Rendering/GameProjection.swift` |
| HUD geometry and compact breakpoints | `ios/PocketVector/Game/Rendering/HUDLayout.swift` |
| Player/field/HUD identity | `ios/PocketVector/Presentation/LaunchVisualIdentity.swift` |
| Economy payouts, prices, ad cadence, coin packs | `ios/PocketVector/Economy/EconomyConfiguration.swift` |
| Achievement thresholds | `ios/PocketVector/Achievements/AchievementCatalog.swift` |
| Default and persisted settings | `ios/PocketVector/Persistence/PlayerProfileFactory.swift` and profile models |

Do not duplicate a tuning value in SwiftUI copy or an adapter. UI derives
presentation from domain values, and platform services receive immutable domain
requests.

## Gameplay constraints

- Keep fixed-step simulation at 60 Hz and deterministic for a given seed.
- Maintain frame-partition independence for movement and collision.
- Preserve the 60-second run, bounded final-ball grace, and single authoritative
  football.
- Preserve normal receiver speed before a catch, 1.5-times normal speed after a
  catch while on the field, and 2-times normal speed beyond either sideline.
- Keep throw eligibility blocked only while the authoritative football is
  airborne; do not add a post-resolution input cooldown.
- A valid throw remains distance/upfield based; release speed shapes the arc but
  does not decide whether the gesture is accepted.
- Receiver spawn/despawn bounds must clear the widest supported field art.
- Paid or unlocked cosmetics may never affect collision, speed, score, payout,
  or opponent selection.

## Layout constraints

- Test both 667 x 375 and 932 x 430 compact landscape geometry.
- Keep all controls inside safe-area insets, including the Dynamic Island side.
- Protect the playfield from menu, matchup, readiness, and exit chrome.
- Verify primary and alternate palettes for all eight teams and both footballs.
- Check large Dynamic Type, VoiceOver labels, reduced motion, mute, and pause on
  physical iPhone and iPad hardware before release.

## Economy constraints

Economy values are release rules, not casual feel knobs. Any change must update
the product charter, deterministic ledger tests, store presentation, App Store
product metadata, and balancing evidence together. Never change an identifier
for an already shipped ledger mutation or StoreKit product.

## Launch achievements

`AchievementCatalog.launch` is the authoritative eight-achievement catalog.
Successful passes always include both completions and touchdowns.

| Achievement | Permanent ID | Points | Requirement |
| ----------- | ------------ | -----: | ----------- |
| First Read | `achievement.first_read.v1` | 25 | Complete any successful pass. |
| Paydirt | `achievement.paydirt.v1` | 50 | Score a touchdown. |
| Cash the Charge | `achievement.cash_the_charge.v1` | 75 | Score a touchdown while TD Bonus is active. |
| Full Route Tree | `achievement.full_route_tree.v1` | 75 | Complete a pass in all four lanes during one run. |
| Dialed In | `achievement.dialed_in.v1` | 75 | Finish with at least 80% accuracy over at least 25 pass attempts. |
| Hot Hand | `achievement.hot_hand.v1` | 100 | Score four consecutive touchdowns during one run. |
| Light Up the Board | `achievement.light_up_the_board.v1` | 100 | Reach 65,000 points during one run. |
| Millennia of Connections | `achievement.millenia_of_connections.v1` | 100 | Complete 1,000 career passes, including touchdowns. |

The catalog totals 600 points. The permanent Game Center ID for Millennia of
Connections intentionally spells `millenia` with one `n`; do not correct or
alias that persisted value.

### Catalog V1 to V2 persistence transition

`AchievementCatalogTransitionV1ToV2` is the versioned semantic contract. PM
persistence must apply it exactly once, idempotently, before validating any
supported profile against the current catalog:

- Replace `achievement.century_of_connections.v1` with
  `achievement.millenia_of_connections.v1`. Recompute progress as
  `floor(min(career.successfulPasses, 1,000) * 100 / 1,000)` from the
  authoritative career counter; never carry the retired percentage forward.
  When complete, use the earliest naturally completed run that takes the
  chronological successful-pass total to 1,000 as `completedAt`; otherwise the
  completion date is nil.
- Recompute Dialed In and Light Up the Board as binary states from authoritative
  naturally completed run records under the current 25-attempt/80-percent and
  65,000-point rules. An obsolete completion that no longer qualifies becomes
  zero percent with no completion date. A valid completion uses the earliest
  qualifying run's `recordedAt`.
- Remove the retired Century ID from current achievement progress and every
  bound or unbound Game Center queue. Scrub all three affected current IDs from
  those queues before rebuilding them.
- Reinsert affected pending work only from a positive percentage in the same
  bound or unbound provenance bucket and the same logical achievement: Dialed
  evidence authorizes only
  Dialed, Light evidence authorizes only Light, and either retired Century or
  current Millennia evidence authorizes only Millennia. Mixed Century and
  Millennia evidence in one bucket collapses to one current entry. Replace the
  queued value with no more than freshly earned progress; never manufacture
  pending work for an already acknowledged achievement, and remove empty player
  buckets.
- Rebuild affected achievement updates stored in settlement receipts by
  replaying authoritative naturally completed runs in `recordedAt`, then run-ID
  order under V2 rules. For each receipt's run ID, replace only its retired or
  affected-current achievement updates with the replay result. Preserve
  unrelated updates and every non-achievement receipt field so an idempotent
  settlement retry cannot restore an obsolete award.
- Preserve all unrelated achievement progress and queue work. Mixed old/new
  input must converge without duplicate awards or submissions.

The V2 catalog and transition material are part of the achievement semantic
fingerprint. Activating it for an existing cloud replica scope requires the
PM-owned checkpoint transition and persistence migration; Technical code must
not silently reinterpret sealed profile or queue authority.

## Verification workflow

1. Record the observed problem and the device/run evidence.
2. Identify one authoritative native constant or calculation.
3. Add or update a deterministic regression before changing behavior.
4. Run the focused test class.
5. Run the complete simulator suite.
6. Play representative runs on compact iPhone, regular iPhone, and iPad layouts.
7. For resource, capability, app-composition, or Release changes, create an
   unsigned generic-iOS archive.
8. Update `production-release-status.md` with evidence only after all gates pass.

Debug previews and test fakes must never persist scores, runs, coins,
achievements, ownership, or service queues.
