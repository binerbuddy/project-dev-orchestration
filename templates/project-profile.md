# Project profile: <project name>

<!--
Copy this file to `.agents/project-profile.md` in the product repo and commit it on the default branch.
The lifecycle skills (project-small-feature-or-bug-fix, project-feature-design, project-feature-build, and the others
in project-dev-orchestration) read it and cite its sections by name as "§<Section>", so keep the `##` headings exactly
as they are. Replace each paragraph of guidance with your project's facts; delete the commented example once done.
Keep it factual and short: commands, paths, ports, names. Anything an agent could get wrong without being told.
LF line endings only.
-->

## Identity

Who the project is on GitHub and where its work is tracked. Give the org, the primary repo (the one bare `#n` refs
mean), every related repo agents may need to search or file against and when each one is in scope, and the org
Project board the issues live on: its number, its node id, its Status field id, and the option ids of each Status
column (Backlog, Todo, the orchestrator's queue column, In Progress, In Review, Done). Say whether the repo supports
GitHub issue types (personal repos don't, and the API silently drops `type`; name the type labels used instead), and
name any legacy tracker that still holds older closed work (read-only).

<!-- Example (Acme):
- Org: `acme-co`. Primary repo: `acme-co/acme-app` (bare `#n` = this repo).
- Related: `acme-co/acme-engine` (the pricing engine; search and file there when a change touches pricing rules).
- Board: org Project #3 "Acme Roadmap", node id `PVT_xxxxxxxxxxxxxxxx`, Status field `PVTSSF_xxxxxxxxxxxxxxxx`.
  Options: Backlog `aaaa1111`, Todo `bbbb2222`, Agent Queue `cccc3333`, In Progress `dddd4444`, In Review `eeee5555`,
  Done `ffff6666`.
- Issue types: org types Epic / Feature / Bug / Task.
- Legacy tracker: closed work before 2025-01-01 is in the old tracker (read-only); new issues go to GitHub only.
-->

## Layout

How checkouts are arranged on disk, so agents create worktrees in the right place with the right names. Say whether
the repo is a bare-root clone with one worktree per branch (and where the bare root lives), how worktree directories
are named (kebab-case, camelCase, a `-design` suffix for design worktrees), the base branch PRs target, and the
branch prefixes in use.

<!-- Example (Acme):
- Bare root: `~/src/acme-app.git` (bare clone, `remote.origin.fetch` set). One worktree per branch inside it.
- Worktree dirs: camelCase of the slug (`userPreferences`); design worktrees add `Design` (`userPreferencesDesign`).
- Base branch: `main`. Branch prefixes: `feat/`, `fix/`, `docs/<slug>-design`, `feat/<epic#>-<slug>` for epic builds.
-->

## Build & checks

The authoritative compile/typecheck/lint commands an agent must pass before handing off code, per part of the repo,
with the directory each runs in. List the errors those commands report on a clean base branch (known noise) so agents
ignore them rather than "fix" them, and any env vars a build needs.

<!-- Example (Acme):
- Web client (`web/`): `npm run typecheck`. Known noise: errors in `*.spec.ts` and `e2e/` (stale test files).
- Server (`server/`): `npm run build:server`.
- Never run `npm run build:prod` locally (it needs release signing keys).
-->

## Tests

What test infrastructure exists and how far agents should rely on it. Say which suites work and how to run them, or
that there is no working test infrastructure (then plans include no test work and verification is compile checks plus
headless QC). Name the headless browser driver used for automated QC and smoke runs, if any.

<!-- Example (Acme):
- Unit tests: `npm test` in `server/` works and is fast; run it for server changes.
- Web client unit tests are broken (no working runner); plan no web test work.
- Headless QC: `scripts/cdp-driver.mjs` (raw Chrome DevTools Protocol, no Playwright install needed).
-->

## Dev servers

How to run the app locally for agent QC: the start commands, the env vars and secrets they need, the dev login or
auth bypass, and the database rules (shared or per-agent, what must never be stopped or dropped, how migrations are
handled). Give the ports reserved for the human (agents never bind or kill them) and the port scheme agents use
instead, plus any CORS or API-URL wiring that changing ports requires.

<!-- Example (Acme):
- API: `npm run dev:api` (needs `ACME_DB_URL`; dev auth: `ACME_AUTH=none`, then log in as `demo`).
- Web: `npm run dev:web -- --port <port>`; point it at your API with `ACME_API_URL`.
- Reserved for the human: 3000 and 8080. Agents: web on `4300 + (issue# % 100)`, API on `5300 + (issue# % 100)`.
- DB: shared local Postgres container `acme-db`. Never stop it. Snapshot before running migrations; restore after.
-->

## QC data

What human QC runs against, and how to give it data. Describe the seed data (users, sample projects) and what the
top-level record is called in the UI (checklists name data by it, never by URL or id). Give the fixture format and
file extension, how to export a fixture from the running app, how the human imports it, and any size limit. Fixtures
are published with the engine's `pdo qc-fixture-push <PR#> <file>` to the never-merged `qc-fixtures` branch, never
committed to a PR branch.

<!-- Example (Acme):
- Seed: two users (`demo`, `admin`) and one project, *Acme Demo*.
- Top-level record: "project" (Projects → <name>).
- Fixture format: `.acme-export` (Projects → ⋯ → Export). Import: Projects → Import. Keep under 5 MB.
- Publish: `pdo qc-fixture-push <PR#> <file>.acme-export`.
-->

## QC preview

The optional remote preview service that builds a PR for browser QC without a local setup. Give the PR comment
triggers that start and stop a preview, the preview link pattern, the login to use, roughly how long a build takes,
and the idle timeout. These fill the QC commands block at the end of every QC checklist. If there is no preview
service, say "None"; the checklist then keeps only the `QC:` and `Claude, QC pass` rows.

<!-- Example (Acme):
- Start: `Claude, spin up QC` (about 5 min). Stop: `Claude, tear down`. Idle previews stop after 4 h.
- Link pattern: `https://pr-<n>.preview.example.com`.
- Login: dev auth, as **demo**.
-->

## Changelog

How every PR records its change for release notes: changesets, a CHANGELOG file, PR labels, or nothing. Give the exact
file location and format, with an example entry, and any format traps (characters that break the release build,
retired styles not to copy).

<!-- Example (Acme):
- Changesets: one file per PR in `.changeset/<slug>.md`:
  ```
  ---
  type: minor
  ---
  Feature: Users can pin a project to the top of the list.
  ```
  One `Feature:` / `Fix:` line per user-visible change. Don't use braces `{ }` in entries (the release-notes page
  is a template and they break its build).
-->

## Review roles

Extra reviewer roles for this project, on top of the base Architect, Security, Code Review and Adversary roles. Give
each a name, when it joins (every plan, only UI changes, only migrations), and its role prompt. A UI role defined here
replaces the generic UI / UX reviewer.

<!-- Example (Acme):
- **UI Designer** (any change with UI): "You are a UI/UX designer specializing in React and the Acme design system.
  Focus on: component layout and composition, design-system guidelines, responsive design, theming and typography,
  accessibility (a11y), and user interaction flow. Recommend specific design-system components. Provide concrete
  markup/styles when relevant. Do not review backend logic or business rules."
- **Data reviewer** (schema changes): checks migrations are reversible and safe on large tables.
-->

## Docs

Where documentation lives: the design-doc directory used by `/project-feature-design` and `/project-feature-build`
(and their `.progress.md` ledgers), the user guide and how it is built, and any other docs agents should update when
behaviour changes.

<!-- Example (Acme):
- Design docs: `docs/design/<slug>.md`; ledgers alongside as `docs/design/<slug>.progress.md`.
- User guide: separate repo `acme-co/acme-docs`, `guide/`; update it for user-visible changes only when asked.
-->

## Conventions

The code conventions a reviewer would flag: patterns to match and the reason behind each. Transaction ownership,
DTO and mapping style, route shapes, UI component and dialog patterns, state management, naming. Point to the files
that show each pattern best.

<!-- Example (Acme):
- Services own transactions; controllers never open one (`server/src/orders/order.service.ts`).
- Write endpoints are `POST /<resource>/update`, never PUT/PATCH.
- Mapping profiles are registered explicitly in `server/src/mapping/index.ts`; no auto-discovery.
- Dialogs use the shared `ConfirmDialog` (`web/src/shared/confirm-dialog.tsx`).
-->

## Do not

Hard prohibitions: things agents must never do in this repo or its environment, each with a one-line reason.

<!-- Example (Acme):
- Never stop or recreate the `acme-db` container (other sessions share it).
- Never commit fixtures or QC data to a PR branch (they merge into main).
- Never merge to `main`; the human merges.
- Never edit generated files under `web/src/generated/`; regenerate with `npm run codegen`.
-->
