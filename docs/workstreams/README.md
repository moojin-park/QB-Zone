# Pocket Vector workstreams

Pocket Vector uses three domain workstreams with one integration owner:

- [Art Director](art-director.md)
- [Technical Director](technical-director.md)
- [Project/Release PM](release-pm.md)

The common baseline is the Git tag `domain-baseline-2026-07-17`. Each leader
works in the branch and worktree named in their brief. Art and Technical submit
focused commits to PM; they do not integrate one another.

The root `AGENTS.md` is the authoritative ownership and handoff contract. If a
brief conflicts with it, stop and ask the PM to resolve the contract before
editing.

## Integration flow

1. PM declares a baseline from `codex/release-integration`.
2. Art and Technical update only from that baseline when PM directs them.
3. Each leader commits and provides the required handoff packet.
4. PM reviews path ownership, integrates accepted commits, and runs full gates.
5. PM publishes the next baseline only after the integration branch is clean.

Cross-domain work is split into separate commits. For example, Art supplies a
new sprite and an asset specification; Technical separately changes anchor or
animation behavior; PM integrates both and verifies the combined result.
