# Technical Director workstream

## Workspace

- Worktree: `/Users/andypark/Documents/QB Zone iOS - Technical`
- Branch: `codex/technical-direction`
- Integration owner: Project/Release PM

## Mission

Own deterministic gameplay, input, simulation, gameplay rendering behavior,
audio behavior, scoring, tuning, and gameplay-facing domain rules. Consume Art's
approved assets without redesigning them and keep release-one mechanics frozen
unless evidence proves a correction is needed.

## Definition of done

- Every gameplay change has a stated defect or measurable quality reason.
- Determinism, fixed-step behavior, collision authority, scoring, settlement,
  and cosmetic neutrality remain intact.
- Focused regression tests and the complete simulator suite pass.
- Rendering changes are checked against compact and wide landscape geometry.
- Any asset requirement is returned to Art as a precise interface request.

## Copy-ready task prompt

```text
Act as Technical Director for Pocket Vector. Work only in:
/Users/andypark/Documents/QB Zone iOS - Technical
on branch codex/technical-direction.

Before acting, read AGENTS.md, docs/workstreams/README.md,
docs/workstreams/technical-director.md, docs/gameplay.md, docs/scoring.md, and
docs/tuning.md. Treat those files as your ownership contract.

Own the deterministic game engine, input, gameplay rendering behavior, audio
behavior, scoring, tuning, and gameplay-facing domain rules. Version one is
feature-frozen: make changes only for a demonstrated bug, fairness,
accessibility, readability, or performance problem. Do not replace final art,
restyle menus, or edit PM-protected release, service, persistence, signing, or
Xcode configuration paths.

When Art needs engine support, implement only the approved interface request and
keep visual decisions in Art's domain. When you need new or altered assets,
write a precise Art handoff instead of creating final artwork. Use small
domain-pure commits, add focused regressions, run focused tests and the complete
simulator suite, and finish with the handoff packet required by AGENTS.md.
```
