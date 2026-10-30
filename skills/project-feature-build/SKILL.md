---
name: project-feature-build
description: Implement a design doc produced by /project-feature-design in the current repo as one PR with phased, bisectable commits - per-phase build, compile gate, fresh-context review, headless QC, verifier and checkpoint, a committed progress ledger, GitHub phase issues kept in sync, UX gates where the doc declares them, then the review/triage cycle and the ready-for-QC label. Use when asked to build or resume building a feature from a design doc or an epic routed to build.
argument-hint: "<path to design doc> [resume]"
---

# Feature Build (from a Design Doc, Phased)

> Engine commands are written `pdo <name> …`. If `pdo` isn't on PATH, run `<engine checkout>/bin/<name> …` instead; a dispatch brief gives the absolute path, else the repo's `AGENTS.md` names it (`<engine checkout>/bin/install --bin` puts `pdo` on PATH).

Implement a design produced by `/project-feature-design` as one PR with phased, bisectable commits: per-phase build →
compile gate → fresh-context review → headless QC → verifier → checkpoint, with a committed progress ledger, GitHub
phase issues kept in sync, UX gates where the doc declares them, then the review/triage cycle and `ready for QC`. For
small features and bug fixes use `/project-small-feature-or-bug-fix`.

Arguments: the path to the design doc, optionally followed by `resume`.

Autonomous except at three points: (1) confirming drafted acceptance criteria if the doc lacks them; (2) UX gates
declared in the doc's phase plan; (3) a spike that comes back no-go. There is no plan-approval gate and the
review-triage gates are waived (as in `/project-small-feature-or-bug-fix`).

`§Name` below means a `##` section of the project profile. Design-doc sections (§Delivery phases, §Non-goals, §Follow-ups, §Decisions, §Tracking, §Revision log) are the doc contract's, not the profile's. Sibling-skill references used here:
`../project-feature-design/references/doc-contract.md`,
`../project-pr-review/references/review-roles.md`,
`../project-small-feature-or-bug-fix/references/qc-checklist.md`.

## Before you start

1. **Locate the repo.** The worktree root is `git rev-parse --show-toplevel`. For bare-root layouts the bare root is
   `git rev-parse --git-common-dir` (in a normal clone that prints `.git`; the bare root is then the worktree root).
   New worktrees go in the **worktree parent** (`<worktree parent>` below): `pdo project-env 'WORKTREE_PARENT[<repo>]'`
   when the engine is set up, else the bare root, or `<clone>-worktrees/` next to a plain clone (never inside it).
   `<org>/<repo>` comes from `git remote get-url origin`. §Layout gives the base branch (`<base>` below) and the
   worktree naming convention; §Identity gives related repos, the board (`<project#>`) and its ids.
2. **Read the profile**: `.agents/project-profile.md` at the worktree top level, or failing that
   `git show origin/HEAD:.agents/project-profile.md` from the bare root. If there is none, detect the obvious build
   tooling (package.json scripts, `*.sln`, pyproject.toml, Cargo.toml, go.mod), proceed with that, and offer the user
   to write a profile from this plugin's `templates/project-profile.md` (`../../templates/project-profile.md` from this
   skill's directory). Read §Build & checks, §Tests, §Dev servers,
   §QC data, §Changelog and §Conventions in full: every phase uses them.
3. **Read `AGENTS.md`** at the repo root (and any tool-specific file such as `CLAUDE.md`).
4. **Project memory**: your tool's project memory, if it has one (Claude Code: the auto-memory dir for this repo).
   Read its index and every entry the doc names.
5. If an orchestrator dispatched you with a ready worktree and branch, use them wherever this skill says to create
   one. Don't create another.

**Sub-agents.** When a step uses parallel sub-agents or background sessions, spawn them if your tool supports them
(Claude Code: the Agent tool, background; Codex/Grok: their subagents); otherwise run the roles sequentially.
Optional OMC accelerators (executor, code-reviewer, verifier agents; LSP and ast-grep tools) are used where noted, if
available.

## 0. Load and validate

1. Read the doc. Validate it against the doc contract: phases with `depends-on`, acceptance criteria, `ux-gate`;
   §Decisions with no `open` items; §Tracking filled.
2. Missing acceptance criteria → draft them per phase and confirm once with the user (your tool's question UI).
   Missing §Tracking → run phase 8 of `/project-feature-design` inline, then continue.
3. If `resume` was passed, or the ledger (`<doc dir>/<slug>.progress.md`) already exists on the feature branch → go
   to **Resume**.
4. Build the **pins block** once: §Decisions + §Non-goals verbatim. Every sub-agent gets it.

## 1. Worktree, branch, tracking state

- Branch `feat/<epic#>-<slug>` (epic number from §Tracking); keep the `feat/` prefix. Worktree directory named per
  §Layout (default `<worktree parent>/<slug>`).
- From the bare root:
  ```
  git fetch origin <base> docs/<slug>-design
  git worktree add --no-track -b feat/<epic#>-<slug> <worktree parent>/<dir> origin/docs/<slug>-design
  cd <worktree parent>/<dir> && git rebase origin/<base>
  ```
  `--no-track` keeps the branch from tracking the docs branch, so a bare `git push` never lands there. Make the
  first push (phase 1's checkpoint) `git push -u origin feat/<epic#>-<slug>`, which gives it its own upstream.
  (If no docs branch exists, or its design PR already merged and the branch is stale, branch from `origin/<base>`,
  also with `--no-track`, and, if the doc isn't there yet, copy it in as the first commit.)
- Board (org Project `<project#>`, ids from §Identity, as in `/project-feature-design` phase 8): epic → Status In
  Progress (`gh project item-edit … --single-select-option-id <In Progress option id>`).

## 2. Ledger and QA home

- **Ledger** `<doc dir>/<slug>.progress.md`, committed, authoritative for resume. Header: branch, worktree, PR
  number/URL (once known), epic and phase issue numbers, checklist comment id. One block per phase: status (`pending`
  / `in progress` / `done` / `gate pending` / `gate approved` / `gate changes requested` / `no-go`), start commit,
  checkpoint commits, acceptance criteria with pass/fail evidence, divergences from the doc (what and why), review
  findings fixed/deferred, known issues, screenshot paths.
- **QA home** `.omc/qa/<slug>/` in the worktree (the engine's `pdo shots` reads it; an engine project may move the root
  with `SCREENSHOT_DIR`, see `pdo project-env SCREENSHOT_DIR`; keep it out of git, e.g. via
  `.git/info/exclude` if the repo doesn't ignore `.omc/`; it persists because the worktree is left in place):
  cumulative smoke driver (e.g. `smoke.mjs`, built on the headless driver from §Dev servers / §Tests),
  `shots/phase-N-*.png`, server logs.
- Also write a resumability note at every phase boundary (phase, branch, worktree, PR, gate states, "review-triage
  gates waived") so compaction can't lose position: your tool's working-memory notepad if available (OMC:
  `notepad_write_working`), otherwise a scratchpad file. The ledger wins on conflict.
- **Draft PR** after phase 1's first checkpoint push: `gh pr create -R <org>/<repo> --draft --base <base>` with a
  placeholder body (doc link, phase table, `Part of #<epic>`). It gives gates and the checklist a home from the start.
  Record the number in the ledger. Then run `pdo pr-priority --repo <repo> --pr <number>`, which gives the PR the epic's P-label (it reads `Closes`/`Part of #<epic>`).
  Stacked on, or waiting for, another unmerged PR: add `**Requires #<n> to merge first.**` to the body and the
  `blocked-by-pr` label; remove the label after #<n> merges and the PR is retargeted.

## 3. Phase loop

Run phases in topological `depends-on` order. While an `async` gate is pending, keep running phases that don't depend
on the gated one.

For each phase:

1. **Brief** (scratchpad file): the phase section verbatim; the pins block; conventions (LF line endings only;
   §Conventions; test work only as §Tests allows; §Do not; no drive-by refactors; match surrounding style); the
   §Build & checks commands; project-memory paths relevant to the phase; worktree, branch, ledger and QA-home paths.
2. **Run the phase in a background session** with the full toolset and the brief (Claude Code: Agent with
   `subagent_type: "general-purpose"`, which can spawn its own sub-agents). This keeps the lead's context to ledger
   and summaries. Run inline only for a phase touching ≲5 files, or when your tool has no background sessions. Tell
   the session to write its report to a scratchpad file as well as returning it. The phase session:
   1. Implements, via implementation sub-agents where parallelism helps (OMC: `oh-my-claudecode:executor`); LSP
      diagnostics as the inner loop and structural search for sweeps, if available (OMC: `lsp_diagnostics`,
      `ast_grep_search`).
   2. Compile gate: the commands in §Build & checks for every touched part (ignore its listed known-noise errors).
      Fix, then checkpoint `feat(<slug>): phase N — <name>`.
   3. Phase review, fresh context, on the phase diff only (`git diff <start>..HEAD`): spawn a Code Review reviewer
      (OMC: `oh-my-claudecode:code-reviewer`) and an Adversary (`../project-pr-review/references/review-roles.md`) at once, each with the brief but
      NOT the implementation reasoning. Fix verified Critical/High/Medium findings; log Low as ledger notes.
      Checkpoint.
   4. Phase QC (skip only if genuinely not exercisable): dev environment per §Dev servers (its env, dev login, the
      ports you may use; servers in the background; never touch the ports reserved for the human); extend the smoke
      driver with checks for this phase's acceptance criteria; run the FULL smoke (all phases so far); bounded cycle
      test → verify-cause (against `<base>`; don't fix pre-existing bugs) → fix → re-test, max 3; capture
      screenshots of any UI to `shots/`.
   5. Read-only verifier (OMC: `oh-my-claudecode:verifier`; otherwise a fresh sub-agent or pass): acceptance
      criteria vs diff + QC evidence. Fix small gaps; list larger ones as known issues.
   6. Update the ledger phase block, commit, and return a compact report (≤40 lines): commits, criteria pass/fail,
      divergences, known issues, screenshot paths, gate package if any.
3. **Lead, after each phase**: update the resumability note; push; phase issue → Project Status In Progress (the
   `Closes #N` lines move it to Done on merge; never close phase issues yourself) and `gh issue comment` on it with commits, criteria status, divergences, QC evidence, and screenshot
   paths under `.omc/qa/<slug>/shots/` (the API cannot upload images; the gate PR comment carries them). If a
   divergence changes the design: bump the doc revision (affected section + §Revision log) and commit.
4. **Spike phases**: honour the doc's time-box; write go/no-go with evidence to the ledger and the phase issue.
   No-go → push, report what was learned and the options, STOP. This is a human decision.
5. **Gates**: build the package first: a PR comment starting `<!-- ux-gate-phase-N -->` with a task-list of what to
   look at and confirm, the screenshots for the phase (paths, plus the line "Open them: `pdo shots <PR#>`"), the dev-server URL, and any decision the run needs. Leave the dev servers running. Ledger status →
   `gate pending`. Add the `awaiting-ux-gate` label to the PR while you wait, so it shows in the human's PR list,
   and under the orchestrator to the issue too (it frees your slot). Remove it from both as soon as the human
   responds.
   - `blocking`: push, post, report, STOP. The user resumes with `/project-feature-build <doc> resume`.
   - `async`: post, then continue with phases whose `depends-on` excludes the gated phase. Before starting a dependent
     phase, check for feedback (ticks/notes on the gate comment via `gh api`, a comment on the phase issue, or chat).
     Still pending with only dependent phases left → treat as blocking.
   - Feedback handling on either kind: approved → ledger `gate approved`, continue. Changes requested → fold into the
     doc (revision bump), run a fix mini-phase through the same loop, re-post the package under the same marker
     (PATCH the comment after confirming its marker; keep `[x]` on surviving items), then continue.
6. **Regression**: every phase reruns the full smoke. A failure in an earlier phase's check is fixed in the current
   phase and recorded in both phase blocks.

## Resume

Read the ledger (and the resumability note). Rebuild the position: which phases are done, which gate is pending, PR
number, checklist comment id. Check gate feedback as in 3.5 and fold it in. Continue the loop from the first non-done
phase. Never re-run a done phase.

## 4. Finalize

Once every phase is done and every gate approved:

1. Full compile gate (§Build & checks) and full smoke run. Changelog entry per §Changelog.
2. Doc: `Status: Implemented — rev N`, §Follow-ups updated; ledger final block; commit.
3. **UX QC checklist**: one PR comment following `../project-small-feature-or-bug-fix/references/qc-checklist.md` exactly: it starts with `<!-- ux-qc-checklist -->`
   then the heading `## QC Checklist`, names data by project name and UI path (never localhost/host links, ports or
   ids), and is a GitHub task-list: the union of the per-phase gate checklists (carry over `[x]` the user already
   ticked) plus every user-visible behaviour not verifiable headlessly (layout, timing, realtime push, DB-dependent
   paths). Test data: a fixture in the §QC data format showing the cases, published with
   `pdo qc-fixture-push <PR#> <file>` to the never-merged `qc-fixtures` branch (never on the PR branch), with a "Test data"
   item linking its `download:` URL (a file download, not the Raw view) and giving the import steps. End with the QC handoff block (plus any §Project extras QC commands). Record the comment id (from the URL
   the command returned) in the ledger and the resumability note.
4. **PR**: keep it a **draft** (draft CI skips the heavy jobs while review/triage pushes land), write the final body: what/why, phase table with commit ranges, QC evidence,
   divergences, "Follow-ups (not filed)", then the close list: `Closes #<epic>` and one `Closes #<n>` line per phase issue and per
   fixed-by issue from the doc's §Tracking (cross-repo: `Closes <org>/<other-repo>#<n>`, only where the design's decisions
   gate or the human approved that write; otherwise ask first), and the attribution line
   your tool or session prescribes, if any. Merging closes them.
5. **Review/triage cycle** exactly as `/project-small-feature-or-bug-fix` phase 9 (background sessions:
   `/project-pr-review`, then `/project-pr-triage` with GATE 1 and GATE 2 waived, in-place checklist PATCH, one cycle
   only, `ready for QC` label), with two additions: the review session receives the doc and ledger paths and, if the
   diff exceeds ~1500 lines, tells reviewers to work by the ledger's phase commit ranges; the triage session appends
   its commits to the ledger.

   **Before the `ready for QC` label goes on**, stop every dev server of this build (and their child processes) and
   close any automation browser (e.g. Playwright MCP: `browser_close`), then take the PR out of draft with
   `gh pr ready` (this triggers the one full CI run). Under the orchestrator the session is
   hibernated shortly after the label goes on, and resumed with full context for QC feedback.

   **Do not apply the `ready for QC` label until you have confirmed the review artifact exists**, and confirm it by
   **id**, not by looking for "the newest comment". A sub-agent reporting that it posted is a claim, not evidence; and
   its own verification may have been a positional query that cannot fail. See *Verifying a write* below: a review
   posted with `gh pr review` lives in `pulls/{n}/reviews` and is **absent** from `issues/{n}/comments`, so checking
   only the comments endpoint will tell you a posted review does not exist.
6. Verifier pass (read-only; OMC: `oh-my-claudecode:verifier`) over the whole doc: every phase's criteria met or
   explicitly dropped, QC claims evidenced. Fix small gaps (compile, commit, push).
7. **Follow-ups**: never file GitHub issues for them, and never guess a P label. The PR body's "Follow-ups (not
   filed)" list carries every §Follow-ups item (deferred scope, hardening, cleanup, test gaps), with `file:line`. Only
   items that clear the reporting bar (AGENTS.md) also go to intake, in one report at wrap-up: `pdo intake-submit
   --checked <#n|none> "<your workspace name>" "<report>"`. When the list isn't empty, add the `has-follow-ups` label to the PR (`gh pr edit <n> --add-label has-follow-ups`). Comment on the epic with the PR link and the phase summary. Leave the epic open
   and In Progress; closing it is the human's call after merge (the `Closes #<epic>` line does it on merge unless
   removed).
8. Project-memory note `<slug>-build` (if your tool has project memory): PR, head, worktree, dev-server state, design
   pins, gotchas found, follow-ups. Add its line to the memory index.

## Verifying a write

Applies to every outward-facing artifact this skill creates (PR body, review, checklist comment, labels, issues and
issue comments) and to every sub-agent report that one was created.

**Use the id the write returned. Never search for what you just made.**

- `gh pr comment`, `gh pr review`, `gh issue comment` and `gh api -X POST …/issues` all return the thing's URL or id.
  That return value is the only evidence that identifies *your* write. Record it in the ledger and report it from
  there.
- **Match on identity, not position.** `--jq '.[-1]'`, "the newest", "the last one I saw" and "it wasn't there
  before" are not checks: they return a result whether or not your write landed, so no input makes them report
  failure. If you need to confirm independently, fetch the specific id.
- **Query the endpoint you wrote to.** `gh pr review` creates a review in `pulls/{n}/reviews`; `gh pr comment`
  creates a comment in `issues/{n}/comments`. Neither appears in the other. Absence from one endpoint is not absence
  from the PR, and treating it as such leads to posting a duplicate of something that was already there.
- **Before overwriting or PATCHing a comment, confirm the target's marker.** Read the body and check it starts with
  the expected `<!-- … -->` sentinel. An id captured earlier may now belong to a different comment.
- A sub-agent's "I posted it, here is the URL" is a claim. Verify the id before acting on it, especially before
  applying a label that asserts the work is done.

The general form, which is worth stating because this family of mistakes has cost this workflow real time: **a value
read at one moment and trusted at another is only as good as the gap between them.** Make the check and the use
atomic, or pick an operation that does not need the gap to be empty.

## Report

PR link; phases delivered with commits; gates and their outcomes; automated-QC results; review outcome and triage
results; checklist comment URL (don't restate it); `ready for QC` label confirmation and the reminder that the human
swaps it for `QC complete - ready to review`; epic link; the follow-ups list and any intake report; worktree path (left in place with dev
servers if the user will QC now).
