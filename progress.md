Original prompt: You are working in a local git repository. Build a small-scope MVP web game (American Football QB swipe-pass) using Vite + TypeScript + Canvas 2D with pure game-state logic separated from rendering, and unit tests for core logic.

- Initialized manual Vite-style project files due offline npm registry access.
- Added AGENTS.md with required setup/dev/test/build/lint/format and style/conventions.
- Next: implement pure physics/scoring/state logic and tests, then render/input loop.
- Implemented pure modules: config/types/physics/scoring/state/logic.
- Added unit tests for scoring meter rules and segment-circle intersection.
- Implemented canvas rendering with pseudo-perspective trapezoid field + depth lanes.
- Implemented pointer input controller with depth snapping and world-x mapping.
- Added deterministic hooks: window.advanceTime(ms) and window.render_game_to_text().
- Verification attempts:
  - npm install failed (ENOTFOUND registry.npmjs.org).
  - npm test/build/lint/format could not execute due missing installed tools.
  - Playwright client run failed because package `playwright` is not installed.
- TODO for next agent:
  - Restore network/npm registry access.
  - Run npm install, then npm test, npm run lint, npm run format, npm run build.
  - Run develop-web-game Playwright client loop and inspect screenshots.
