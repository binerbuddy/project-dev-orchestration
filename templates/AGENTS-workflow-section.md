<!--
Paste this section into the product repo's AGENTS.md (CLAUDE.md then becomes `@AGENTS.md` plus any Claude-only notes).
Replace every <placeholder> (`<guide path>` is where /project-setup wrote the human guide, default
`docs/agent-workflow.md`). Keep it short: the details live in the profile and the skills.
-->

## How work flows here

Work is tracked as GitHub issues in `<org>/<repo>` on org Project `<project#>`, and built by agents running the
project-dev-orchestration skills. Project facts (build commands, ports, QC data, conventions) are in
`.agents/project-profile.md`; read it before you start. To learn the whole pipeline, load the `project-how-it-works`
skill. Engine commands are written `pdo <name>`; if `pdo` isn't on PATH, use `<engine checkout>/bin/<name>` (a
dispatch brief gives the absolute path).

**First session in a clone: the human guide (once).** Skip this if you were dispatched rather than started by a
person: `PDO_DISPATCHED=1` is set in your environment, or your first prompt is a dispatch brief from an orchestrator.
Otherwise, at the start of work, check for `.agents/local/guide-ack` (per clone, gitignored).
- Missing: ask the human once whether they've read the human guide, `<guide path>` (this repo's labels, routes, QC
  and who to ask), and the general guide at https://binerbuddy.github.io/project-dev-orchestration/. Offer a 3-line
  summary of `<guide path>`. When they confirm, create the file with two lines: `date: <YYYY-MM-DD>` and
  `guide: <version>`, where the version is the `guide-version:` value at the top of `<guide path>` (no such line: the
  output of `git hash-object <guide path>`). If they decline or skip, carry on and don't ask again this session.
- Present: never ask again, unless its `guide:` differs from the guide's current version; then ask once more and
  rewrite the file on confirmation.

**Labels and routes**
- `P1-urgent` … `P4-low`: priority, on issues and PRs. A PR takes the highest P-label of the issues it closes
  (`pdo pr-priority`); never set it by hand.
- `route:small` → `/project-small-feature-or-bug-fix`; `route:design` → `/project-feature-design`;
  `route:build` → `/project-feature-build`. An epic built from a design doc has one `epic-phase` sub-issue per phase;
  phases are never worked alone.
- `ready for QC` → the agent's work is done and the PR's QC checklist is the human's to work.
  `QC complete - ready to review` → the human has passed QC. Only the human applies it.
- `awaiting-ux-gate`: an agent is waiting for a prototype sign-off. `likely-fixed`: an agent thinks the issue is
  already done on `<base>`. `blocked-by-pr`: the PR can't merge until another PR lands. `needs-triage`: not yet
  triaged.

**Agents must**
- Work in their own worktree and branch from `origin/<base>`; open a PR against `<base>` with `Closes #<n>` lines.
- Pass the checks in the profile's §Build & checks before handing off code.
- Stop their dev servers and browsers before labelling a PR `ready for QC`.
- Verify every GitHub write by the id it returned, never by searching for "the newest".

**Agents must not**
- Merge to `<base>`; the human merges.
- Move board cards when an orchestrator is running (it owns the board). Exception: a /project-feature-build run moves its own epic's and phase issues' cards (the orchestrator never dispatches phases).
- Commit QC fixtures or test data to a PR branch.
- Do anything listed in the profile's §Do not.

**Other repos.** Check with your manager (the agent that started you) or a human before touching any repo outside
this one. Reading another repo for context is fine; editing its files, creating branches, pushing, opening PRs or
issues, commenting, labelling or closing anything there (a `Closes <org>/<other-repo>#<n>` line included: merging
closes that issue) waits for their yes. When another project's manager owns that repo, your manager checks with the
portfolio manager, which asks the owner.

**Intake rule.** Don't fix or file bugs and ideas you notice outside your task. Queue them for the intake agent:
`pdo intake-submit "<your workspace name>" "<what, where, repro>"` (one report per call). The human triages the queue with
`/project-intake inbox`. Without an engine install, open an issue with the `needs-triage` label instead (see the
`project-how-it-works` skill).

**QC Checklist rule.** Every PR that changes user-visible behaviour gets one PR comment starting
`<!-- ux-qc-checklist -->` and headed `## QC Checklist`: a GitHub task list of concrete steps in the running app. Name
data by project name and UI path, never by a localhost or host link, port or id. When the seed data doesn't cover a
case, link a fixture published with `pdo qc-fixture-push` to the never-merged `qc-fixtures` branch. End with the QC
commands block. Update the comment in place; never post a second one.
