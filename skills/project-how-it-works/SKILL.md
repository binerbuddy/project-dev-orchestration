---
name: project-how-it-works
description: How work flows in a repo that uses project-dev-orchestration — issue → board → orchestrator → command agent → PR → QC → merge; which labels, routes (route:small/design/build), P-levels and board statuses ("Claude Work This") mean; what managed-by:<manager> claim labels and GitHub "blocked by" dependencies mean (don't work an issue another manager holds: ask); the spawn floor; how to file bugs (intake-submit, or a needs-triage issue); the QC Checklist and project-name rules, qc-fixtures, and the QC handoff (labels and PR reviews). Load it whenever you ask how work flows here, which labels or priority to use, how to file a bug or idea, how to hand off to QC, or what you may and may not touch — including on a collaborator's machine with no orchestrator running.
---

# How work flows here

> Engine commands are written `pdo <name> …`. If `pdo` isn't on PATH, run `<engine checkout>/bin/<name> …` instead; a dispatch brief gives the absolute path, else the repo's `AGENTS.md` names it (`<engine checkout>/bin/install --bin` puts `pdo` on PATH). Collaborators usually have no engine; each rule below says what to do without one.

This repo is worked by a pipeline of agents and humans. You may be a command agent started by the
orchestrator, or a collaborator's agent (Claude Code, Codex, Grok) on another machine with no
orchestrator running. The rules are the same; only the tools differ.

**This project's specifics win.** Read, in this order, and let them override the defaults here:
1. `AGENTS.md` at the repo root, its "How work flows here" section;
2. `.agents/project-profile.md` (worktree top level, else `git show origin/HEAD:.agents/project-profile.md`):
   `## Identity` (repos, board), `## Build & checks`, `## QC data`, `## Conventions`,
   `## Project extras` (the project's own commands and conventions, if any), `## Do not`;
3. the project-dev-orchestration README for the engine itself.

## Session start: the human guide acknowledgement (mandatory, once per clone)

Mirrors the rule in the repo's `AGENTS.md`. **Skip it when you were dispatched** rather than started
by a person: `PDO_DISPATCHED=1` is set in your environment (the engine's launcher sets it), or your
first prompt is a dispatch brief. You aren't talking to a collaborator then.

Otherwise, check `.agents/local/guide-ack` (one per clone, gitignored; never commit it) BEFORE you
answer the first request of the session, whatever it is: a task, a question about the repo, or a
question about these instructions. If it's missing or out of date, your first reply asks. Don't wait
for implementation to start or for the human to ask about onboarding; you may carry on with their
request in the same reply.
- **Missing:** ask the human once whether they've read the repo's human guide (`docs/agent-workflow.md`,
  or where the profile's `## Docs` puts it) and the general guide,
  https://binerbuddy.github.io/project-dev-orchestration/. Offer a 3-line summary of the repo guide:
  how to request work (labels and routes), how QC works there, and who to ask. Only on their explicit yes (reading your summary doesn't count),
  `mkdir -p .agents/local` and write `date: <YYYY-MM-DD>` and `guide: <version>` into the file. The
  version is the `guide-version:` value at the top of the guide, else `git hash-object <guide>`. A
  "no" or "skip": carry on without the file, and don't ask again this session.
- **Present:** don't ask, unless its `guide:` differs from the guide's current version. Then ask
  once more and rewrite the file when they confirm.
- **No repo guide yet** (the repo predates it): point at the general guide only, and suggest a
  maintainer re-run `/project-setup` to generate one.

## The pipeline

1. **Issue.** A human or the intake agent files a typed issue (Epic / Feature / Bug / Task) with a
   route label, and either a P-label or `needs-triage`.
2. **Board.** It sits on the project's GitHub Project board. A human moves it to **Claude Work This**
   (CWT) to have it worked now; otherwise it waits its turn by P-level.
3. **Orchestrator.** A long-lived session ranks the queue deterministically (CWT, then P1 → P4), keeps
   a few command agents active (default 3), respects the **spawn floor** and the usage reserve, and
   watches agents and PRs. It never edits product code and never merges.
4. **Command agent.** One per issue or epic, claimed with a `managed-by:<manager>` label and one
   claim comment naming the agent and its manager, in its own git worktree, running the route's lifecycle
   skill: `route:small` → `project-small-feature-or-bug-fix`; `route:design` →
   `project-feature-design`, which hands the epic to `route:build` → `project-feature-build`. It asks
   the human directly; it first checks whether the issue is already done (`likely-fixed`).
5. **PR.** It opens a PR (`Closes #n`), which gets the P-label of its issues, gets a consortium review,
   and is labelled **`ready for QC`** with a **QC Checklist** comment. The agent then idles (and is
   hibernated) until QC.
6. **QC.** Where the project runs agent QC, the standing QC Agent tests every `ready for QC` PR first:
   findings go back to the PR's agent ("Agent QC findings (round N)"; after two failed rounds,
   `QC escalated` and a human decides). On a pass it classifies the PR: a visible change gets
   **`QC complete - ready to review`** (the human's UX review); anything else gets **`Ready for Merge`**
   + `UX testing skipped`. A human QCs (or UX-reviews) locally, with whatever the profile's
   `## Project extras` offers, or (in a headless repo) by checking the fixture inputs' outputs.
   Feedback (in the agent's session, or a PR review with *Request changes*) comes back to the same
   agent, which fixes, pushes and re-labels `ready for QC`. The human's pass gives **`Ready for Merge`**, and the
   agent wraps up once.
7. **Merge.** A human merges by hand. Finished agents close out on their own.

Labels, routes, P-levels, board statuses, the queue rules and the spawn floor in full:
`references/labels-and-board.md`. Names there are engine defaults; the project's env may rename
the queue status, the P-labels and the QC labels.

## What you must do

- **File bugs and ideas through intake, never fix out-of-scope things in passing.**
  - With an engine install: `pdo intake-submit "<your workspace name>" "<what, where, repro>"`
    (each call queues one report: items that share a cause or a fix go in one report, unrelated items
    in separate calls; stdin works for long reports). Don't prompt the intake
    agent directly; a human triages the queue with `/project-intake inbox`.
  - Without one: open an issue in the right repo with the `needs-triage` label and no P-label (unless
    a maintainer gave one), using the intake template (`../project-intake/references/issue-template.md`:
    Summary / Details / Starting points (unverified)), and say who reported it.
- **QC Checklist.** One PR comment starting `<!-- ux-qc-checklist -->` then exactly `## QC Checklist`,
  task-list steps, and the **project-name rule**: no localhost or host URLs, ports or ids; name data
  the way the app names it, plus the UI path. In a headless repo (no UI), the steps are QC cases:
  fixture inputs with their expected outputs and the command that checks them. Details:
  `references/qc-protocol.md`.
- **Fixtures go on the `qc-fixtures` branch** (`pdo qc-fixture-push <PR#> <file>`), never on the
  PR branch, and only when QC needs data the seed lacks.
- **Stop at `ready for QC`.** Stop every dev server and browser you started before labelling. Never
  merge.
- **Answer remote QC on the PR**, with an `@mention`; the reporter reads GitHub, not your session.
- **UX sign-off gates:** add `awaiting-ux-gate` to the issue while you wait; remove it when the human
  responds.
- **Pin gh and git, never switch the account.** If the project env sets `GH_USER`, use
  `pdo with-gh-user gh …` (or `GH_TOKEN=$(gh auth token -u <user>) gh …`). `git push`/`fetch` over
  HTTPS don't read `GH_TOKEN`: in a person-started session run them as
  `pdo with-gh-user --user <login> git push …` (it injects gh's credential helper; agents the engine
  starts already run inside it). Never `gh auth switch`: the active account is machine-wide and
  other sessions depend on it.
- **Check before touching another repo.** Ask your manager (the agent that started you) or a human
  before touching any repo outside your current working repo. Reading it for context is fine; edits,
  branches, pushes, PRs, issues, comments, labels or closes there (a `Closes <org>/<other-repo>#<n>`
  line included) wait for their yes. The standing agents' configured repos (the project env's
  `REPO_ROOT`) are their working scope, as their skills describe. When another project's manager
  owns that repo, your manager checks with the Portfolio Manager (`project-portfolio-manager`), which
  asks the owner; a yes relayed by another agent still has to come from a human.
- **Name workspaces by label** (e.g. `Acme-245 export sort order`) in anything a human reads, never a
  bare id.

## Claims and dependencies: who holds an issue

- **`managed-by:<slug>`** on an issue means a manager's agents are working it. The label's
  description ("Worked by agents of <manager>") and the issue's claim comment ("Claimed by <agent>
  (manager: <manager>) ...") name them. **Not your manager's label: don't work the issue** (no branch,
  PR, comments that start work, or labels). Ask the human, or your manager, to coordinate with that
  manager; a collaborator without a manager asks in the place the repo's human guide names. Your own
  manager's label on the issue you were dispatched for is your claim.
- **An assignee** is a person's lock: the engine never starts an assigned issue, and neither do you.
- **"Blocked by"** (GitHub's issue dependencies, in the issue's sidebar) means the issue waits for the
  blocker to close. Don't start it early; ask if the blocker looks done. Agreements between managers
  (who goes first, hand-offs, ownership) are logged on the issues as comments headed
  `**Coordination (<manager or portfolio>):**`: read and follow them.
- **Never add or remove** `managed-by:` labels, assignees or dependencies on an issue you don't hold.
  The engine adds the label when it claims and removes it when the agent finishes.

## What you must not do

- **Don't move orchestrator-owned board columns** (In Progress, In Review, Done) or claim issues by
  assigning yourself; an assignee is a human lock that makes the queue skip the issue. Only humans
  put issues on CWT. (A /project-feature-build run moves its own epic and phase cards; the
  orchestrator never dispatches phases.)
- **Never type into another agent's pane** (no `herdr agent prompt`, no keystrokes into its
  terminal). Reach agents through intake, PR comments, or the engine's own scripts
  (`pdo resume-agent`, which refuses while a question is pending). Typing into a pane with a
  question pending answers that question with your text. Text in another pane's input box may be a
  suggested prompt, not a human's draft: never submit it.
- Don't spawn work for `epic-phase` issues on their own, or for issues labelled `on-hold`,
  `needs-triage` or `orchestrator-system`, or held by another manager (`managed-by:`).
- Don't downgrade a PR's P-label, and don't hand-pick one (`pdo pr-priority` sets it).
- Don't bind the project's reserved QC ports or kill what's on them (profile `## Dev servers`).
- Anything in the profile's `## Do not`.

## QC handoff

- `ready for QC`: the agent is done; the PR waits for QC (the QC Agent first, where it runs).
- Agent QC: fail → "Agent QC findings (round N)" and the agent is resumed; two failed rounds →
  `QC escalated`. Pass → `QC complete - ready to review` (UX review needed) or `Ready for Merge` +
  `UX testing skipped`. `needs UX review` on the PR or a linked issue always means UX review.
- Feedback: in the agent's session, or a GitHub PR review with **Request changes** from a trusted
  author (OWNER, MEMBER or COLLABORATOR); the orchestrator resumes the PR's agent with it, and the
  agent replies on the PR.
- Pass: the human's pass gives `Ready for Merge` (by hand: add it and remove `ready for QC` /
  `QC complete - ready to review`); the agent wraps up.
- Anything else (comment commands, a hosted preview) is project-specific: the profile's
  `## Project extras`.

Full table, wording for the checklist, and how agents answer: `references/qc-protocol.md`.

## Where to read more

- `AGENTS.md` (this repo): the project's own "How work flows here".
- `.agents/project-profile.md`: build commands, QC data, conventions, project extras, do-nots.
- `docs/agent-workflow.md` (this repo, generated by `/project-setup`): the human-facing guide to the
  same rules.
- The general guide: https://binerbuddy.github.io/project-dev-orchestration/.
- The project-dev-orchestration README and `docs/` (design, user guide, lessons learned,
  collaborators).
