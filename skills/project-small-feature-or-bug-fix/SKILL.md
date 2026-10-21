---
name: project-small-feature-or-bug-fix
description: Full lifecycle for a small feature or bug fix in the current repo (one that fits a single context window and needs no design doc) - intake, explore, disambiguate, consensus plan, implement in a fresh worktree, automated QC, UX QC checklist, changelog + PR, one background review/triage cycle, final report. Use when asked to build a small feature or fix a bug end to end. Larger or cross-cutting work goes through /project-feature-design then /project-feature-build.
argument-hint: "[feature or bug description]"
---

# Small Feature / Bug Fix (Full Lifecycle)

> Engine commands are written `pdo <name> …`. If `pdo` isn't on PATH, run `<engine checkout>/bin/<name> …` instead; a dispatch brief gives the absolute path, else the repo's `AGENTS.md` names it (`<engine checkout>/bin/install --bin` puts `pdo` on PATH).

Take a small feature or bug fix (one that fits a single context window and needs no design doc; larger work goes
through `/project-feature-design` then `/project-feature-build`) from description to reviewed, review-fixed PR:
intake → explore → disambiguate → consensus plan → implement in a fresh worktree → automated QC → UX QC checklist →
changelog + PR → one background review/triage cycle → final report.

User interaction happens ONLY in phases 1–3 (intake and disambiguation). From phase 4 onward the workflow is fully
autonomous (no plan-approval gate, no triage gates), ending with a final report and a UX QC checklist posted as a
task-list PR comment for the human to tick off. If arguments were given, treat them as the initial feature/bug
description and skip straight to follow-up questions.

`§Name` below means a `##` section of the project profile.

## Before you start

1. **Locate the repo.** The worktree root is `git rev-parse --show-toplevel`. For bare-root layouts the bare root is
   `git rev-parse --git-common-dir` (in a normal clone that prints `.git`; the bare root is then the worktree root).
   New worktrees go in the **worktree parent** (`<worktree parent>` below): `pdo project-env 'WORKTREE_PARENT[<repo>]'`
   when the engine is set up, else the bare root, or `<clone>-worktrees/` next to a plain clone (never inside it).
   `<org>/<repo>` comes from `git remote get-url origin`. §Layout gives the base branch (`<base>` below) and the
   worktree naming convention.
2. **Read the profile**: `.agents/project-profile.md` at the worktree top level, or failing that
   `git show origin/HEAD:.agents/project-profile.md` from the bare root. If there is none, detect the obvious build
   tooling (package.json scripts, `*.sln`, pyproject.toml, Cargo.toml, go.mod), proceed with that, and offer the user
   to write a profile from this plugin's `templates/project-profile.md` (`../../templates/project-profile.md` from this
   skill's directory).
3. **Read `AGENTS.md`** at the repo root (and any tool-specific file such as `CLAUDE.md`).
4. **Project memory**: your tool's project memory, if it has one (Claude Code: the auto-memory dir for this repo).
   Phases below say when to read it; pass the relevant file paths to sub-agents.
5. If an orchestrator dispatched you with a ready worktree and branch, use them wherever this skill says to create
   one. Don't create another.

**Sub-agents.** When a step uses parallel sub-agents, spawn them if your tool supports them (Claude Code: the Agent
tool, background; Codex/Grok: their subagents); otherwise run the roles sequentially. Role prompts and the hand-back
rule are in `../project-pr-review/references/review-roles.md`. Model choice: your strongest generally available model for reviewers
(Claude Code: `model: "opus"`; bump individual reviewers to `"fable"` only for unusually high-risk changes).

**Workflow state (resumability).** At every phase boundary from phase 4 onward, write a short resumability note:
current phase, branch + worktree path, PR number once known, the checklist comment id once known, open decisions, and
a reminder that the phase-9 triage gates are waived. Use your tool's working-memory notepad if available (OMC:
`notepad_write_working`), otherwise a file in the scratchpad. This run is long and autonomous: after any context
compaction, read the note before continuing, so the waivers and phase position survive summarization.

## 1. Intake

Ask the user what the new feature or bug fix entails: expected behaviour, affected screens/areas, and (for bugs)
reproduction steps. Use your tool's question UI or direct questions. Don't over-ask here: deep ambiguities are handled
in phase 3 after exploration, when you know what questions matter.

## 2. Explore

Explore the existing code as you normally would (breadth via search sub-agents if available, direct reads for depth).
Also check the project memory index for entries touching the affected area: past PR triage states, known gotchas, and
parked work often change the plan. Identify: files involved, existing patterns to match, adjacent features to stay
consistent with, and anything that contradicts the user's description.

## 3. Ambiguity loop (only if necessary)

If exploration leaves real ambiguity about specs or intended UX, run a disambiguation loop: enumerate the open
questions, ask the user the ones that change the design (batched), fold answers in, repeat until there are no
design-changing unknowns. If the request was unambiguous, skip this phase entirely. Do not manufacture questions.

## 4. Consensus plan

Draft an implementation plan: approach, files touched, data/API changes, UI changes, migration needs, and explicit
non-goals. Then run the planning consortium:

1. Spawn Architect + Security + Adversary, plus every role from §Review roles (and the UI / UX role when the change has
   a user interface), all at once (see `../project-pr-review/references/review-roles.md`). Each reviews the PLAN (not code): is the approach
   sound, simpler alternatives, security holes, ways it fails. Each ends with AGREE / AGREE-WITH-CHANGES (state them) /
   REJECT (why + alternative).
2. Fold feedback in and re-run the consortium on the revised plan. Repeat until all AGREE, capped at 3 rounds. If
   disagreement survives round 3, resolve it yourself with the code as arbiter and note the unresolved point in the
   final report.

Plan constraints: test work only as §Tests allows (if it says the project has no working test infrastructure, plan no
test work); the changelog update per §Changelog is part of the plan; respect §Conventions and §Do not.

## 5. Implement in a fresh worktree

1. From the bare root, create a branch `<prefix>/<slug>` (`fix/` for a bug, `feat/` otherwise, unless §Layout names
   other prefixes; with the engine, `pdo project-env BRANCH_PREFIX` maps issue types, then labels, to prefixes) from an up-to-date `origin/<base>` and a worktree
   for it (directory named per §Layout):
   `git fetch origin <base> && git worktree add --no-track -b <branch> <worktree parent>/<slug> origin/<base>`
   (`--no-track`: a branch that tracks `origin/<base>` makes a bare `git push` or `git pull` target the base branch;
   the first push sets the branch's own upstream, step 8)
2. Implement per the plan, using implementation sub-agents where parallelism helps (OMC, if available:
   `oh-my-claudecode:executor`). Each gets the plan section, the worktree path, and the conventions: LF line endings
   ONLY; match surrounding style; no drive-by refactors; §Conventions.
3. Commit a checkpoint after every phase/wave without being asked (bisectable, resumable).
4. Fast inner loop, if available: after each wave, run LSP diagnostics on touched files (OMC: `lsp_diagnostics` /
   `lsp_diagnostics_directory`) and fix new errors before the next wave. Use a structural search (OMC:
   `ast_grep_search`) over plain grep when the plan needs every structural usage of a pattern (e.g. all call sites of
   a changed method).
5. Authoritative compile-check before moving on: run the commands in §Build & checks for every touched part (ignore its
   listed known-noise errors). Fix every new error and commit. Do NOT hand off code that doesn't compile. No full test
   runs, no unsolicited dev servers beyond phase 6.

## 6. Automated QC (when applicable)

Skip only when the change genuinely can't be exercised this way (e.g. pure build tooling). Otherwise, from the
feature worktree:

1. Spin up the dev environment per §Dev servers (commands, ports you may use, env vars, dev login, DB rules, the
   headless browser driver). Never bind or kill the ports §Dev servers reserves for the human. Run servers in the
   background.
2. Run a bounded QA cycle INLINE. Do not hand it to a persistent "loop until done" mode (OMC: do NOT invoke the
   `ultraqa` skill: it writes mode state that outlives a crashed run, and its loop is unbounded). Each cycle:
   - TEST: drive the feature headlessly: happy path AND the failure/edge paths the Adversary flagged in planning.
     Capture console errors and failed network requests.
   - VERIFY: for each issue found, confirm it is caused by this change (check against `<base>` / pre-existing
     behaviour) before touching code. Don't "fix" pre-existing bugs here; record those for the final report instead.
   - FIX confirmed issues, checkpoint-commit.
   - RE-TEST the full affected path set, not just the step that failed.
3. Cap at 3 cycles. If issues survive cycle 3, stop fixing: record them as known issues for the final report and flag
   them in the UX QC checklist.
4. Leave the dev servers running afterwards only if the user will QC immediately; otherwise shut them down.

## 7. UX QC checklist

Generate the checklist for HUMAN review of the feature, following `references/qc-checklist.md` exactly. In short:
concrete steps in the running app covering every user-visible behaviour the change adds or alters plus anything not
verifiable statically or headlessly; GitHub task-list format; starts with `<!-- ux-qc-checklist -->` then the heading
`## QC Checklist`; names data by project name and UI path, never by localhost/host links, ports or ids; a "Test data"
item linking a fixture published with `pdo qc-fixture-push` to the never-merged `qc-fixtures` branch when the seed data
doesn't cover the cases; and it ends with the QC handoff block (plus any §Project extras QC commands). Save it to the scratchpad; phase 8 posts it.

## 8. Changelog, push, PR

1. Ensure the changelog entry is up to date per §Changelog.
2. Push the branch and open the PR: `git push -u origin <branch>`, then `gh pr create -R <org>/<repo> --draft --base <base>`
   (always a **draft**: draft CI skips the heavy jobs, which saves Actions minutes while review/triage pushes land)
   with a body summarizing what/why and the automated-QC evidence, with `Closes #<issue>` for every issue it resolves
   (cross-repo: `Closes <org>/<other-repo>#<n>`, only after the human said yes to closing an issue in that repo:
   reading other repos is fine, writing to them needs the check). Record the PR number. Then give the PR the priority of its issues:
   `pdo pr-priority --repo <repo> --pr <number>`. It copies the highest P-label of the
   linked issues onto the PR. Never set a PR's P-label by hand-picking one.
   If the branch is stacked on another unmerged PR, or can't merge until another PR lands: base the PR on that branch,
   put `**Requires #<n> to merge first.**` at the top of the body, and add the `blocked-by-pr` label. When #<n> merges,
   retarget to `<base>`, rebase, and remove the label.
3. Post the phase-7 checklist as a PR comment: `gh pr comment <number> --body-file <scratchpad checklist>`. Record the
   comment's id and URL from the URL the command returned (confirm via
   `gh api repos/<org>/<repo>/issues/comments/<id>` that the body starts with the `<!-- ux-qc-checklist -->` marker)
   in the resumability note: triage needs the id to edit it in place. Tell the user the comment URL so they can start
   UX QC while the background review cycle runs.

## 9. Background review cycle (one cycle, then stop)

Both steps run as BACKGROUND sessions with the full toolset (Claude Code: the Agent tool with
`subagent_type: "general-purpose"`, which can fan out its own consortium sub-agents). Without background sessions, run
them in turn yourself. Spawn them sequentially (triage needs the posted review), waiting on each completion. Permission
prompts from background sessions surface to the user; that's expected. Have each session write its report to a file in
the scratchpad as well as returning it.

1. **Review session**: a session whose task is to run `/project-pr-review` on PR #<number> from the bare root and
   report back the posted review summary and the review's id. Wait for it.
2. **Triage session**: a session whose task is to run `/project-pr-triage` on PR #<number> WITH THESE OVERRIDES (this
   flow is fully autonomous; the skill's two hard gates are waived by the user for this workflow):
   - GATE 1 waived: do not ask which solutions to implement. Implement every finding the verifier consortium approved
     that triages LIKELY or PLAUSIBLE; skip UNLIKELY/NOT-A-FIX as usual.
   - GATE 2 waived: no human QC pause. The §Build & checks compile-check (and headless QC where feasible) stands in;
     push once checks pass and post the fixed/not-fixed comment per the skill.
   - If any fix changes user-visible behaviour, update the changelog entry AND regenerate the UX QC checklist, then
     edit the existing PR checklist comment IN PLACE per `references/qc-checklist.md` ("Updating the posted
     checklist"), with triage-driven items under an `### Added after review triage` heading. Do not post a second
     comment. If no fix changes user-visible behaviour, leave the comment untouched.
3. One cycle only: do not re-run the review after triage pushes.

   **Verifying a write: applies to the review, the checklist comment and the label.** Use the id or URL the write
   command returned; never search for what you just created. `--jq '.[-1]'`, "the newest comment" and "it wasn't there
   before" are not checks: they return a result whether or not your write landed, so no input makes them report
   failure. Query the endpoint you wrote to: `gh pr review` creates a **review** in `pulls/{n}/reviews`, which never
   appears in `issues/{n}/comments`, so checking only the comments endpoint will report a posted review as missing and
   invite a duplicate. Before PATCHing a comment, re-read its body and confirm the expected `<!-- … -->` marker: an id
   captured earlier may now belong to a different comment. A sub-agent's "posted, here is the URL" is a claim; confirm
   the id before relying on it.
4. **Release your side processes, then label the PR ready for QC.** First stop every dev server you or your
   sub-agents started (and their child processes, e.g. bundler watchers) and close any automation browser (e.g.
   Playwright MCP: `browser_close`). Nothing of this run should be left holding RAM. Under the orchestrator the
   session is hibernated a few minutes after this label goes on, and resumed with full context for QC feedback. Then,
   once the triage session has pushed and posted its fixed/not-fixed comment, **and you have confirmed both that
   comment and the review exist by id**, add the `ready for QC` label:
   `gh pr ready <number> -R <org>/<repo>` (out of draft: this triggers the one full CI run), then
   `gh pr edit <number> -R <org>/<repo> --add-label "ready for QC"`
   (create it first with `gh label create "ready for QC" -R <org>/<repo> --color e8b339 --description "Automated
   review+triage done; awaiting human UX QC"` if the repo doesn't have it; GitHub label names cannot contain commas).
   This label signals the automated cycle is finished and the UX QC checklist is the human's to work. The human flips
   the labels when done: removes `ready for QC` and adds `QC complete - ready to review`. The workflow never applies
   the QC-complete label itself. (These are the engine's default label names; if the project env renames them,
   `pdo project-env LABEL_QC_READY` / `LABEL_QC_DONE` print the names to use.)

## 10. Verifier pass + final report

Before reporting, spawn a read-only verifier (OMC, if available: `oh-my-claudecode:verifier`; otherwise a fresh
sub-agent with the verifier brief, or do it yourself in a fresh pass) with the final plan, worktree path, and a diff
summary (`git diff origin/<base>...HEAD --stat` plus key hunks). Its job: confirm every planned item was implemented
or explicitly dropped, and that QC claims have evidence. Fix small gaps it finds (compile-check + checkpoint-commit +
push); list larger ones as known issues in the report.

Report to the user: PR link; what was built (brief); automated-QC results; review outcome (raw vs consensus
findings); triage results (fixed with commits / deliberately not fixed with reasons); the URL of the UX QC checklist
PR comment (the canonical, tick-off copy; note whether triage updated it; do NOT restate the checklist in full);
confirmation that the `ready for QC` label is on the PR, with a reminder that after ticking the checklist the human
swaps it for `QC complete - ready to review`; follow-up items worth ticketing; and the worktree path (left in place
for the user's dev server; do not remove it).

Out-of-scope bugs or ideas noticed on the way: don't fix them here. If the project uses the intake queue (see
`AGENTS.md`), queue them with `pdo intake-submit`; otherwise list them as follow-ups in the report.
