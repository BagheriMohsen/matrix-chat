# Repository Guidelines

## Project Structure & Module Organization

This repository is currently a project skeleton. Keep application code in a
top-level `src/` directory, tests in `tests/`, and static or fixture data in
`assets/` or `tests/fixtures/`. Keep generated output (for example, `dist/`,
coverage reports, and local caches) out of version control. Add a short
`README.md` when the application entry point and setup requirements are known.

Organize code by feature or domain rather than by generic technical layer when
the project grows. For example: `src/rooms/`, `src/messages/`, and
`src/auth/`. Put shared utilities in `src/shared/` only when they are genuinely
used across features.

## Build, Test, and Development Commands

No runtime, package manager, or build system is configured yet. When adding
one, expose the standard workflow through documented, repeatable commands:

- `npm run dev` — run the application locally with development settings.
- `npm test` — execute the complete automated test suite.
- `npm run lint` and `npm run format` — check and apply code style.
- `npm run build` — produce a deployable build.

Update this section and `README.md` with the actual commands as tooling is
introduced. Do not require undeclared global dependencies.

## Coding Style & Naming Conventions

Use the formatter and linter provided by the chosen language ecosystem; commit
formatted code. Prefer two spaces for JSON, YAML, Markdown, and web code unless
the selected formatter dictates otherwise. Use descriptive names: `roomId`,
`sendMessage`, and `message-service.ts`, rather than abbreviations. Keep files
small, avoid duplicated logic, and keep configuration free of secrets.

## Testing Guidelines

Place tests alongside a feature or under `tests/`, using names such as
`messages.test.ts` or `test_messages.py` appropriate to the adopted framework.
Cover normal behavior, invalid input, and failure paths. Run the full test and
lint commands before opening a pull request; add regression tests for fixes.

## Commit & Pull Request Guidelines

There is no commit history yet. Use concise, imperative commit subjects, such
as `Add message validation` or `Fix room membership check`. Keep commits focused.
Pull requests should explain the change, list verification performed, link the
relevant issue when available, and include screenshots for visible UI changes.
