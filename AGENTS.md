# Pocket Vector collaboration contract

This repository is developed through three bounded workstreams. Every Codex
task must read this file and its workstream brief before changing files.

## Integration model

- `codex/release-integration` is the only branch that represents the combined
  release candidate.
- Art and Technical work in separate Git worktrees and submit focused commits
  to the Project/Release PM.
- Art and Technical never merge or cherry-pick each other's branches directly.
- Only the Project/Release PM integrates accepted commits and declares a new
  shared baseline.
- Never work around another task's uncommitted changes. Stop and report the
  overlap instead.
- Keep commits domain-pure. Do not combine art, gameplay, and release changes
  in one commit.

## Path ownership

### Art Director

Primary ownership:

- `ios/AssetSources/**`
- `ios/Tools/**`
- `ios/PocketVector/Resources/Assets.xcassets/**`
- `ios/PocketVector/Resources/GameAssets/**`
- `ios/PocketVector/Presentation/**`
- `ios/PocketVector/UI/**`
- `docs/asset-generation.md`
- `docs/pixel-art-direction.md`

Art owns final visual assets, visual tokens, UI appearance, layout, and visual
accessibility. Art does not change navigation behavior, gameplay rules,
collision, scoring, economy, persistence, services, or release configuration.

### Technical Director

Primary ownership:

- `ios/PocketVector/Achievements/**`
- `ios/PocketVector/Catalog/**`
- `ios/PocketVector/Domain/**`
- `ios/PocketVector/Economy/**`
- `ios/PocketVector/Game/**`
- `docs/gameplay.md`
- `docs/scoring.md`
- `docs/tuning.md`

Technical owns deterministic simulation, input, gameplay rendering behavior,
audio behavior, scoring, tuning, gameplay-facing domain rules, and their tests.
Technical consumes approved art but does not redesign or replace final assets.

### Project/Release PM

Primary ownership:

- `ios/PocketVector/App/**`
- `ios/PocketVector/Persistence/**`
- `ios/PocketVector/Services/**`
- `ios/PocketVector.xcodeproj/**`
- `ios/PocketVector/Info.plist`
- `ios/PocketVector/PocketVector.entitlements`
- `ios/PocketVector/Resources/PrivacyInfo.xcprivacy`
- `docs/production-architecture.md`
- `docs/production-release-charter.md`
- `docs/production-release-status.md`
- root and iOS README files
- repository configuration and release metadata

PM is the sole integration owner and owns milestones, release-service
composition, build settings, signing, QA evidence, archives, TestFlight, and
App Store readiness.

## Shared and protected surfaces

- `ios/PocketVectorTests/**` is shared only for tests corresponding to a
  workstream's owned production files. PM owns cross-domain and release tests.
- `ios/PocketVector/Resources/GameAssets/native-assets.json` is Art-owned for
  inventory contents. Any schema or runtime-loading contract change requires a
  Technical handoff and PM approval.
- `ios/PocketVector.xcodeproj/project.pbxproj`, app composition, entitlements,
  Info.plist, privacy manifest, and production release documents are PM-only.
- A task that needs a protected or foreign-domain change writes a handoff
  request; it does not make the change itself.

## Required handoff packet

Every submitted change must report:

1. Baseline commit.
2. Submitted commit hashes.
3. Files changed and why.
4. Verification performed and its result.
5. Screenshots for visual changes.
6. Cross-domain requests or known limitations.
7. Confirmation that no protected foreign-domain path was changed.

## Verification

- Run focused tests for every behavioral change.
- Technical changes require the complete simulator suite before handoff.
- Art changes require resource-manifest validation, a build, and representative
  compact-iPhone, regular-iPhone, and iPad landscape screenshots.
- PM runs the full simulator suite after integration.
- Resource, capability, app-composition, or Release changes require an unsigned
  generic-iOS archive before the integration milestone is accepted.
- Only PM records release evidence in `docs/production-release-status.md`.

Use the commands documented in the root `README.md`. If its named simulator is
not installed, select an installed iOS simulator without changing project
configuration.
