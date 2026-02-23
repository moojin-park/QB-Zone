## Setup

- Install: `npm install`

## Dev

- Run dev server: `npm run dev`

## Testing

- Run tests: `npm test`

## Build

- Production build: `npm run build`

## Linting / Formatting

- Lint: `npm run lint`
- Format: `npm run format`

## Code Style

- TypeScript with `strict: true`
- Prefer small modules, explicit types, and no `any`
- Game architecture: pure state update functions (no DOM/canvas in logic), rendering in separate module
- Keep constants/config centralized

## PR & Commit Conventions

- PR title: `[type] Short summary` where `type` is one of `feat|fix|chore|refactor|test|docs`
- Include in PR description: summary, rationale, testing commands + results, screenshots/GIF if UI changed
- Keep commits small, scoped, and descriptive

## Safety

- Ask before destructive operations (deleting/renaming major files, large refactors)
