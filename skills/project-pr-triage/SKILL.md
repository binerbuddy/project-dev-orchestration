---
name: project-pr-triage
description: Triage the review comments on a GitHub PR in the current repo, verify proposed fixes with a sub-agent consortium, and, after two explicit human gates (pick fixes; pass QC), implement them on the PR branch, push, and post one fixed/not-fixed comment. Use when asked to triage PR review findings, act on review comments, or fix what a review flagged on PR #N.
argument-hint: "<PR#>"
---

# PR review triage and fix (consortium-verified)

> Engine commands are written `pdo <name> …`. If `pdo` isn't on PATH, run `<engine checkout>/bin/<name> …` instead; a dispatch brief gives the absolute path.

Triage the review comments on pull request `#<PR>` (the argument), propose verified solutions, and,
after explicit human approval and human QC, implement and push the accepted fixes to the PR branch.

**Repo and project facts.** The repo is the one of the current working directory (bare-root
layouts: `git rev-parse --git-common-dir`). Read `.agents/project-profile.md` (worktree top level,
else `git show origin/HEAD:.agents/project-profile.md`) for `## Build & checks` (the authoritative
compile/typecheck commands and known-noise errors), `## Changelog`, `## Review roles` and
`## Conventions`. No profile: detect the obvious build tooling (package.json scripts, *.sln,
pyproject, Cargo, go.mod) and use that.

**gh identity.** If the project env sets `GH_USER`, run gh through `pdo with-gh-user gh …`.
Never `gh auth switch`.

**Two HARD GATES.** You MUST stop and wait for the human:
1. after presenting triaged solutions: the human picks which to implement;
2. after implementation: the human completes the QC checklist before anything is pushed.

Never push, and never start implementing, past a gate the human has not explicitly cleared. (A
calling lifecycle skill such as `project-small-feature-or-bug-fix` may waive the gates; it says so
explicitly when it does.)

## 1. Gather the review material

1. `gh pr view <PR> --json title,body,baseRefName,headRefName,url,state`
2. Read ALL review comments and threads:
   - `gh pr view <PR> --json reviews` (review bodies; a consortium review from `project-pr-review`
     is usually the primary source)
   - `gh api repos/{owner}/{repo}/pulls/<PR>/comments` (inline threads)
   - `gh pr view <PR> --json comments` (issue-style comments)
3. Extract every distinct finding into a working list (id, severity as posted, `file:line`, claim,
   suggested fix) and save it to a scratchpad file.
4. Save `gh pr diff <PR>` to the scratchpad, and fetch the head for context: `git fetch origin <headRefName>`.

## 2. Triage production likelihood

For each finding, assess how likely it is to bite in production, verifying claims against the code
(read the fetched head via `git show FETCH_HEAD:<path>` or a read-only worktree; do NOT create the
writable fix worktree yet). Use structural search for blast-radius checks. For a finding you can't
classify confidently from the code (a claimed race, subtle state corruption), optionally delegate to
a tracing sub-agent (oh-my-claudecode `tracer`, if available) for evidence for and against, and
classify from its verdict.

- **LIKELY**: reachable in normal production use, or guaranteed by the code path.
- **PLAUSIBLE**: needs a race, an edge input, or an unusual-but-real deployment condition.
- **UNLIKELY**: contrived precondition, mitigated elsewhere, or cosmetic-only impact.
- **NOT-A-FIX**: pre-existing or out of scope, design-accepted, or better as a follow-up issue;
  recommend NOT fixing in this PR (still reported in the final comment).

For everything except NOT-A-FIX, draft a concrete solution: approach, files touched, blast radius.
Prefer the fix the review suggested unless the code says otherwise.

## 3. Verify solutions (parallel consortium)

Spawn sub-agents if your tool supports them (Claude Code: the Agent tool, all in one message,
background, `model: "opus"`; Codex/Grok: their subagents); otherwise run the roles sequentially.
Roles: **Architect, Security, Adversary**, plus the profile's `## Review roles` (typically a UI
designer, which covers only UI-touching solutions). Role prompts and the hand-back rule:
`../project-pr-review/references/review-roles.md`.

Each gets the triaged list with proposed solutions (scratchpad file), the PR diff and the fetched
head, and reviews the SOLUTIONS, not the original findings: is the approach correct, is there a
simpler or safer fix, does it regress anything, does it miss part of the problem? The Adversary hunts
ways each fix fails or regresses. Verdict per solution: AGREE / AGREE-WITH-CHANGES (state them) /
REJECT (why, plus an alternative). Fold the feedback in; where verifiers disagree, resolve with the
code and note the disagreement.

## 4. GATE 1: present and ask

Present a HIGH-LEVEL numbered list, one or two sentences each:
`N. [LIKELY/PLAUSIBLE/UNLIKELY] <plain-language problem> → <plain-language fix> (effort: S/M/L)`,
grouped by tier, with NOT-A-FIX items briefly at the end with the reason. No code or file paths unless
asked. State a recommendation (typically all LIKELY plus cheap PLAUSIBLE).

ASK which to implement and STOP. Create no worktree and write no code until the human answers. Then
record a resumability note: scratchpad paths (finding list, diff), the approved solutions, and the
gate position. Use your tool's durable notepad if it has one (oh-my-claudecode
`notepad_write_working`), else a `triage-state.md` in the scratchpad. Gate waits are where a session
idles long enough to compact; approvals must survive summarisation, so re-read the note after any
compaction.

## 5. Implement in a temp worktree

1. Create a worktree ON THE PR BRANCH (needed to push later), from the bare root:
   `git fetch origin <headRefName> && git worktree add <root>/pr-triage-<PR> <headRefName>`.
   If the local branch is checked out elsewhere, use `-B <headRefName> origin/<headRefName>`
   semantics or fail loudly. Never detach.
2. Implement the approved fixes, grouping related findings per implementer and running independent
   groups in parallel when your tool supports sub-agents (oh-my-claudecode `executor`, if available).
   Each implementer gets the finding, the verified solution with verifier amendments, the worktree
   path, and the conventions: LF line endings only; match surrounding style; no drive-by refactors.
3. Do NOT run full test suites or long-lived dev servers unless the profile says to; the human runs
   their own app and reports runtime errors. Implementers read back every edited hunk. Fast inner
   loop: after each fix group, run language-server diagnostics on the touched files if available
   (this is a real working copy, unlike the review worktree) and fix new errors before the next group.
   After ALL groups, you MUST run the profile's `## Build & checks` commands on the worktree (ignore
   the known-noise errors it lists), fix every new error and commit the fix before Gate 2. Never hand
   the human code that doesn't compile.
4. Commit per logical fix or group (bisectable): `fix(<area>): <finding summary> (review triage #<PR>)`.
   Update the changelog entry per the profile's `## Changelog` if user-facing behaviour changed.
   Commit locally only. DO NOT PUSH.
5. Each implementer reports: what changed, a per-file summary, and items that need human eyes (visual
   layout, live realtime behaviour, data-dependent paths, timing and races).

## 6. Verifier pass, then GATE 2: QC checklist, then wait

First run a read-only completeness verifier (oh-my-claudecode `verifier` if available, else a
sub-agent or yourself) with the approved-solution list including amendments, the worktree path, and
the diff of the new commits. It confirms every approved solution was implemented as amended, nothing
skipped or half-done, with evidence per finding. Fix the gaps (checkpoint commit, re-run the checks)
before Gate 2. This matters double when gates are waived: then it is the only completeness check
between implementation and push. Update the resumability note (gate: awaiting QC).

Present:
- a short summary (per finding: done, or deviated from plan and why);
- a **QC checklist** of everything that needs human verification: concrete steps in the running app
  ("open the access dialog, edit a role, remove a user, confirm the role edit survives Save"),
  flagged per finding, including everything the implementers flagged and anything you can't verify
  statically.

STOP and wait. On reported failures, fix in the worktree (new commits) and re-present the affected
items. Proceed only when the human explicitly confirms QC passed.

## 7. Push and close the loop

1. Push from the worktree: `git push origin HEAD:<headRefName>`.
2. Post ONE PR comment (`gh pr comment <PR> --body-file …`) mapping back to the original review:
   - **Fixed**: each finding addressed, one line each, with the commit hash;
   - **Not fixed (deliberate)**: each UNLIKELY/NOT-A-FIX or declined finding, one line with the
     reason (pre-existing, follow-up issue, design-accepted, contrived precondition, …);
   - what the human QC-verified versus what was verified statically.
3. Remove the worktree (`git worktree remove` + `prune`) ONLY after confirming the push landed
   (`gh pr view <PR> --json commits` shows the new head). On permission-denied files, give the human
   the path for manual cleanup.

**Verifying what you posted.** Report the URL `gh pr comment` printed; don't go looking for it
afterwards. `gh api .../issues/{n}/comments --jq '.[-1]'` returns *somebody's* comment whether your
post succeeded or not, so it can't report failure. If you confirm independently, fetch the specific id
the post returned. A review posted by `gh pr review` lives in `pulls/{n}/reviews`, not
`issues/{n}/comments`: don't conclude from the comments endpoint that the review you're mapping back
to doesn't exist.

**Editing a comment in place.** Re-read its body first and confirm the expected `<!-- … -->` marker:
an id captured earlier may now belong to a different comment, and overwriting it destroys content the
human may already have ticked.

Throughout: keep human-facing updates high-level; the detail lives in the PR comment and commits.

**Follow-ups you notice** that are out of scope: don't file them yourself. Queue them for intake
(`pdo intake-submit "<your workspace name>" "<report>"`), or, with no engine installed, list them
in your final report so a human can file them with `needs-triage`.
