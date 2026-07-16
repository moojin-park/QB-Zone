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
