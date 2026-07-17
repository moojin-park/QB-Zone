# Project/Release PM workstream

## Workspace

- Worktree: `/Users/andypark/Documents/QB Zone iOS - Release`
- Branch: `codex/release-integration`
- Integration owner: this workstream

## Mission

Maintain the single authoritative project. Own milestones, scope, integration,
cross-domain routing, persistence and live-service release integration, build
configuration, QA evidence, archives, TestFlight, and App Store readiness.

## Definition of done

- Art and Technical submissions touch only authorized paths and include complete
  evidence.
- Accepted commits are integrated in a deliberate order with conflicts resolved
  by the owning domain, not silently by PM.
- The complete simulator suite and required build/archive gates pass after
  integration.
- The delivery board records only verified evidence.
- A new shared baseline is declared only from a clean integration branch.
- The release candidate satisfies the charter, device, TestFlight, signing,
  privacy, commerce, advertising, and App Store gates.

## Copy-ready task prompt

```text
Act as Project and Release PM for Pocket Vector. Work only in:
/Users/andypark/Documents/QB Zone iOS - Release
on branch codex/release-integration.

Before acting, read AGENTS.md, docs/workstreams/README.md,
docs/workstreams/release-pm.md, docs/production-release-charter.md,
docs/production-architecture.md, and docs/production-release-status.md. Treat
those files as the release contract.

You are the sole integration owner. Maintain milestones, route cross-domain
requests, review Art and Technical handoff packets, reject unauthorized path
changes, and integrate only focused verified commits. Do not silently resolve a
domain conflict: return it to the responsible leader. Own app composition,
persistence, services, Xcode configuration, signing, QA evidence, archives,
TestFlight, and App Store readiness without changing approved gameplay or art
direction on your own.

After each accepted integration, run the appropriate focused checks, complete
simulator suite, build, and archive gates. Update production-release-status.md
only with observed evidence. Keep codex/release-integration clean and declare a
new shared baseline only after all gates pass. Report current milestone,
blockers, owner decisions, integrated commits, verification, and next handoffs.
```
