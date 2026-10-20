<!--
Paste this section into the product repo's AGENTS.md (CLAUDE.md then becomes `@AGENTS.md` plus any Claude-only notes).
Replace every <placeholder> (`<guide path>` is where /project-setup wrote the human guide, default
`docs/agent-workflow.md`; `<engine checkout>` is the engine path on the manager's machine, e.g.
`~/src/project-dev-orchestration`, or "your project-dev-orchestration checkout" where there is no engine). For a
repo with no UI, use the headless variant of the QC Checklist rule and delete the other. Keep it short: the details
live in the profile and the skills.
-->

## How work flows here

**Session start: check the human guide acknowledgement (mandatory).** Skip this only if you were dispatched rather
than started by a person: `PDO_DISPATCHED=1` is set in your environment, or your first prompt is a dispatch brief from
an orchestrator. Otherwise, BEFORE answering the first request of the session, whatever it is (a task, a question
about this repo, or a question about these instructions), check `.agents/local/guide-ack` (per clone, gitignored).
- **Missing, or its `guide:` differs from the guide's current version:** your FIRST reply must ask whether the human
  has read both guides: `<guide path>` (this repo's labels, routes, QC and who to ask) and the general guide at
  https://binerbuddy.github.io/project-dev-orchestration/. Offer a 3-line summary of `<guide path>`. Don't wait for
  implementation to start or for the human to ask about onboarding. You may carry on with their request in the same
  reply while you wait for the answer.
- **Record it only on an explicit yes** ("I've read them"). Reading your summary doesn't count. Then write the file
  with two lines: `date: <YYYY-MM-DD>` and `guide: <version>`, where the version is the `guide-version:` value at the
  top of `<guide path>` (no such line: the output of `git hash-object <guide path>`). If they decline or skip, carry on
  and don't ask again this session.
- **Present and current:** never ask.

Work is tracked as GitHub issues in `<org>/<repo>` on org Project `<project#>`, and built by agents running the
project-dev-orchestration skills. Project facts (build commands, ports, QC data, conventions) are in
`.agents/project-profile.md`; read it before you start. To learn the whole pipeline, load the `project-how-it-works`
skill. Engine commands are written `pdo <name>`. If `pdo` isn't on PATH, use `<engine checkout>/bin/<name>` (a
dispatch brief's absolute path wins), or put `pdo` on PATH once with `<engine checkout>/bin/install --bin`.

**Labels and routes**
- `P1-urgent` … `P4-low`: priority, on issues and PRs. A PR takes the highest P-label of the issues it closes
  (`pdo pr-priority`); never set it by hand.
- `route:small` → `/project-small-feature-or-bug-fix`; `route:design` → `/project-feature-design`;
  `route:build` → `/project-feature-build`. An epic built from a design doc has one `epic-phase` sub-issue per phase;
  phases are never worked alone.
- `ready for QC` → the agent's work is done; the PR waits for QC (the team's QC Agent first, where it runs).
  `QC complete - ready to review` → agent QC passed; a human UX review is next. `Ready for Merge` → all QC done
  (`UX testing skipped` with it: agent QC found no visible change). `QC escalated` → agent QC failed twice; a human
  decides. `needs UX review` → always gets a human UX review. Only a human applies `Ready for Merge` by hand.
- `awaiting-ux-gate`: an agent is waiting for a prototype sign-off. `likely-fixed`: an agent thinks the issue is
  already done on `<base>`. `blocked-by-pr`: the PR can't merge until another PR lands. `needs-triage`: not yet
  triaged.
- `managed-by:<manager>`: that manager's agents hold the issue (its claim comment names them). If it isn't your
  manager's, don't work it: ask the human or your manager to coordinate with them. An assignee is a person's lock;
  an issue GitHub shows as "blocked by" an open issue waits for it. Follow `**Coordination (…):**` comments.

**Agents must**
- Work in their own worktree and branch from `origin/<base>`, created with `--no-track` (so a bare `git push` never
  targets `<base>`) and first pushed with `git push -u origin <branch>`; open a PR against `<base>` with `Closes #<n>`
  lines.
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
`pdo intake-submit "<your workspace name>" "<what, where, repro>"`. Each call queues one report: put items that share
a cause or a fix in one report, and unrelated items in separate calls. The human triages the queue with
`/project-intake inbox`. Without an engine install, open an issue with the `needs-triage` label instead (see the
`project-how-it-works` skill).

**QC Checklist rule.** Every PR that changes user-visible behaviour gets one PR comment starting
`<!-- ux-qc-checklist -->` and headed `## QC Checklist`: a GitHub task list of concrete steps in the running app. Name
data by project name and UI path, never by a localhost or host link, port or id. When the seed data doesn't cover a
case, link a fixture published with `pdo qc-fixture-push` to the never-merged `qc-fixtures` branch. End with the QC
handoff block (and the profile's §Project extras QC commands, if any). Update the comment in place; never post a
second one.

<!-- headless variant (no UI): -->
**QC Checklist rule.** Every PR that changes behaviour gets one PR comment starting `<!-- ux-qc-checklist -->` and
headed `## QC Checklist`: a GitHub task list of QC cases, each named by its input (a fixture input file or a request
to replay, published with `pdo qc-fixture-push` to the never-merged `qc-fixtures` branch) with the expected output and
the command that checks it (profile §QC data), plus the evidence you already gathered. No host links, ports or ids.
End with the QC handoff block (and the profile's §Project extras QC commands, if any). Update the comment in place;
never post a second one.
