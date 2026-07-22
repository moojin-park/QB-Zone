# Pocket Vector production release status

Status date: 2026-07-21

This is the living delivery board for the first iOS release. Product scope and
rules remain authoritative in
[`production-release-charter.md`](production-release-charter.md); this file
tracks execution, evidence, dependencies, and owner decisions.

## Current outcome

The native foundation, launch rules, durable local repository, production app
shell, first-run tutorial, fail-closed release information, eight-team emblems
and field visuals, retained production runtime, and Apple-only diagnostics
composition are complete. Typed first-zone Cloud replica genesis is versioned
at `a584b65` (`Add typed cloud replica genesis`), and the repository hydration
mutation barrier is versioned at `1a8036e` (`Add hydration mutation barrier`).
The typed ordinary publication boundary immediately beneath them is `20e1cbc`
(`Add
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

The Art-approved final High Mesa main menu through submitted commit `99909f5`
is integrated as the ordered, patch-equivalent chain ending at `9b450ba` (`Art:
separate phone utilities from score`). The integrated Art-owned tree exactly
matches the approved submission. Asset-catalog JSON, the focused resource and
Privacy and Support route tests, the complete simulator suite, compact and
regular iPhone plus iPad captures, and an unsigned generic-iOS Release archive
all passed. The compact-device UI smoke traversed Settings to Privacy and
Support and back to the main menu, and exposed the expected labels, hints,
five-digit score, and pending-coin value. Static independent review found no
P0-P2 regression and confirmed both operating-system and persisted reduced-
motion inputs suppress utility scaling animation. A live reduced-motion toggle
was not repeated after the QA Mac auto-locked. Art follow-up remains to remove
25 superseded, unreferenced QA captures and correct the stale manifest-blocker
note in `menu-design-qa.md`; fresh PM captures are clean and no source-art or QA
evidence is present in the archive.

The approved Championship Marquee app icon submitted at `abd34bd` is integrated
at `bd2b51c` (`Art: ship Championship app icon`). The committed 1254-pixel
opaque source deterministically reproduces the shipping 1024-pixel opaque PNG
with the documented SHA-256. Asset-catalog JSON, a fresh complete simulator
suite, compact-iPhone, regular-iPhone, and iPad launcher-scale inspection, and
an unsigned generic-iOS Release archive passed. The archived app contains the
compiled 120-pixel iPhone and 152-pixel iPad icons, the privacy manifest, and
the exact GameAssets package without source-art or documentation content.

The complete Art branch through `cc029c3` is merged at `ad2f50e` (`Merge latest
Art direction`), preserving its submitted ancestry. It adds the paused gameplay
status panel, fixes the Resume label shadow, removes the active-gameplay matchup
capsule, refines the PAUSED/STATS header and confirmed END RUN flow, and supplies
the registered 1728 x 768 layered field package. The exact shipping manifest
declares 76 unique assets: 60 images and 16 audio files.

The complete Technical branch through `04060b8` is merged at `3ed7598` (`Merge
latest Technical direction`). Gameplay now renders the neutral stadium base,
selected offense's transparent end-zone and midfield paint, and universal
markings in registered order, with actors and the HUD above the field. The
combined 44-test presentation/gameplay gate, 827-test simulator suite,
deterministic field regeneration, independent integration and archive audits,
Debug simulator build, and unsigned generic-iOS Release archive passed with no
open P0-P3 finding. The verified Debug build is installed and launched on the
iPhone 17 Pro simulator for owner testing. Compact-iPhone, regular-iPhone, and
iPad paused-panel and field visual acceptance remains pending.

The latest Art head `bf3d8c8` (`Art: implement approved team emblems`) is merged
with full ancestry at `e796ce0` (`Merge latest Art direction`). It supplies
eight distinct normalized emblem definitions and palettes, updates seven
midfield-branding layers while retaining High Mesa, and includes compact-iPhone,
regular-iPhone, iPad, and field-registration QA composites. The latest Technical
head `80e0e41` (`Implement scorebug reaction HUD`) is merged with full ancestry
at `475e3af` (`Merge latest Technical direction`). The scorebug now owns
semantic one- or two-line play reactions with compact/regular/iPad geometry,
reduced-motion presentation, restartable lifetime, and deduplicated VoiceOver
announcements. Deterministic regeneration, 72 focused tests, the exact 832-test
simulator suite, an unsigned generic-iOS Release archive, and independent review
passed with no open P0-P3 finding. Art's committed emblem evidence passed PM
inspection; integrated-device Art approval of the score-reaction presentation
remains pending before visual release acceptance.

The complete latest Art branch through `8f804ab` is merged with full ancestry at
`17792f2` (`Merge latest Art direction`). The approved championship submenu
redesign is present across Choose Your Offense, Team & Locker, Achievements,
Coin Store, and Settings, including the centered-title correction. Privacy and
Support remains available through Settings only. Compact-iPhone, regular-iPhone,
and iPad evidence passed PM inspection with no additional P0-P3 submenu finding;
the two documented P3 frame/crop choices remain accepted.

The ordered Art tutorial and results chain `e68651d` then `092580d` is merged
with full ancestry at `d0dee1a` (`Merge latest Art direction`). Asset-catalog
JSON, exact source/runtime media checks, 60 focused tests, the exact 836-test
simulator suite, and an unsigned generic-iOS Release archive passed. At the
standard text size, the three-panel tutorial passed compact-iPhone,
regular-iPhone, and iPad inspection, and the results screen passed compact-
iPhone inspection. Visual release acceptance is withheld: at Accessibility
XXXL on compact landscape, tutorial content and the header accessory clip, and
the results summary truncates while its actions leave the visible frame. The
three-step tutorial also no longer covers several subjects promised by the
Technical-owned four-step gameplay documentation; that contract must be
reconciled before this presentation is accepted.

The revised Art branch through `6516be6` is merged with full ancestry at
`371b876` (`Merge revised Art accessibility and tutorial`), followed by the
revised Technical scoring commit `bd47ac2` at `29a8b5d` (`Merge revised
gameplay scoring mechanics`). The integrated tutorial now has Rules and Passing
pages, semantic Dynamic Type header reflow, compact page badges, pinned
accessibility actions, Previous navigation, reduced-motion gating, and
SHA-256-validated tutorial media caching. Gameplay applies a fixed 250-point
interception penalty with a zero score floor, preserves the touchdown
multiplier through completions, resets it after incompletions or interceptions,
keeps the consecutive-touchdown statistic separate, and reports the applied
interception deduction in the HUD and VoiceOver feedback. The 142-test combined
focus and exact 846-test simulator suite passed with no failure and the single
existing filesystem skip. Visual release acceptance remains withheld: compact
Accessibility 5 Results truncates `PLAY AGAIN`, and the shared header reflow
truncates the Team & Locker subtitle while consuming most of the compact
content area. Regular-iPhone and iPad Accessibility 5 Tutorial and Results
captures passed. No archive was required because this revision changes no
resource, capability, app-composition, or Release configuration path.

Art follow-up `46c4b96` is merged with full ancestry at `df690b8` (`Merge
compact accessibility Art fixes`). Compact Accessibility 5 now keeps complete
shared-header subtitles readable across Choose Your Offense, Team & Locker,
Coin Store, Achievements, Settings, Tutorial, and Results, while preserving
reachable content and actions. Results displays the complete `MAIN MENU` and
`PLAY AGAIN` labels. The 61-test focused gate and exact 847-test simulator
suite passed with no failure and the single existing filesystem skip. PM
inspection of the 40-capture shared-header matrix passed compact Accessibility
5 plus regular-iPhone and iPad standard regressions. The iPad Accessibility 5
Results stat labels wrap awkwardly but remain complete and reachable; this is an
accepted P3. No archive was required because the follow-up changes no resource,
capability, app-composition, or Release configuration path. The tutorial,
Results, and shared-header accessibility presentation is release-accepted.

Art follow-up `5dae317` is merged with full ancestry at `a07950f` (`Merge
looping tutorial passing media`). Tutorial media remains paused and reset on
Rules page one, starts from the beginning only after entering Passing page two,
and uses a retained `AVQueuePlayer` with `AVPlayerLooper` for continuous
playback. Reduce Motion pauses and resets playback and suppresses the player
surface in favor of the static poster. The 11-test focused presentation gate
and exact 849-test simulator suite passed with no failure and the single
existing filesystem skip. Manual simulator verification on a disposable fresh
iPhone 17 Pro observed progress reset across multiple loop boundaries and a
static unchanged Passing presentation for six seconds with Reduce Motion
enabled. No archive was required because the follow-up changes no resource,
capability, app-composition, or Release configuration path.

The same Art merge adds 544 baked team-and-jersey character frames and expands
the exact native inventory from 76 to 620 assets. All 16 team/uniform sets pass
the deterministic 34-frame validator. The complete Technical branch through
`fd74e2f` (`Route gameplay actors to baked team uniforms`) is merged with full
ancestry at `db02d4c` (`Merge latest Technical direction`). Gameplay now routes
the selected offense and clash-resolved defense through their exact baked
team/jersey paths, preserves decoded RGBA without palette projection, and keeps
the generic fallback disabled unless explicitly requested for development.
The 31-test focused gate and exact 836-test simulator suite passed, and
independent reviews found no open P0-P3 issue. Compact and wide landscape
gameplay visual approval remains required before live-uniform visual acceptance.
No new archive was required because the Technical wave changed runtime routing
and tests without changing resources, capabilities, app composition, or Release
configuration; the prior 620-resource archive remains the applicable resource
evidence.

Technical gameplay handoff `955a63e` is integrated patch-equivalently at
`d5131cf` (`Expose explicit paused gameplay controls`). The PM bridge at
`e9af0bc` (`Bridge explicit gameplay presentation actions`) retains one
`GameScene`, seeds presentation from its current `GameplaySceneSnapshot`,
relays mounted snapshot changes, and routes duplicate-safe Resume and confirmed
Exit Run requests through explicit scene actions. Confirmed Exit still emits a
single `CompletedRun`; `AppCoordinator` remains the only settlement and
navigation authority, including failure and retry. The focused 25-test gate,
exact 816-test simulator suite, unsigned generic-iOS Release archive, and two
independent audits passed with no open P0-P2 finding. The Art-owned paused panel
is now integrated through `ad2f50e`; multi-device landscape visual approval
remains required before release acceptance.

The complete Technical branch through `d89e722` (`Expose versioned run reward
breakdown`) is merged with full ancestry at `67d9a2b` (`Merge Technical
versioned reward breakdown`). `CompletedRun` now resolves completion,
performance, and accuracy coins through immutable economy-version rules and
fails closed for unsupported versions. The PM Results projection at `91c77ee`
(`Consume versioned reward breakdown in Results`) consumes that authoritative
breakdown, requires its checked component sum to equal the durable settlement
reward, exposes pending/recorded state only for this settlement's gameplay and
signing-bonus ledger IDs, and keeps rewarded-ad coins separate. The 78-test
focused integration gate, exact 864-test simulator suite, unsigned generic-iOS
Release archive, diff hygiene, and two independent audits passed with no open
P0-P2 finding. Art still must retain and freeze the completed gameplay surface,
place a transparent noninteractive Results overlay above it without competing
gameplay HUD, and complete multi-device visual verification before this Results
revision receives visual release acceptance.

The diverged Art Results handoff `08ff44d` (`Redesign run results as field
overlay`) and release baseline `d96f027` are joined as the two parents of
`b047ce0` (`Merge Art Results field overlay`), preserving both complete
histories so Art can fast-forward from the new shared baseline. The single
shared-test conflict retained release's authoritative reward components and
ledger states; the integrated Art coin ledger now consumes those supplied
values directly, reconciles them with overflow checking, and derives pending
presentation only from this settlement's gameplay and signing-bonus states.
The misplaced root-level Art QA note is excluded from the merged tree while
remaining available in the submitted commit's history. Seven authored Results
bezels/icons, their asset-catalog renditions, the responsive overlay, and the
Art documentation are integrated. Asset JSON, six supplied compact/regular/
iPad standard and Accessibility 5 captures, the 56-test focused gate, exact
866-test simulator suite, unsigned generic-iOS Release archive, diff hygiene,
and independent audits passed. This is an ancestry and continuation baseline,
not final Results visual acceptance: Art must still retain the same gameplay
adapter and `GameScene` beneath Results, freeze and hide it from interaction
and accessibility, suppress its controls, and remove the synthetic field
fallback before the integrated presentation can be accepted.

Art handoff `71ccd0e` (`Retain gameplay surface beneath run results`) is merged
with full ancestry at `3acbf4c` (`Merge retained gameplay Results surface`).
The production gameplay adapter retains the exact `SKView` and `GameScene` for
the completed run, freezes both render surfaces, removes the synthetic field
fallback, and presents the transparent Results overlay above that stable final
frame. The retained field is noninteractive and accessibility-hidden; gameplay
HUD, paused/settlement chrome, and the scene-local gameplay gesture request are
suppressed while Results is visible. The owner-approved app-wide window-root
exit policy remains in force. Existing Main Menu and Play Again coordinator
routes remain unchanged. The misplaced root-level Art QA note was excluded from
the merged tree. Independent review found no P0-P2 issue; the accepted P3 is the
compact Accessibility 5 wrap of `OPTIONAL` as `OPTION-` / `AL`. Twenty-six
focused tests, the exact 872-test simulator suite, compact/regular/iPad standard
and Accessibility 5 evidence, and an unsigned generic-iOS Release archive all
passed. This completes the retained-gameplay Results visual acceptance gate.

The root-controller system-gesture correction was introduced at `e1c0f9a`
(`Make gameplay gesture deferral root authoritative`), physically corrected at
`d7d3eeb` (`Make UIKit container own gesture deferral`), and finalized under the
owner-approved app-wide policy at `6e20347` (`Lock bottom gesture deferral
app-wide`). The application installs a PM-owned plain `UIViewController` as the
window root and retains the SwiftUI application in one child
`UIHostingController`. The UIKit root is the sole screen-edge authority and
always returns `.bottom`, so Main Menu, countdown, live play, final-ball
resolution, Pause, Results, settlement, background transitions, and every other
app surface require the deliberate repeated Home gesture. A one-touch root
`UIPanGestureRecognizer` neither cancels nor delays content touches and permits
simultaneous recognition, preserving SpriteKit throws and SwiftUI scrolling.
The root reasserts system-UI authority after appearance, safe-area, and scene-
activation changes. It hides the status bar directly and intentionally keeps
Home-indicator auto-hide disabled; physical Face ID testing proved that taking
auto-hide ownership reproduced the one-swipe exit regression. The internal
run/snapshot policy remains covered for scene-local presentation behavior but
cannot clear the window-root exit policy.

Build 156 passed physical acceptance on `Snow J` (iPhone 17 Pro Max, iOS
26.5.2): one swipe remained in Main Menu, the second deliberate swipe exited,
one countdown swipe remained in the game, and one active-play swipe both stayed
in the game and threw the pass. The owner accepted the final build, ordinary UI
interactions, and normal Home-indicator presentation. The exact 880-test final
simulator suite and unsigned generic-iOS Release archive passed. Independent
review found no remaining P0-P3 issue after the explicit Home-indicator decision
and simultaneous-recognition safeguard.

Build 157 integrates Technical handoff `c158148` (`Remove post-pass cooldown
and accelerate caught receivers`) from exact accepted baseline `7773486`.
Resolved passes no longer impose an artificial delay before the next throw;
the live ball still blocks duplicate throws. A receiver carrying a completed
pass runs at 1.5 times ordinary on-field speed and retains the existing 2 times
speed after crossing the sideline. The exact 883-test simulator suite and an
unsigned generic arm64 iOS Release archive passed. The first complete-suite
attempt encountered one simulator media-playback teardown crash in the
unrelated tutorial/results capture test; that test passed alone and in the
fresh complete acceptance run.

Build 158 is the publication-hardening candidate. Its privacy manifest now
declares the approved reasons used by the shipping app for file timestamps
(`C617.1`), system boot time (`35F9.1`), and app-scoped defaults (`CA92.1`). The
unused Push Notifications entitlement is removed, and source regressions keep
it absent while retaining the exact Game Center and CloudKit containers. The
launch build is explicitly limited to the tested iPhone and iPad platforms;
Apple silicon Mac and Apple Vision Pro compatibility distribution are disabled
until those environments receive their own QA. The exact simulator suite
passed 885 total tests with 884 passes, no failures, and the one established
conditional filesystem skip. Release target analysis and the unsigned generic
iOS archive passed. An App Store Connect export then passed using an Apple-
managed distribution certificate and store profile. The exported 1.0 (158)
app has `get-task-allow = false`, Production CloudKit, container
`iCloud.com.pocketvector.game`, Game Center, no APS entitlement, the expected
privacy manifest, and no test/debug/source/QA payload.

The Technical cinematic-presentation handoff `e1f4d94` (`Add countdown
cinematic letterbox`) is integrated with full ancestry from shared baseline
`d57714e`. Equal responsive black bars ease from zero to their completed height
during the authoritative three-second countdown, remain presented through live
play, final-ball resolution, and Pause, and clear before the retained Results
field is shown. Reduce Motion presents the completed bars immediately. Technical
follow-up merged at `9a86c76` makes both bars presentation-only, restores the
countdown cues, and allows normal throw starts anywhere on the gameplay surface,
including beneath the bottom bar after live play begins. Field projection,
actors, trajectories, collision, scoring, and simulation remain unchanged. PM
live inspection passed compact-iPhone, regular-iPhone, and iPad active frames,
the regular-iPhone standard countdown, the retained Results field with the bars
removed, and the physical bottom-edge throw under the final app-wide gesture
policy. Final Art-owned visual acceptance of the complete standard-motion,
Reduce Motion, Pause, and Results sequence remains pending.

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

The durable one-time local-to-cloud claim, outbound initial publication,
committed-association recovery, authoritative checkpoint refresh, account-
scoped runtime, private-cloud economy, and online-only StoreKit composition are
now implemented. The runtime enables private-cloud sync and purchases only for
complete validated CloudKit and StoreKit configuration; the repository's
missing release contact values and service dictionaries therefore remain fail
closed until the owner publishes the destinations and creates the permanent
App Store records. Player-scoped Game Center delivery and rewarded-ad
verification/recovery remain unavailable in the live app. Build 158 completes
the final codesigned distribution-entitlement proof, but live service records,
privacy answers, TestFlight metrics, and submission metadata remain external
release-candidate gates.

## Delivery board

| Milestone                                       | State               | Exit evidence                                                                                                                         |
| ----------------------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Product charter and release gates               | Complete            | Scope, roster, economy, achievements, ads, persistence, devices, and success gates approved                                           |
| Reproducible native foundation                  | Complete            | Clean-checkout tests and unsigned Release archive pass at `49d8a6b`                                                                   |
| Domain, catalog, economy, and achievement rules | Complete            | Eight teams, inventory, matchup, clash, reward, coin-pack, and eight-achievement rules pass exhaustive tests                          |
| Durable local player profile and ledger         | Complete            | Atomic recovery, migration, account isolation, idempotent settlement, unlock, ad reward, and relaunch tests pass                      |
| Account-independent service foundations         | Complete            | Cloud transport/checkpoint, typed genesis/publication/hydration, canonical V4 seed, player-scoped Game Center delivery, StoreKit runtime, and challenge-only rewarded-ad verification/recovery foundations pass; none implies live composition |
| Production app shell and menus                  | Complete            | Art-approved High Mesa main menu plus championship-styled offense selection, locker, store, achievements, and Settings ship; Privacy and Support remains Settings-routed |
| Tutorial and results presentation               | Complete            | The tutorial and authoritative Results coin breakdown pass; Results retains and freezes the exact gameplay scene beneath a transparent overlay, suppresses gameplay chrome and interaction, and passes compact/regular/iPad standard and Accessibility 5 gates with one accepted P3 compact label wrap |
| Retained production runtime and diagnostics     | Complete            | Process-owned coordinator/diagnostics tasks, restartable versioned state, Apple-only telemetry, typed config, and UIKit handoff pass   |
| Gameplay settlement integration                 | Complete            | Release composition persists natural and abandoned runs exactly once and projects authoritative results after settlement             |
| Paused gameplay presentation                    | Complete            | Refined Art panel and Technical/PM snapshot, Resume, and confirmed-exit actions are integrated; combined tests and owner acceptance of the finalized release build pass |
| Layered team-field assets                       | Complete            | Registered neutral, universal-marking, and eight-team paint layers are bundled and rendered in exact order; deterministic, simulator, archive, and owner release acceptance pass |
| Scorebug reaction presentation                  | Complete            | Semantic one/two-line reactions, responsive geometry, reduced motion, lifecycle, VoiceOver, integrated simulator, and owner release acceptance pass |
| Cinematic gameplay framing                      | Complete            | Responsive countdown-to-gameplay bars are presentation-only; multi-device live inspection, physical bottom-edge input, complete-suite, and owner release acceptance pass |
| Eight-team presentation system                  | Complete            | Eight emblems, fields, and baked primary/alternate character sets are bundled and actively routed without palette projection; exact resource and owner release acceptance pass |
| Live Apple and advertising services             | In progress         | Cloud claim/hydration and online-only StoreKit composition are implemented and fail closed without complete configuration; permanent IDs, products, records, production schema, Game Center retention, authenticated ad transport/SSV and deduplication, SDK/consent, and signed-device gates remain |
| iOS-only repository cleanup                     | Complete            | Native sources/tools are retained under `ios/`; browser runtime, dependencies, tests, build files, and unused assets are removed      |
| TestFlight release candidate                    | In progress         | Build 158 passes complete tests, unsigned archive, and App Store distribution export; permanent live-service configuration, TestFlight metadata, upload/processing, and sandbox/device gates remain |
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
| 2026-07-17 | `9b450ba` | Art-approved menu integration and focused gates | Six submitted Art commits integrated in order; approved Art tree matches `99909f5`; asset JSON valid; resource and Privacy and Support route tests passed 2 of 2 |
| 2026-07-17 | `9b450ba` | Exact integrated full simulator suite | 771 total: 770 passed, 0 failed, 1 existing conditional case-alias skip; result bundle `/tmp/pocketvector-art-full-99909f5-v1.xcresult` |
| 2026-07-17 | `9b450ba` | Compact/regular iPhone and iPad menu QA | Fresh captures passed at `/tmp/pocketvector-menu-compact-99909f5-v1.png`, `/tmp/pocketvector-menu-regular-99909f5-v1.png`, and `/tmp/pocketvector-menu-ipad-99909f5-v1.png`; compact Settings → Privacy and Support → Back navigation and accessibility labels/hints passed |
| 2026-07-17 | `9b450ba` | Unsigned generic-iOS Release archive | Passed at `/tmp/pocketvector-art-archive-99909f5-v1/PocketVector.xcarchive`; arm64, iPhone/iPad, landscape-only, iOS 17+, all seven new Menu imagesets, exact 58 GameAssets plus manifest, and no source-art, QA, or documentation content bundled |
| 2026-07-18 | `2efed0a` | Online-only commerce focused integration gate | 146 passed, 0 failed, 0 skipped before the final crash-outcome regression; the added protected-CAS fault test and affected association/economy regressions also passed |
| 2026-07-18 | `2efed0a` | Exact integrated full simulator suite | 806 total: 805 passed, 0 failed, 1 conditional case-alias skip on a case-sensitive filesystem; result bundle `/tmp/PocketVector-OnlineCommerce-Gate.gZ3xoY/Logs/Test/Test-PocketVector-2026.07.18_03-59-38--0700.xcresult` |
| 2026-07-18 | `2efed0a` | Online-commerce independent audit | Final adversarial review found one protected-profile crash-outcome P1; it was fixed before commit with fault-injection coverage, and the final reviewed implementation has no open P0–P3 findings |
| 2026-07-18 | `2efed0a` | Unsigned generic-iOS Release archive | Passed at `/tmp/PocketVector-OnlineCommerce-Final-20260718.xcarchive`; arm64, iPhone/iPad, landscape-only, iOS 17+, Production CloudKit compiler condition, privacy manifest, and native asset manifest present |
| 2026-07-18 | `bd2b51c` | Championship app-icon integrity and build gate | All asset-catalog JSON passed; documented ImageMagick regeneration exactly matched shipping SHA-256 `b21e93de...`; fresh Debug build and asset compilation passed |
| 2026-07-18 | `bd2b51c` | Exact integrated full simulator suite | 806 total: 805 passed, 0 failed, 1 conditional case-alias skip on a case-sensitive filesystem; clean-boot rerun result bundle `/tmp/PocketVector-Art-abd34bd.9Du355/Logs/Test/Test-PocketVector-2026.07.18_13-21-53--0700.xcresult` |
| 2026-07-18 | `bd2b51c` | Compact iPhone, regular iPhone, and iPad launcher QA | App icon remained readable and unclipped at actual launcher sizes in `/tmp/PocketVector-AppIcon-abd34bd-compact.png`, `/tmp/PocketVector-AppIcon-abd34bd-regular.png`, and `/tmp/PocketVector-AppIcon-abd34bd-ipad.png` |
| 2026-07-18 | `bd2b51c` | Unsigned generic-iOS Release archive | Passed at `/tmp/PocketVector-Art-abd34bd-Release.xcarchive`; arm64, iPhone/iPad, landscape-only, iOS 17+, Production CloudKit condition, compiled iPhone/iPad icons, privacy manifest, and exact 59-file GameAssets package present; no source-art or documentation bundled |
| 2026-07-18 | `e9af0bc` | Gameplay snapshot/action bridge focused gate | Technical submission `955a63e` integrated patch-equivalently at `d5131cf`; 25 bridge, coordinator, and gameplay tests passed with no failure or skip; independent reviews found no P0-P2 finding and the only P3 test-harness note was fixed before commit |
| 2026-07-18 | `e9af0bc` | Exact integrated full simulator suite | 816 total: 815 passed, 0 failed, 1 existing conditional case-alias skip on iPhone 17 Pro; result bundle `/tmp/PocketVector-GameplayBridge-e9af0bc-full.xcresult` |
| 2026-07-18 | `e9af0bc` | Unsigned generic-iOS Release archive | Passed at `/tmp/PocketVector-PausedBridge-e9af0bc.6CD0Tg/PocketVector.xcarchive`; arm64, iPhone/iPad, landscape-only, iOS 17+, Production CloudKit compile condition/build setting, privacy manifest, and exact 58-asset GameAssets package verified; final codesigned entitlement proof remains pending |
| 2026-07-18 | `0971f9b` | Layered team-field manifest and asset gate | Focused manifest test passed 1 of 1; 76 unique declared assets exactly match 76 physical resources (60 image, 16 audio); deterministic regeneration and independent asset/integration audits passed with no open P0-P3 finding |
| 2026-07-18 | `0971f9b` | Exact integrated full simulator suite | 816 total: 815 passed, 0 failed, 1 existing conditional case-alias skip on iPhone 17 Pro; result bundle `/tmp/PocketVector-LayeredField-0971f9b-full.xcresult` |
| 2026-07-18 | `0971f9b` | Unsigned generic-iOS Release archive | Passed at `/tmp/pocket-vector-release-archive-verified.uX4Sj4/PocketVector.xcarchive`; arm64, iPhone/iPad, landscape-only, iOS 17+, Production CloudKit condition, valid privacy manifest, and exact 76-asset GameAssets package verified; source art, tools, and repository documentation are absent |
| 2026-07-18 | `3ed7598` | Full Art and Technical branch integration | Art head `cc029c3` merged at `ad2f50e`, then Technical head `04060b8` merged at `3ed7598`; combined 44-test presentation/gameplay gate passed, deterministic field regeneration produced no diff, and independent review found no open P0-P3 finding |
| 2026-07-18 | `3ed7598` | Exact combined full simulator suite | 827 total: 826 passed, 0 failed, 1 existing conditional case-alias skip on iPhone 17 Pro; result bundle `/tmp/PocketVector-Combined-3ed7598-full.xcresult` |
| 2026-07-18 | `3ed7598` | Combined unsigned generic-iOS Release archive | Passed at `/tmp/pocket-vector-combined-archive-3ed7598.ozYLrE/PocketVector.xcarchive`; arm64, iPhone/iPad, landscape-only, iOS 17+, Production CloudKit condition, valid privacy manifest, exact 76-asset package, and no bundled source art, tools, or documentation |
| 2026-07-18 | `3ed7598` | Owner simulator build | Clean Debug simulator build passed and was installed without erasing app data on iPhone 17 Pro; `com.pocketvector.game` launched successfully for owner gameplay testing |
| 2026-07-19 | `475e3af` | Latest full Art and Technical branch integration | Art head `bf3d8c8` merged at `e796ce0`, then Technical head `80e0e41` merged at `475e3af`; both submitted heads are ancestors and their final owned trees exactly match the submissions |
| 2026-07-19 | `475e3af` | Emblem and score-reaction focused gate | 72 passed, 0 failed, 0 skipped on iPhone 17 Pro; deterministic generation reproduced all 19 field assets with no diff; independent review found no open P0-P3 finding |
| 2026-07-19 | `475e3af` | Exact combined full simulator suite | 832 total: 831 passed, 0 failed, 1 existing conditional case-alias skip on iPhone 17 Pro; result bundle `/tmp/PocketVector-Emblems-ReactionHUD-475e3af-full.xcresult` |
| 2026-07-19 | `475e3af` | Integrated Art evidence review | Compact-iPhone, regular-iPhone, iPad, and field-registration emblem composites passed PM inspection; integrated-device Art approval of the Technical score-reaction presentation remains pending |
| 2026-07-19 | `475e3af` | Unsigned generic-iOS Release archive | Passed at `/tmp/pocket-vector-team-brand-archive-475e3af.8JFlyF/PocketVector.xcarchive`; arm64, iPhone/iPad, landscape-only, iOS 17+, Production CloudKit condition, valid privacy manifest, exact 76-asset package including seven changed branding files, and no QA/source/tool/doc content |
| 2026-07-19 | `17792f2` | Latest full Art branch integration | Art head `8f804ab` merged with full ancestry; all five championship submenus and the centered-title follow-up are present; deterministic submenu regeneration and all 16 baked-uniform validators produced no diff |
| 2026-07-19 | `17792f2` | Submenu, identity, coordinator, and manifest gate | 43 passed, 0 failed, 0 skipped on iPad Pro 13-inch; exact 620-asset manifest test passed; result bundle `/tmp/PocketVector-Art-Focused-iPad-17792f2.xcresult` |
| 2026-07-19 | `17792f2` | Exact integrated full simulator suite | 832 total: 831 passed, 0 failed, 1 existing conditional case-alias skip on iPad Pro 13-inch; result bundle `/tmp/PocketVector-Art-Full-17792f2.xcresult` |
| 2026-07-19 | `17792f2` | Integrated Art visual and independent review | Compact-iPhone, regular-iPhone, and iPad submenu evidence passed PM inspection with no submenu P0-P3 finding; independent runtime audit found one P1 because baked team uniforms remain dormant pending Technical routing |
| 2026-07-19 | `17792f2` | Unsigned generic-iOS Release archive | Passed at `/tmp/pocket-vector-art-release-17792f2.sNZWsP/PocketVector.xcarchive`; arm64, iPhone/iPad, landscape-only, iOS 17+, Production CloudKit, valid privacy manifest, exact 620-asset package, all 20 submenu renditions in `Assets.car`, and no QA/source/tool/doc content |
| 2026-07-19 | `db02d4c` | Latest full Technical branch integration | Technical head `fd74e2f` merged with full ancestry; exact baked offense and clash-resolved defense paths are active, decoded RGBA bypasses palette projection, production fallback is disabled, and independent reviews found no open P0-P3 finding |
| 2026-07-19 | `db02d4c` | Baked-uniform routing focused gate | 31 passed, 0 failed, 0 skipped on iPad Pro 13-inch; result bundle `/tmp/PocketVector-UniformRouting-db02d4c-focused.xcresult` |
| 2026-07-19 | `db02d4c` | Exact integrated full simulator suite | 836 total: 835 passed, 0 failed, 1 existing conditional case-alias skip on iPad Pro 13-inch; result bundle `/tmp/PocketVector-UniformRouting-db02d4c-full.xcresult`; runtime-only wave did not require a new archive |
| 2026-07-20 | `d0dee1a` | Ordered Art tutorial/results integration | Art commits `e68651d` then `092580d` merged with full ancestry; all 16 changed paths are Art-owned; asset-catalog JSON, 620-asset manifest count, diff hygiene, declared-file presence, image identity, video decode, and source/runtime quality checks passed |
| 2026-07-20 | `d0dee1a` | Tutorial/results focused simulator gate | 60 passed, 0 failed, 0 skipped across tutorial/privacy, app coordinator, gameplay coordinator, and launch visual identity tests; result bundle `/tmp/PocketVector-Art-TutorialResults-d0dee1a-focused.xcresult` |
| 2026-07-20 | `d0dee1a` | Exact integrated full simulator suite | 836 total: 835 passed, 0 failed, 1 existing conditional case-alias filesystem skip; result bundle `/tmp/PocketVector-Art-TutorialResults-d0dee1a-full.xcresult` |
| 2026-07-20 | `d0dee1a` | Unsigned generic-iOS Release archive | Passed at `/tmp/PocketVector-Art-TutorialResults-d0dee1a-Release.xcarchive`; arm64, iPhone/iPad, landscape-only, iOS 17+, Production app metadata, privacy manifest, exact 620-file GameAssets package, and all four new compiled tutorial assets verified; no source-art, tool, or documentation leakage |
| 2026-07-20 | `d0dee1a` | Tutorial/results multi-device visual gate | Standard-size tutorial passed compact iPhone, regular iPhone, and iPad; standard-size results passed compact iPhone; playback, saved reduced motion, and accessibility labels/hints passed. Accessibility XXXL failed on compact landscape because tutorial and results content clips/truncates and results actions leave the visible frame; visual acceptance withheld. Evidence: `/tmp/PocketVector-Art-TutorialResults-d0dee1a-compact-tutorial.png`, `/tmp/PocketVector-Art-TutorialResults-d0dee1a-regular-tutorial.png`, `/tmp/PocketVector-Art-TutorialResults-d0dee1a-ipad-tutorial.png`, `/tmp/PocketVector-Art-TutorialResults-d0dee1a-compact-results.png`, and `/tmp/PocketVector-Art-TutorialResults-d0dee1a-compact-results-axxxl.png` |
| 2026-07-20 | `29a8b5d` | Revised Art then Technical integration | Art head `6516be6` merged with full ancestry at `371b876`, then rewritten Technical head `bd47ac2` merged at `29a8b5d`; both worktrees were clean, both deltas were domain-pure, merge previews were conflict-free, and independent audits found no P0/P1 code issue |
| 2026-07-20 | `29a8b5d` | Combined tutorial/scoring focused gate | 142 passed, 0 failed, 0 skipped across presentation, tutorial, app/gameplay coordinators, game core, gameplay session, economy/achievement, and launch visual identity tests; result bundle `/tmp/PocketVector-ArtScoring-29a8b5d-focused.xcresult` |
| 2026-07-20 | `29a8b5d` | Exact integrated full simulator suite | 846 total: 845 passed, 0 failed, 1 existing conditional case-alias skip on a case-sensitive filesystem; result bundle `/tmp/PocketVector-ArtScoring-29a8b5d-full.xcresult` |
| 2026-07-20 | `29a8b5d` | Revised multi-device visual gate | Standard and Accessibility 5 Rules, Passing, and Results captures passed on regular iPhone and iPad; compact Rules and Passing actions are reachable. Compact Accessibility 5 Results still truncates `PLAY AGAIN`, and live Team & Locker inspection truncates its subtitle while the shared header consumes most of the content area, so visual acceptance and a new shared baseline are withheld. Evidence: `/tmp/PocketVector-ArtScoring-29a8b5d-compact-ax5-results.png` and `/tmp/PocketVector-ArtScoring-29a8b5d-compact-ax5-locker.png` |
| 2026-07-20 | `df690b8` | Compact Accessibility 5 Art integration | Art head `46c4b96` merged with full ancestry; all changed paths are Art-owned UI or corresponding presentation tests; merge preview, ownership review, and diff hygiene passed with no P0-P2 finding |
| 2026-07-20 | `df690b8` | Shared-header and Results focused gate | 61 passed, 0 failed, 0 skipped across AppPresentation, LaunchVisualIdentity, AppCoordinator, and TutorialPrivacyCoordinator tests; result bundle `/tmp/PocketVector-Art-46c4b96-df690b8-focused.xcresult` |
| 2026-07-20 | `df690b8` | Exact integrated full simulator suite | 847 total: 846 passed, 0 failed, 1 existing conditional case-alias skip on a case-sensitive filesystem; result bundle `/tmp/PocketVector-Art-46c4b96-df690b8-full.xcresult` |
| 2026-07-20 | `df690b8` | Shared-header multi-device visual gate | Forty integrated captures passed compact/regular/iPad Accessibility 5 and regular/iPad standard inspection across Choose Offense, Team & Locker, Coin Store, Achievements, Settings, Tutorial Rules/Passing, and Results. Compact subtitles and full Results actions are readable and reachable. Accepted P3: iPad AX5 Results stat labels wrap awkwardly. Evidence directory `/tmp/PocketVector-Art-46c4b96-df690b8-attachments.KNLjzU` |
| 2026-07-20 | `a07950f` | Looping Passing-media Art integration | Art head `5dae317` merged with full ancestry; exact delta is Art-owned `TutorialView.swift` plus matching presentation tests; both independent audits accepted with no P0-P2 finding and diff hygiene passed |
| 2026-07-20 | `a07950f` | Passing-media focused and full simulator gates | Focused AppPresentation suite: 11 passed, 0 failed, 0 skipped at `/tmp/PocketVector-Art-5dae317-a07950f-focused.xcresult`; complete suite: 849 total, 848 passed, 0 failed, 1 existing conditional case-alias filesystem skip at `/tmp/PocketVector-Art-5dae317-a07950f-full.xcresult` |
| 2026-07-20 | `a07950f` | Passing-media runtime gate | Fresh disposable iPhone 17 Pro verified no media on Rules page one; page-two progress advanced and reset across multiple loop boundaries during an eight-second observation; with system Reduce Motion enabled, the static poster and first progress state remained visually unchanged for six seconds. No resource/configuration delta required an archive |
| 2026-07-20 | `00f703a` | Apple development signing and capability configuration | Automatic signing resolves team `RBMXD4NS89` for Debug and Release with bundle `com.pocketvector.game`; the app declares Game Center, APS, CloudKit, exact container `iCloud.com.pocketvector.game`, and Sports Games category. A signed Debug device build passed and its embedded entitlements matched the development profile. Final Apple Distribution identity, distribution profile, exported Release entitlements, and App Store upload remain pending external release gates |
| 2026-07-20 | `00f703a` | Exact Apple-configuration full simulator suite | 851 total: 850 passed, 0 failed, 1 existing conditional case-alias filesystem skip on iPhone 17 Pro; result bundle `/Users/andypark/Library/Developer/Xcode/DerivedData/PocketVector-gzonknuffecczwcjjrtxgwzvubqz/Logs/Test/Test-PocketVector-2026.07.20_22-30-26--0700.xcresult` |
| 2026-07-20 | `00f703a` | Unsigned generic-iOS Release archive | Passed at `/tmp/PocketVectorAppleConfigArchive.mtoxCn/PocketVector.xcarchive`; arm64, iPhone/iPad, iOS 17 minimum, bundle `com.pocketvector.game`, and `public.app-category.sports-games` metadata verified. This unsigned archive does not satisfy the final codesigned distribution-entitlement gate |
| 2026-07-20 | `4f45dde` | Technical live-play input and snapshot handoff integration | Technical commit `32d0f25` merged with full ancestry; all seven changed paths are Technical-owned gameplay, gameplay documentation, or matching tests. Merge preview, ownership review, independent audit, and diff hygiene passed without a source conflict or P0-P2 code finding |
| 2026-07-20 | `4f45dde` | Gameplay snapshot and throw-input focused gate | GameCore and GameplaySession suites passed 67 tests with 0 failures and 0 skips; result bundle `/Users/andypark/Library/Developer/Xcode/DerivedData/PocketVector-gzonknuffecczwcjjrtxgwzvubqz/Logs/Test/Test-PocketVector-2026.07.20_22-39-48--0700.xcresult` |
| 2026-07-20 | `4f45dde` | Exact integrated full simulator suite | Fresh iPhone 17 Pro simulator serial gate passed 854 total: 853 passed, 0 failed, 1 existing conditional case-alias filesystem skip; result bundle `/Users/andypark/Library/Developer/Xcode/DerivedData/PocketVector-gzonknuffecczwcjjrtxgwzvubqz/Logs/Test/Test-PocketVector-2026.07.20_22-56-26--0700.xcresult`. The runtime-only Technical wave changed no resource, capability, app-composition, or Release surface, so no additional archive was required |
| 2026-07-20 | `572d6a8` | Bottom-system-gesture adapter integration | Art commit `0571f6c` merged from exact shared baseline `48d76d8` without conflict. The owner explicitly routed consumption of Technical's `GameplaySceneSnapshot.defersBottomSystemGestures` to the Art-owned gameplay adapter; the two changed paths are the UI adapter and its matching presentation test, with no visual, resource, gameplay-rule, navigation, persistence, service, or release-configuration delta |
| 2026-07-20 | `572d6a8` | Gesture-deferral focused and full simulator gates | LaunchVisualIdentity focused suite passed 32 tests with 0 failures and 0 skips at `/Users/andypark/Library/Developer/Xcode/DerivedData/PocketVector-gzonknuffecczwcjjrtxgwzvubqz/Logs/Test/Test-PocketVector-2026.07.20_23-29-13--0700.xcresult`; complete serial suite passed 855 total: 854 passed, 0 failed, 1 existing conditional case-alias filesystem skip at `/Users/andypark/Library/Developer/Xcode/DerivedData/PocketVector-gzonknuffecczwcjjrtxgwzvubqz/Logs/Test/Test-PocketVector-2026.07.20_23-30-25--0700.xcresult`. No visual pixels or resources changed, so screenshots and a new archive were not applicable; physical-iPhone deliberate repeated-home-gesture behavior remains a manual device QA item |
| 2026-07-20 | `124fb1f` | Raised-quarterback Technical integration | Technical commit `3031125` merged with full ancestry from its older `32d0f25` parent under the owner's approved older-baseline integration path. Three Technical-owned gameplay-rendering and matching test paths changed; the shared visual-identity test file merged additively without conflict. The foreground quarterback baseline rises 60 logical units and the rendered football receives the same initial visual offset, easing back to the unchanged authoritative trajectory by 180 ms; collision, scoring, simulation state, and assets remain unchanged |
| 2026-07-20 | `124fb1f` | Quarterback alignment focused and full simulator gates | GameCore and LaunchVisualIdentity focused suites passed 86 tests with 0 failures and 0 skips at `/Users/andypark/Library/Developer/Xcode/DerivedData/PocketVector-gzonknuffecczwcjjrtxgwzvubqz/Logs/Test/Test-PocketVector-2026.07.20_23-38-22--0700.xcresult`; complete serial suite passed 858 total: 857 passed, 0 failed, 1 existing conditional case-alias filesystem skip at `/Users/andypark/Library/Developer/Xcode/DerivedData/PocketVector-gzonknuffecczwcjjrtxgwzvubqz/Logs/Test/Test-PocketVector-2026.07.20_23-40-14--0700.xcresult`. Runtime-only rendering changed no resource, capability, app-composition, or Release surface, so no additional archive was required |
| 2026-07-20 | `124fb1f` | Raised-quarterback live simulator review | Regular iPhone live gameplay and one successful throw passed inspection: foreground crop remains intentional, the ball begins at the throwing-hand area, and the captured 60 fps release shows no obvious early-flight discontinuity. Evidence: `/tmp/PocketVector-QBRaise-idle-124fb1f.png`, `/tmp/PocketVector-QBRaise-release-124fb1f.mov`, and `/tmp/PocketVector-QBRaise-release-contact-500ms-124fb1f.png`; compact, wide, and iPad centering/placement are additionally covered by deterministic viewport tests |
| 2026-07-21 | `91c77ee` | Versioned reward-breakdown Technical and PM integration | Technical head `d89e722` merged with full ancestry at `67d9a2b`; PM Results projection consumes the immutable versioned breakdown and validates its checked sum against durable settlement authority. Both independent audits found no P0-P2 issue, ownership and diff hygiene passed, and Art's retained-field overlay remains a separate visual handoff |
| 2026-07-21 | `91c77ee` | Results settlement focused integration gate | 78 passed, 0 failed, 0 skipped across economy, production composition/runtime, app coordinator, and gameplay coordinator suites; result bundle `/Users/andypark/Library/Developer/Xcode/DerivedData/PocketVector-gzonknuffecczwcjjrtxgwzvubqz/Logs/Test/Test-PocketVector-2026.07.21_00-46-44--0700.xcresult` |
| 2026-07-21 | `91c77ee` | Exact integrated full simulator suite | 864 total: 863 passed, 0 failed, 1 existing conditional case-alias filesystem skip; result bundle `/Users/andypark/Library/Developer/Xcode/DerivedData/PocketVector-gzonknuffecczwcjjrtxgwzvubqz/Logs/Test/Test-PocketVector-2026.07.21_00-47-38--0700.xcresult` |
| 2026-07-21 | `91c77ee` | Unsigned generic-iOS Release archive | Passed at `/tmp/PocketVector-ResultsTechnical-20260721.xcarchive`; App-composition integration compiles for generic arm64 iOS with signing disabled. Final codesigned distribution-entitlement proof remains pending |
| 2026-07-21 | `b047ce0` | Diverged Art/Release ancestry bridge | Merge parents are exactly release baseline `d96f0273b13749ca53bf774a113b864c1ef7dd50` and Art handoff `08ff44db3f7e28633a45cf7bb05267146d185d3d`; both are verified ancestors. The one shared-test conflict retained authoritative release fields, the Art ledger was adapted to consume them directly, and the misplaced root QA note was excluded. Independent audits found no P0; retained real-gameplay composition remains an explicit P1 follow-up before visual acceptance |
| 2026-07-21 | `b047ce0` | Results overlay focused integration gate | 56 passed, 0 failed, 0 skipped across Results presentation, app/gameplay coordinators, production composition, and the exact native asset-manifest test; result bundle `/Users/andypark/Library/Developer/Xcode/DerivedData/PocketVector-gzonknuffecczwcjjrtxgwzvubqz/Logs/Test/Test-PocketVector-2026.07.21_01-18-37--0700.xcresult` |
| 2026-07-21 | `b047ce0` | Exact integrated full simulator suite | 866 total: 865 passed, 0 failed, 1 existing conditional case-alias filesystem skip; result bundle `/Users/andypark/Library/Developer/Xcode/DerivedData/PocketVector-gzonknuffecczwcjjrtxgwzvubqz/Logs/Test/Test-PocketVector-2026.07.21_01-20-07--0700.xcresult` |
| 2026-07-21 | `b047ce0` | Art visual evidence and unsigned Release archive | Compact iPhone, regular iPhone, iPad, and Accessibility 5 evidence passed inspection; seven new asset-catalog JSON files parsed and compiled. Unsigned generic-iOS archive passed at `/tmp/PocketVector-ArtResultsBridge-20260721.xcarchive`; final retained-gameplay visual gate and codesigned distribution proof remain pending |
| 2026-07-21 | `3acbf4c` | Retained-gameplay Results Art integration | Art handoff `71ccd0e` merged with full ancestry; the exact gameplay adapter, `SKView`, and `GameScene` are retained and frozen beneath the transparent Results overlay, gameplay chrome/interaction/accessibility/gesture deferral are suppressed, and existing replay/menu coordinator behavior is preserved. The submitted root QA note was excluded as outside Art ownership. Independent review found no P0-P2 issue; the compact Accessibility 5 `OPTIONAL` wrap is an accepted P3 |
| 2026-07-21 | `3acbf4c` | Retained Results focused integration gate | 26 passed, 0 failed, 0 skipped across AppPresentation, coordinator, gameplay-HUD, production-composition, gesture-deferral, and exact native asset-manifest coverage; result bundle `/Users/andypark/Library/Developer/Xcode/DerivedData/PocketVector-gzonknuffecczwcjjrtxgwzvubqz/Logs/Test/Test-PocketVector-2026.07.21_02-41-39--0700.xcresult` |
| 2026-07-21 | `3acbf4c` | Exact integrated full simulator suite | 872 total: 871 passed, 0 failed, 1 existing conditional case-alias filesystem skip; result bundle `/Users/andypark/Library/Developer/Xcode/DerivedData/PocketVector-gzonknuffecczwcjjrtxgwzvubqz/Logs/Test/Test-PocketVector-2026.07.21_02-43-34--0700.xcresult` |
| 2026-07-21 | `3acbf4c` | Retained Results visual and archive gates | Compact iPhone, regular iPhone, and iPad standard and Accessibility 5 evidence passed PM inspection at `/tmp/pocket-vector-results-retained-final`; unsigned generic-iOS Release archive passed at `/tmp/PocketVector-RetainedResults-20260721.xcarchive`. Final codesigned distribution-entitlement proof remains pending |
| 2026-07-21 | `e1c0f9a` | Root-controller bottom-gesture correction | The window's actual `PocketVectorRootHostingController` now owns `preferredScreenEdgesDeferringSystemGestures`, invalidates UIKit's preference only on effective transitions, and requires active-app, active-gameplay, matching-run, live-snapshot authority. Countdown, pause, Results, settlement/error, frozen presentation, backgrounding, non-gameplay routes, and stale/replay runs fail closed. Existing scene-session installation is covered by a scene-notification fallback. Independent review found no P0-P2 code issue |
| 2026-07-21 | `e1c0f9a` | Root gesture focused and full simulator gates | Four focused root-controller, lifecycle-policy, and snapshot-policy tests passed at `/tmp/PocketVectorRootGestureFocused/Logs/Test/Test-PocketVector-2026.07.21_10-32-17--0700.xcresult`; complete serial suite passed 875 total: 874 passed, 0 failed, 1 existing conditional case-alias filesystem skip at `/tmp/PocketVectorRootGestureFull/Logs/Test/Test-PocketVector-2026.07.21_10-33-52--0700.xcresult` |
| 2026-07-21 | `e1c0f9a` | Root gesture launch and archive gates | An in-place upgrade over the existing simulator installation cold-launched successfully through the custom root controller without deleting app data. Unsigned generic-iOS Release archive passed at `/tmp/PocketVector-RootGesture-20260721.xcarchive`. Physical Face ID iPhone one-swipe protection and second-deliberate-swipe exit remain pending because device `Snow J` was unavailable |
| 2026-07-21 | `d7d3eeb` | Physical Face ID root-gesture acceptance | On `Snow J` (iPhone 17 Pro Max, iOS 26.5.2), the final UIKit-root arrangement kept active gameplay open after the first upward Home swipe and allowed the immediate second deliberate swipe to exit. The SwiftUI/SpriteKit hierarchy and existing `GameScene` remained retained; no gameplay input, scoring, or simulation code changed |
| 2026-07-21 | `d7d3eeb` | Final root-container simulator gates | Final containment/system-UI focused regression passed 1 of 1; complete suite passed 875 total: 874 passed, 0 failed, 1 existing conditional case-alias filesystem skip at `/Users/andypark/Library/Developer/Xcode/DerivedData/PocketVector-gzonknuffecczwcjjrtxgwzvubqz/Logs/Test/Test-PocketVector-2026.07.21_11-09-53--0700.xcresult`. Independent review's one P2 forwarding finding was fixed before acceptance, leaving no P0-P3 finding |
| 2026-07-21 | `d7d3eeb` | Final root-container unsigned Release archive | Passed at `/tmp/PocketVector-RootGestureContainer-20260721.xcarchive`; generic arm64 iOS Release compiled with signing disabled. Final codesigned distribution-entitlement proof remains pending |
| 2026-07-21 | `e1f4d94` | Technical cinematic framing integration | Technical commit `e1f4d943600c369146f935f16ef9550814359ada` fast-forwarded from exact shared baseline `d57714e`; all six production/documentation paths are Technical-owned and the two shared tests correspond to those paths. Ancestry, ownership, clean-worktree, diff-hygiene, and two independent audits passed with no P0-P3 finding |
| 2026-07-21 | `e1f4d94` | Cinematic focused and full simulator gates | GameCore and GameplaySession focus passed 73 tests with 0 failures; exact integrated suite passed 879 total: 878 passed, 0 failed, 1 existing conditional case-alias filesystem skip at `/tmp/PocketVector-Cinematic-e1f4d94-full.xcresult`. This runtime-only Technical wave changed no resource, capability, app-composition, or Release configuration path, so no additional archive was required |
| 2026-07-21 | `e1f4d94` | Cinematic multi-device PM visual gate | Compact-iPhone, regular-iPhone, and iPad active gameplay frames passed inspection; regular-iPhone standard countdown captures at `2` and `1` showed progressive bars, and the retained Results capture showed the bars removed. Evidence: `/tmp/PocketVector-Cinematic-e1f4d94-compact-active-landscape.png`, `/tmp/PocketVector-Cinematic-e1f4d94-regular-active-landscape.png`, `/tmp/PocketVector-Cinematic-e1f4d94-ipad-active-landscape.png`, `/tmp/PocketVector-Cinematic-e1f4d94-regular-countdown-2.png`, `/tmp/PocketVector-Cinematic-e1f4d94-regular-countdown-1.png`, and `/tmp/PocketVector-Cinematic-e1f4d94-regular-results.png`; final Art sequence approval remains pending |
| 2026-07-21 | `9a86c76` | Visual-only cinematic input integration | Technical commits `52d7b0a` and `28dcf8f` are merged with full ancestry. The cinematic bars no longer remove any gameplay input area, countdown input remains inert until live play, and countdown audio/visual cues remain synchronized. The PM countdown expectation is retained at `51a4278`; no art asset, scoring, collision, or simulation rule changed |
| 2026-07-21 | `6e20347` | App-wide root gesture lock and build 156 | The PM-owned plain window root always defers `.bottom`, owns status-bar presentation, keeps Home-indicator auto-hide disabled, and uses a noncancelling, nondelaying one-touch pan recognizer with simultaneous recognition. Build metadata is pinned to 156 for Debug and Release. The root-containment regression covers Main Menu, countdown, Playing, final-ball resolution, Pause, frozen Results, settlement, and inactive-scene state. All changed paths are PM-owned app, release configuration, or cross-domain regression coverage |
| 2026-07-21 | `6e20347` | Final build 156 focused and simulator gates | The final root-controller focus passed 1 of 1 at `/tmp/PocketVector-global-deferral-focused-156-final.xcresult`; the exact full iPhone 17 Pro simulator suite passed 880 total: 879 passed, 0 failed, 1 existing conditional case-alias filesystem skip at `/tmp/PocketVector-global-deferral-suite-156-final.xcresult`; diff hygiene passed |
| 2026-07-21 | `6e20347` | Final build 156 physical and archive acceptance | On `Snow J` (iPhone 17 Pro Max, iOS 26.5.2), Main Menu required a second deliberate swipe to exit, countdown stayed after its first swipe, and active gameplay stayed while also throwing the pass. The owner accepted build 156 and normal Home-indicator/UI interaction behavior. The exact signed Debug build was installed; unsigned generic arm64 iOS Release archive passed at `/tmp/PocketVector-global-deferral-156-final.xcarchive` with `CFBundleVersion` 156. Independent final review found no remaining P0-P3 issue; final codesigned distribution-entitlement proof remains pending |
| 2026-07-21 | `c158148` | Post-pass gameplay Technical integration | Technical commit `c158148a49fa3b1ea04bb8f7ed4488eefd216b20` fast-forwarded from exact shared baseline `7773486`; all changed paths are Technical-owned gameplay/documentation or matching shared tests. Independent review found no P0-P3 issue; GameCore focus passed 59 tests with 0 failures and 0 skips at `/tmp/PocketVector-c158148-review.xcresult`; diff hygiene passed |
| 2026-07-21 | `efd28d3` | Exact build 157 complete simulator suite | The fresh iPhone 17 Pro acceptance run passed 883 total: 882 passed, 0 failed, and 1 existing conditional case-alias filesystem skip at `/tmp/PocketVector-c158148-build157-full-rerun.xcresult`. The first run's unrelated tutorial media teardown crash was isolated; `testCaptureTutorialAndResultsLayoutMatrix` then passed alone at `/tmp/PocketVector-c158148-build157-layout-rerun.xcresult` and passed again in the complete acceptance run |
| 2026-07-21 | `efd28d3` | Build 157 unsigned Release archive | Generic arm64 iOS Release archive passed with signing disabled at `/tmp/PocketVector-c158148-build157.xcarchive`; `CFBundleShortVersionString` is 1.0 and `CFBundleVersion` is 157. Final codesigned distribution-entitlement proof remains pending |
| 2026-07-21 | build 158 | Publication hardening focused and complete simulator gates | Privacy/entitlement focused suite passed 19 tests; exact iPhone 17 Pro suite passed 885 total: 884 passed, 0 failed, and 1 established conditional filesystem skip at `/tmp/PocketVector-build158-full.xcresult` |
| 2026-07-21 | build 158 | Release analysis and unsigned archive | Shipping app target passed arm64 Release analysis with no product diagnostic. Generic arm64 iOS Release archive passed with signing disabled at `/tmp/PocketVector-build158-hardened.xcarchive`; version 1.0 (158), required-reason privacy manifest, platform restrictions, and clean payload verified |
| 2026-07-21 | build 158 | App Store Connect distribution export | `/tmp/PocketVector-build158-app-store-export/PocketVector.ipa` exported through the tracked options using Cloud Managed Apple Distribution. Signature verification passed; final entitlements are `RBMXD4NS89.com.pocketvector.game`, `get-task-allow = false`, Production `iCloud.com.pocketvector.game`, Game Center, and no APS. Live services, App Store metadata, upload/processing, and TestFlight remain pending |

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
7. **Complete internal composition; external Cloud configuration pending:** the
   automatic first-association claim, same-account offline reopening, account-
   switch isolation, outbound initial publication, checkpoint refresh, and
   crash-safe hydration are composed in the account-scoped runtime while
   preserving generation, checkpoint, journal, lineage, and final durability
   rechecks.
8. **Complete Game Center foundation; live integration pending:** V4 persistence,
   exact player buckets, unbound quarantine, and capability-bound single-flight
   delivery are implemented. Add the trusted Release factory, retained
   authentication/foreground/presentation composition, App Store Connect
   records, a proof-bearing settlement attribution path, and the approved
   durable exactly-once claim of unbound maxima to the first authenticated
   player. A later player may never claim the same values.
9. **Complete internal StoreKit composition; external products pending:** localized product
   validation, verified updates, unfinished recovery, durable finish gating,
   account-generation retirement, and serialized purchases are implemented.
   Live account-session sourcing, private-cloud economy composition, retained
   lifecycle, transaction-boundary revalidation, and bounded presentation state
   are implemented. Permanent consumable identifiers and App Store product
   records remain external release work.
10. **Complete rewarded-ad verification foundation; live integration pending:**
   exact challenge/status correlation, process-only verified claims, and
   crash-recoverable challenge journaling are implemented. Add authenticated
   production transport and replay-stable SSV backend with provider-transaction
   deduplication, provider SDK and consent adapters, retained orchestration, and
   authoritative presentation state. A client callback alone never grants
   coins.

The Cloud claim/hydration and online-only StoreKit paths are now internally
composed. The remaining service critical path is permanent CloudKit and App
Store configuration plus signed-device validation, retained Game Center
delivery, and rewarded-ad production transport/SDK/consent integration.

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
5. **Owner-approved app-wide exit policy:** the window root defers the bottom
   system gesture on every app surface. The first bottom-edge swipe remains
   available to gameplay/UI input but cannot leave the app; a second deliberate
   swipe exits. Keep Home-indicator auto-hide disabled and do not restore
   scene-state blockers or child Home-indicator forwarding without a new
   physical Face ID regression pass.
6. Permanent bundle identifier, iCloud container, privacy URL, and support URL.
   Domain and email setup are tracked in the separate user-owned Codex task.
7. Verified rewarded-ad infrastructure. The dormant correlation client,
   process-only verified claim, and challenge-only recovery journal are
   complete, but an authenticated production transport and replay-stable
   server-side-verification endpoint, provider-transaction deduplication, the ad
   SDK, consent orchestration, and retained runtime integration remain. AdMob
   client callbacks alone never grant coins.
8. **Owner-approved Apple-only diagnostics:** use OSLog, Apple crash reports,
   and MetricKit without a third-party crash SDK. The release gate is zero known
   reproducible gameplay crashes, no recurring multi-tester crash signature,
   and completed Apple diagnostics review rather than an exact percentage.
9. Final audience-policy declarations for AdMob and App Store privacy. The
   product remains general audience and outside Apple's Kids Category; the
   shipping SDK configuration and disclosures still require final review.
10. Apple Developer enrollment, Paid Apps agreement, tax and banking, live
   consumable products, Game Center records, AdMob app/ad unit, UMP message,
   `app-ads.txt`, and production CloudKit schema deployment.
11. Final codesigned-entitlement verification. After the permanent iCloud
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
| Known P0/P1 defects                  |      0 | 0 open in integrated code and automated gates; build 156 app-wide root policy passed physical Face ID one-swipe/two-swipe acceptance with no remaining P0-P3 finding |
| TestFlight sessions                  |   200+ | Not started                                     |
| Valid completed runs                 |   100+ | Not started                                     |
| Apple gameplay-crash review          |   Pass | Not started                                     |
| Results-to-replay rate               |   30%+ | Event contract planned                          |
| Exactly-once economic mutations      |   100% | Local/cloud history, initial publication, hydration, online-only catalog debit/ownership, and StoreKit durable delivery pass internal tests; external sandbox/device gates remain |
| Clean-checkout archive               |   Pass | Unsigned generic-iOS build 157 archive containing Technical handoff `c158148` passed; final codesigned entitlement/export proof remains |
| Browser runtime in active repository |   None | Browser runtime, dependencies, tests, and build configuration removed at `24cd2c7` |

The release is ready only when the entire scoreboard is satisfied, the owner
approves representative iPhone and iPad visuals, and App Store review materials
are complete.
