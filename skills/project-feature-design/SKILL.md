---
name: project-feature-design
description: Take a large or cross-cutting feature in the current repo from idea to an implementation-ready design doc - code/memory/issue survey, proposal, consortium review, one human decisions gate, committed doc with a phased delivery plan and UX gates, then a GitHub epic with one sub-issue per phase. Use when a feature is too big for /project-small-feature-or-bug-fix, needs design decisions, or when asked to design, revise or complete a design doc. Output feeds /project-feature-build.
argument-hint: "<feature description> | <path to existing design doc>"
---

# Feature Design (Survey → Consortium → Decisions → GitHub Epic)

> Engine commands are written `pdo <name> …`. If `pdo` isn't on PATH, run `<engine checkout>/bin/<name> …` instead; a dispatch brief gives the absolute path, else the repo's `AGENTS.md` names it (`<engine checkout>/bin/install --bin` puts `pdo` on PATH).

Take a large or cross-cutting feature from idea to an implementation-ready design document: code/memory/issue survey →
proposal → consortium review → human decisions gate → committed doc with a phased delivery plan → GitHub epic (one
sub-issue per phase) tracking the doc. The output feeds `/project-feature-build`. For small features and bug fixes use
`/project-small-feature-or-bug-fix`.

The argument is either a feature description (new design) or a path to an existing design doc (revise / complete /
tracking-only mode; see phase 0).

The only human gate is phase 6 (decisions). Everything else is autonomous. Don't manufacture questions; batch the ones
that change the design.

`§Name` below means a `##` section of the project profile. Design-doc sections (§Delivery phases, §Non-goals, §Follow-ups, §Decisions, §Tracking, §Revision log) are the doc contract's, not the profile's. The doc contract is `references/doc-contract.md`.

## Before you start

1. **Locate the repo.** The worktree root is `git rev-parse --show-toplevel`. For bare-root layouts the bare root is
   `git rev-parse --git-common-dir` (in a normal clone that prints `.git`; the bare root is then the worktree root).
   `<org>/<repo>` comes from `git remote get-url origin`. §Layout gives the base branch (`<base>` below) and the
   worktree naming convention; §Identity gives related repos, the board (`<project#>`) and its ids.
2. **Read the profile**: `.agents/project-profile.md` at the worktree top level, or failing that
   `git show origin/HEAD:.agents/project-profile.md` from the bare root. If there is none, detect the obvious build
   tooling (package.json scripts, `*.sln`, pyproject.toml, Cargo.toml, go.mod), proceed with that, and offer the user
   to write a profile from this plugin's `templates/project-profile.md` (`../../templates/project-profile.md` from this
   skill's directory).
3. **Read `AGENTS.md`** at the repo root (and any tool-specific file such as `CLAUDE.md`).
4. **Project memory**: your tool's project memory, if it has one (Claude Code: the auto-memory dir for this repo).
   Read its index, then the entries named below; pass the paths to sub-agents.
5. If an orchestrator dispatched you with a ready worktree and branch, use them wherever this skill says to create
   one. Don't create another.

**Sub-agents.** When a step uses parallel sub-agents, spawn them if your tool supports them (Claude Code: the Agent
tool, background; Codex/Grok: their subagents); otherwise run the roles sequentially. Role prompts and the hand-back
rule: `../project-pr-review/references/review-roles.md`.

## 0. Mode

- **Existing doc** (argument is a path): read it and validate it against the doc contract. Worktree rule: if the doc's
  worktree is already on a `docs/<slug>-design` branch, work there and skip phase 2; if it is untracked or sits on any
  other branch, do phase 2 first and move the doc into the new design worktree. Then jump to the first phase whose
  output is missing or invalid (e.g. Status says decisions are taken and there is no §Tracking → go to phase 8; phases
  lack acceptance criteria or gates → phase 4 for those parts, then 5 with reviewers told to review only the
  additions). Never re-run the full consortium on a doc whose decisions are already taken unless the user asks or the
  gaps change the design.
- **New design**: start at phase 1.

## 1. Intake

Ask what the feature must do, who it is for, and what it must not do. Keep it brief; deep questions come after the
survey, when you know which ones matter.

## 2. Design worktree

Never work in an existing worktree (unless you were dispatched with one). From the bare root, with the slug in
kebab-case (`user-preferences`) and the directory named per §Layout (default `<slug>-design`):

```
git fetch origin <base>
git worktree add --no-track -b docs/<slug>-design <bare-root>/<design-dir> origin/<base>
```

`--no-track` keeps the branch from tracking `origin/<base>` (a bare `git push` or `git pull` would target the base
branch); phase 7's `git push -u` gives it its own upstream.

The doc lives in the design-doc directory from §Docs (default `docs/design/<slug>.md`). If a draft already exists
elsewhere (untracked in another worktree), move it here.

## 3. Survey (run the three parts in parallel)

1. **Code survey**: search sub-agents for breadth, direct reads for depth. Produce a "What exists today" table with
   `file:line` evidence: seams, stubs, TODOs, hard-coded values, adjacent features to stay consistent with, and
   conventions to match (§Conventions lists the project's: e.g. transaction ownership, DTO style, mapping
   registration, dialog styling, route shapes). Pre-existing bugs found on the way go into §Follow-ups, not scope.
2. **Memory**: every project-memory entry touching the area (past triage states, gotchas, parked work).
3. **Issue sweep (cursory)**: GitHub `<org>/<repo>`, plus any related repo §Identity says the area touches. If
   §Identity names a legacy tracker for older closed work, check it read-only. The sweep only reads; in a related
   repo, any write it leads to (filing, commenting, closing, a `Closes` line) is listed for approval at phase 6.
   - `gh issue list -R <org>/<repo> --search "<terms> type:Epic" --state all` for existing epics; 4–8 keyword queries
     (`gh search issues --repo <org>/<repo> --include-prs=false "<terms>"`, open and closed) built from the feature's
     nouns and the UI areas it touches. Search is fuzzy, so read each plausible candidate with `gh issue view` before
     classifying it.
   - Classify into a disposition table saved in the doc's §Tracking as *proposed*:
     **umbrella** (an existing Epic/brainstorm issue for this feature: becomes the epic),
     **fixed-by** (the design resolves it: goes on the PR close list),
     **related** (adjacent, untouched: linked from the epic body only),
     **stale** (already delivered by earlier work: tell the user, close only if they say so),
     **ignore**.

## 4. Draft the design doc

Write the doc following the doc contract. Points that matter most for the build:

- **Phase plan.** Each phase: number, name, one-paragraph summary, `depends-on`, **acceptance criteria** (verifiable
  statements: compile-level, headless-checkable, or "manual: …"), **ux-gate** (`none` | `async` | `blocking`, with
  the reason), and for spikes a time-box plus go/no-go criteria. Order phases so a new UI container lands early with
  one minimal card in it, before the phases that fill it. Backend-only and consumer-wiring phases are the natural
  companions to run while an async gate is out.
- **Decisions.** Every design choice gets a line with status `decided (date)`, `provisional` (revisit after hands-on
  use), or `open`. Provisional decisions generate a gate at the phase that lands them.
- **Gate heuristics** (apply, and say which one justified each gate):
  1. A new container that later phases fill → `blocking`, right after the shell lands.
  2. A component reused outside its home page → `async` after the spike, screenshot-first.
  3. An interaction pattern with no precedent in the app → `async`.
  4. A decision marked provisional → `async` at its phase.
  5. Fan-out: the more phases depend on a UI, the earlier and harder its gate.
  Wording, colours, spacing never gate: they go in the final UX QC checklist. Cap: two gates per feature, at most one
  blocking.
- Constraints: test work only as §Tests allows; respect §Conventions, §Do not and the repo's `AGENTS.md`; the
  changelog entry per §Changelog is part of delivery.

## 5. Consortium review (plan, not code)

Spawn the role reviewers all at once: Architect, Security, Adversary, the UI / UX role (from §Review roles, or the
generic one when the feature has a UI), plus any other role §Review roles adds. Use your strongest model (Claude Code:
`model: "opus"`; bump to `"fable"` only for unusually high-risk designs). Each gets the doc path, the design worktree
path, the memory paths, and the instruction to verify every claim against the actual code, severity-rate, and be
selective. Extra deliverables per role:

- **Architect**: phase ordering and dependency sanity, seams (one resolution point, not three), simpler alternatives,
  anything that will not survive the next feature in the area.
- **UI / UX**: nominated UX gates (phase, `async`/`blocking`, heuristic that justifies it), missing containers,
  existing components/patterns to reuse, a11y.
- **Security**: threat notes per surface, what the server must validate, what stored strings can reach, auth scoping.
- **Adversary**: per phase, the most likely way it is wrong; the single phase most likely to need rework;
  acceptance-criteria gaps (criteria that can't actually be checked).

Each ends with AGREE / AGREE-WITH-CHANGES (listed) / REJECT (why + alternative), per the hand-back rule. Fold feedback
in, bump the revision, log it in §Revision log, re-run on the revised doc. Repeat until all AGREE, capped at 3 rounds;
survivors are resolved by the lead with the code as arbiter and recorded as `provisional` decisions.

## 6. Decisions gate (the one human gate)

Present, batched with your tool's question UI (Claude Code `AskUserQuestion`: ≤4 questions per call, repeat as
needed): open decisions; provisional decisions that need confirming; the proposed gates (phase + kind); the issue
dispositions (absorb this umbrella? close these stale issues? anything to add?); and every write the plan makes in
a repo other than this one (filing the epic or phases there, commenting on or closing its issues, a
`Closes <org>/<other-repo>#<n>` line), each listed for a yes or no. Without a yes, the item stays read-only: link it
from the epic body instead. Fold answers into §Decisions with
dates, update the phase plan, and set the header to
`Status: Ready for implementation — revision N, all decisions taken <date>`.

## 7. Commit and push the docs branch

```
git add <doc path> && git commit -m "docs: <feature> design rev N"
git push -u origin docs/<slug>-design
```

The branch is docs-only and is merged later via the feature PR; pushing gives the doc a GitHub copy.

## 8. GitHub epic

Repo `<org>/<repo>` (work owned by a related repo goes there only if the human approved it at phase 6; §Identity). Board: org Project `<project#>`, with its
node id, Status field id and option ids (Backlog, In Progress, …) from §Identity. If §Identity lacks the ids, discover
them: `gh project view <project#> --owner <org> --format json --jq .id` and
`gh project field-list <project#> --owner <org> --format json`.
Conventions: type = org issue type (Epic/Feature/Bug/Task; if §Identity says the repo has no issue types, as in
personal repos where the API silently drops `type`, use the type labels it names instead); priority = one of
`P1-urgent`…`P4-low`; area labels as existing. Check that every label you rely on exists (`gh label list`) before
relying on it. Create (or update, if the sweep found an epic) in this order, recording every number and numeric `id`
(`--jq .id`, needed for sub-issue and dependency calls) as you go:

1. **Epic issue**: if the sweep found one, edit its body to add "Design: <GitHub URL of the doc on the docs branch>
   (rev N). Phases tracked as sub-issues." and set type Epic. Otherwise
   `gh api -X POST repos/<org>/<repo>/issues -f title="<Feature>" -f type=Epic -f body=<goal paragraph + doc link +
   phase table (number, name, gate)>`. Its number drives the feature branch name (`feat/<epic#>-<slug>`). Once the doc
   is READY, add the `route:build` label to the epic (and remove `route:design` / `needs-design` if present): the
   orchestrator dispatches the epic itself to `/project-feature-build`.
2. **Phase issues**: one per phase, created in dependency order: `title: "Phase N: <name>"`, `type: Feature`, the
   epic's P label **plus `epic-phase`** (`-f "labels[]=epic-phase"`), body = summary + acceptance criteria as a task
   list + gate + spike note + depends-on. `epic-phase` tells the orchestrator never to dispatch a phase on its own; the
   epic's `/project-feature-build` run works every phase. Attach each to the epic:
   `gh api -X POST repos/<org>/<repo>/issues/<epic#>/sub_issues -F sub_issue_id=<phase id>`. Blocked-by chain from
   `depends-on`:
   `gh api -X POST repos/<org>/<repo>/issues/<phase#>/dependencies/blocked_by -F issue_id=<dep id>`.
3. **Board**: add the epic and every phase issue to the Project
   (`gh project item-add <project#> --owner <org> --url <issue url> --format json --jq .id`) and set Status Backlog
   (`gh project item-edit --project-id <project node id> --id <item> --field-id <status field id>
   --single-select-option-id <Backlog option id>`).
4. **Dispositions**: fixed-by issues: comment "Resolved by epic #<n>" and list them in the epic body (they go on the
   PR close list). In another repo, only the writes approved at phase 6. Related: listed in the epic body only. Stale: close as completed only if the user confirmed in
   phase 6, with a comment naming what delivered it.
5. **Write back**: fill the doc's §Tracking (epic #/URL, phase → issue table, fixed-by list, related list, stale
   list). Commit `docs: link tracking issues` and push. The doc in git is the only copy; there is no mirrored
   document.

Verify every write by the id or URL the command returned, never by searching for "the newest" issue or comment.

## 9. Memory and report

Save a project-memory note `<slug>-design` (if your tool has project memory): doc path/branch/rev, epic and phase issue
numbers, gates, design pins the build must not relitigate, and the next step. Add its line to the memory index.

Report: doc path, branch, revision; epic and phase issue links; the phase plan with gates and why each gate exists;
decisions summary; stale issues flagged; the exact next command: `/project-feature-build <doc path>`.

Under the orchestrator (design route) the doc needs no human review after its decisions gate: once it is READY, the
epic and phases are filed and the report is written, follow the hand-off in your dispatch brief instead of starting
the build yourself.
