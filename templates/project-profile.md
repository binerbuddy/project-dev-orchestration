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
column (Backlog, Todo, the orchestrator's queue column, In Progress, In Review, Done). When several repos share one
board, only the primary repo's profile lists the ids; the others name the board and point at
`pdo project-env --board`. Say whether the repo supports GitHub issue types (personal repos don't, and the API
silently drops `type`; name the type labels used instead), and name any legacy tracker that still holds older closed
work (read-only).

Three lines feed the human guide (`/project-setup` renders it from them, so keep them here, not only in the guide):
`Manager` (the person who runs the team, sets priorities and merges, and how to reach them), `Where to ask` (where
collaborators ask questions), and `Human guide notes` (repo-specific things people must know, in plain words: which
repo to file in, house prohibitions).

<!-- Example (Acme):
- Org: `acme-co`. Primary repo: `acme-co/acme-app` (bare `#n` = this repo).
- Related: `acme-co/acme-engine` (the pricing engine; search and file there when a change touches pricing rules).
- Board: org Project #3 "Acme Roadmap", node id `PVT_xxxxxxxxxxxxxxxx`, Status field `PVTSSF_xxxxxxxxxxxxxxxx`.
  Options: Backlog `aaaa1111`, Todo `bbbb2222`, Agent Queue `cccc3333`, In Progress `dddd4444`, In Review `eeee5555`,
  Done `ffff6666`.
- Issue types: org types Epic / Feature / Bug / Task.
- Legacy tracker: closed work before 2025-01-01 is in the old tracker (read-only); new issues go to GitHub only.
- Manager: Dana Lee (@dana-acme on GitHub; the #acme-dev chat channel).
- Where to ask: an issue with the `question` label, or #acme-dev.
- Human guide notes:
  - Pricing bugs go to `acme-co/acme-engine`, not here.
  - Don't run the full test suite against the shared staging database.
A secondary repo sharing the board instead says:
- Board: org Project #3 "Acme Roadmap", shared with `acme-co/acme-app`; ids: `pdo project-env --board`.
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
handled). Give the ports reserved for the human (agents never bind or kill them), the QC ports and whether they are
the human's own dev-server ports (shared: starting QC stops their servers) or separate ones, the port scheme agents use
instead, plus any CORS or API-URL wiring that changing ports requires. Add one "Human run" line: the plain commands
a person runs to start the app (or run the engine) for QC; the human guide's "Run it locally" is rendered from it.

<!-- Example (Acme):
- API: `npm run dev:api` (needs `ACME_DB_URL`; dev auth: `ACME_AUTH=none`, then log in as `demo`).
- Web: `npm run dev:web -- --port <port>`; point it at your API with `ACME_API_URL`.
- Reserved for the human: 3000 and 8080 (their dev servers). QC: 3002 and 8082 (own ports). Agents: web on `4300 + (issue# % 100)`, API on `5300 + (issue# % 100)`.
- DB: shared local Postgres container `acme-db`. Never stop it. Snapshot before running migrations; restore after.
- Human run: `npm run dev:api` and `npm run dev:web` in two terminals, then open the web port and log in as `demo`.
-->

## QC data

What human QC runs against, and how to give it data. Describe the seed data (users, sample projects) and what the
top-level record is called in the UI (checklists name data by it, never by URL or id). Give the fixture format and
file extension, how to export a fixture from the running app, how the human imports it, and any size limit. Fixtures
are published with the engine's `pdo qc-fixture-push <PR#> <file>` to the never-merged `qc-fixtures` branch, never
committed to a PR branch.

A headless repo (an engine, library, CLI or API with no UI) says so here, and what QC means for it: each case is a
fixture input (a file, a request to replay) with its expected output, named by the input, plus the command a human
runs to check it (or "the evidence in the PR body is the QC" where a human only reviews outputs).

<!-- Example (Acme):
- Seed: two users (`demo`, `admin`) and one project, *Acme Demo*.
- Top-level record: "project" (Projects → <name>).
- Fixture format: `.acme-export` (Projects → ⋯ → Export). Import: Projects → Import. Keep under 5 MB.
- Publish: `pdo qc-fixture-push <PR#> <file>.acme-export`.
Headless example (a pricing engine):
- No UI. A QC case is a request file in `qc/requests/` plus its expected response; check one with
  `npm run replay -- <file>` and compare against the expected output in the checklist.
-->

## Changelog

How every PR records its change for release notes: changesets, a CHANGELOG file, PR labels, or nothing. Give the exact
file location and format, with an example entry, and any format traps (characters that break the release build,
retired styles not to copy). If CI enforces it, name the workflow, the label that skips it, and the exact paths it
exempts (a docs-only PR may still need the label or an entry).

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
- CI: `.github/workflows/require-changeset.yml` fails a PR without one, unless it has the `skip changeset` label or
  touches only `docs/**` and `*.md`.
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
(and their `.progress.md` ledgers), the user guide and how it is built, any other docs agents should update when
behaviour changes, and the human guide's path ("Human guide: `<path>`", in a dir that isn't gitignored).

<!-- Example (Acme):
- Design docs: `docs/design/<slug>.md`; ledgers alongside as `docs/design/<slug>.progress.md`.
- User guide: separate repo `acme-co/acme-docs`, `guide/`; update it for user-visible changes only when asked.
- Human guide: `docs/agent-workflow.md` (generated by /project-setup).
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

## Project extras

Optional. Conventions of this project that the engine doesn't define and that humans or agents need to use: PR
comment commands that a project service or the project's `WATCH_EVENT_HOOK` acts on, a hosted preview service (how
to start and stop one, its link pattern, login, build time and idle timeout), chat or bot commands, extra QC steps.
Give each one's exact trigger text, who may use it, and what happens. When this section defines QC commands, put
them under a `### QC commands` heading: every QC checklist ends with that table (the QC commands block). Delete
the section if there is nothing; the engine's QC handoff (labels and PR reviews) works without it.

<!-- Example (Acme, with a preview service and comment commands handled by its WATCH_EVENT_HOOK):
### QC commands
| Comment | What happens |
|---|---|
| `Acme, preview` | Builds this PR into a preview (about 5 min) and replies with the link, `https://pr-<n>.preview.example.com`. Log in as **demo**. |
| `Acme, stop preview` | Stops the preview. Idle previews stop after 4 h. |
Only repo owners, members and collaborators can trigger these.
-->

## Do not

Hard prohibitions: things agents must never do in this repo or its environment, each with a one-line reason.

<!-- Example (Acme):
- Never stop or recreate the `acme-db` container (other sessions share it).
- Never commit fixtures or QC data to a PR branch (they merge into main).
- Never merge to `main`; the human merges.
- Never edit generated files under `web/src/generated/`; regenerate with `npm run codegen`.
-->
