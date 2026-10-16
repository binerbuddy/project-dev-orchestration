---
name: project-pr-review
description: Multi-agent consortium code review of a GitHub pull request in the current repo. Reads the PR in a temporary detached worktree, fans out Architect, Code Review, Security, Adversary (plus the profile's extra roles, e.g. a UI designer), keeps only findings a 3-judge majority confirms, and posts ONE review comment. Use when asked to review PR #N, run a PR review, or give a consortium review.
argument-hint: "<PR#>"
---

# PR review (multi-agent consortium)

> Engine commands are written `pdo <name> …`. If `pdo` isn't on PATH, run `<engine checkout>/bin/<name> …` instead; a dispatch brief gives the absolute path.

Review pull request `#<PR>` (the argument) of the git repo you are in, using a temporary worktree and
a review consortium. Only findings the consortium agrees on get posted.

**Repo and project facts.** The repo is the one of the current working directory (`git rev-parse
--show-toplevel`; for a bare-root layout, `git rev-parse --git-common-dir`). Project knowledge comes
from `.agents/project-profile.md` (worktree top level, else `git show origin/HEAD:.agents/project-profile.md`).
This skill uses its `## Review roles` section. No profile: run the core roles only.

**gh identity.** If the project env sets `GH_USER`, run every gh call through
`pdo with-gh-user gh …` (or `GH_TOKEN=$(gh auth token -u "$GH_USER") gh …`). Never
`gh auth switch`: gh's active account is machine-wide and switching it breaks every other session.

## 1. Set up a temporary review worktree

1. Find the git root. `git rev-parse --is-bare-repository`: if bare, the current directory hosts the
   worktrees; otherwise use `git rev-parse --path-format=absolute --git-common-dir`.
2. Fetch the PR head without touching any branch: `git fetch origin pull/<PR>/head`.
3. Create a detached worktree alongside the repo's other worktrees (or under your scratchpad if the
   root isn't writable): `git worktree add --detach <root>/pr-review-tmp-<PR> FETCH_HEAD`.
4. Gather inputs:
   - `gh pr view <PR> --json title,body,baseRefName,headRefName,url,files`
   - `gh pr diff <PR>`, saved to a scratchpad file so sub-agents can read it
   - the changed-file list from the diff

**Do not install, build or run dev servers in this worktree.** Build caches can end up owned by
another user (e.g. created inside a container) and block cleanup. The worktree exists so reviewers
can read full file context, nothing more. Consequence: dependencies aren't installed, so do NOT use
language-server/LSP diagnostics here; they drown in module-resolution noise and mislead judges.
Pure-syntax structural search (e.g. `ast-grep`, or oh-my-claudecode `ast_grep_search` if available)
is safe and recommended for "all call sites of X" sweeps.

## 2. Fan out the review consortium (parallel)

Spawn sub-agents if your tool supports them (Claude Code: the Agent tool, all in one message,
background; Codex/Grok: their subagents); otherwise run the roles sequentially yourself. Use a strong
model for reviewers (Claude Code: `model: "opus"`); you, the lead, do the dedupe and synthesis.

Roles and their prompts: `references/review-roles.md`. Always the four core roles (Architect, Code
Review, Security, Adversary), plus every role in the profile's `## Review roles` (or the generic UI
Designer when the diff touches UI and the profile names none).

Each reviewer gets: the PR title and description, the saved diff path, the worktree path (for
surrounding code), its role prompt, the finding format and the hand-back rule from the reference.

## 3. Consortium consensus

1. **Dedupe and merge.** Collect all findings and merge duplicates, noting how many agents flagged
   each. Multi-agent agreement is strong signal: auto-keep those.
2. **Majority vote** on every remaining candidate: spawn 3 judge sub-agents (same spawning rule and
   model as above). Each gets the full deduped list, the diff and the worktree path, and votes per
   finding REAL-AND-CONCERNING or REJECT with one line of reasoning. Judges verify against the actual
   code, not plausibility: a finding that misreads the code is rejected. Blast-radius claims ("every
   caller of X breaks") are verified structurally over the worktree, not trusted.
3. A finding survives only with ≥2 of 3 judge votes. Nothing that failed consensus may appear in the
   posted review.

## 4. Report and post

1. Show the surviving findings in the terminal, grouped by severity, each with `file:line`,
   description and suggested fix. Note how many raw findings consensus filtered out.
2. Post ONE review: `gh pr review <PR> --comment --body-file <file>`. Format: a short summary of the
   PR and the review process, findings grouped Critical → Low, an overall assessment. Only
   consensus-approved findings. If nothing survived, post a brief "no significant concerns" review.

**Report the URL the post command itself printed. Never go looking for it afterwards.** That return
value is the only thing that identifies what you created. A follow-up query cannot establish it:
`gh api .../issues/{n}/comments --jq '.[-1]'` returns *somebody's* comment whether your post
succeeded or not, so it is not a check. It also looks in the wrong place: `gh pr review` creates a
**review** (`pulls/{n}/reviews`), which never appears in `issues/{n}/comments`. To confirm
independently, match on **identity, not position**: take the id from the post's output and find that
exact id in `gh api repos/{owner}/{repo}/pulls/{n}/reviews --jq '.[] | .id'`. "The last one" is never
evidence that your write landed.

## 5. Cleanup

`git worktree remove <root>/pr-review-tmp-<PR> && git worktree prune`. If removal fails on
permission-denied files, give the user the path so they can remove it themselves (e.g. with sudo in
a real terminal); never leave it behind silently.

Be constructive and actionable: substantive issues over stylistic preferences.
