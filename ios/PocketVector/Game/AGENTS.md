# Gameplay-engine ownership

This subtree belongs to the Technical Director workstream.

- Preserve deterministic 60 Hz simulation and frame-partition independence.
- Version-one gameplay is feature-frozen. Change behavior only for a measured
  bug, fairness, accessibility, readability, or performance problem.
- Cosmetics and team presentation must never change collision, speed, score,
  reward, opponent selection, or other gameplay authority.
- Do not replace final art assets. If the engine needs different dimensions,
  anchors, frames, names, or variants, send a precise request to Art.
- Add a deterministic regression test before fixing a gameplay defect whenever
  feasible, then run the focused and complete simulator suites.
- Do not edit app composition, services, persistence, Xcode configuration, or
  release documents from this workstream.
