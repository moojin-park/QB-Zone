# Art Director workstream

## Workspace

- Worktree: `/Users/andypark/Documents/QB Zone iOS - Art`
- Branch: `codex/art-direction`
- Integration owner: Project/Release PM

## Mission

Own Pocket Vector's visual quality and asset library without changing gameplay
authority or release configuration. Review the complete landscape experience,
produce final assets, maintain visual consistency, and give Technical precise
requests when rendering behavior must change.

## Definition of done

- All menus, tutorial, gameplay, results, locker, store, achievements, settings,
  and privacy/support surfaces have been reviewed on iPhone and iPad.
- Team, uniform, football, character, field, icon, HUD, typography, and color
  direction are internally consistent and legally distinct from real teams.
- Shipping assets contain no drafts or unused files and match
  `native-assets.json` exactly.
- Compact and wide safe areas, contrast, readability, Dynamic Type, reduced
  motion, and VoiceOver presentation have been checked.
- A build passes and representative before/after screenshots accompany the
  handoff.

## Copy-ready task prompt

```text
Act as Art Director for Pocket Vector. Work only in:
/Users/andypark/Documents/QB Zone iOS - Art
on branch codex/art-direction.

Before acting, read AGENTS.md, docs/workstreams/README.md,
docs/workstreams/art-director.md, docs/pixel-art-direction.md, and
docs/asset-generation.md. Treat those files as your ownership contract.

Own the visual audit and approved visual changes across source art, shipping
assets, presentation tokens, and UI appearance. Preserve gameplay, navigation,
persistence, service behavior, economy, identifiers, and release configuration.
Do not edit protected or Technical/PM-owned paths. When a visual result needs an
engine or behavior change, write a precise Technical handoff describing asset
names, dimensions, frames, anchors, timing, and expected result instead of
editing gameplay code.

Work in small domain-pure commits. Validate the resource manifest, build the
app, and capture representative landscape screenshots for compact iPhone,
regular iPhone, and iPad. Finish with the handoff packet required by AGENTS.md,
including baseline, commits, changed files, verification, screenshots,
cross-domain requests, and confirmation that no protected path changed.
```
