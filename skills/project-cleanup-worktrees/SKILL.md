---
name: project-cleanup-worktrees
description: Fast-forward the base branch, then delete every local branch and git worktree whose commits are safely contained in it (ancestry check), skipping dirty worktrees and squash-merge suspects, and hand any permission-denied leftovers to the user as one sudo command. Built for bare-root repos with worktrees as subdirectories. Use when asked to clean up merged worktrees or branches, or after PRs merge.
argument-hint: "[repo root path]"
---

# Clean up merged worktrees and branches

> Engine commands are written `pdo <name> …`. If `pdo` isn't on PATH, run `<engine checkout>/bin/<name> …` instead; a dispatch brief gives the absolute path, else the repo's `AGENTS.md` names it (`<engine checkout>/bin/install --bin` puts `pdo` on PATH).

Update the base branch, then delete every local branch and worktree whose changes are safely
contained in it. Built for the bare-root layout (e.g. `~/Projects/Acme.git` with worktrees as
subdirectories and the base worktree at `<root>/<base>`); the profile's `## Layout` names the
convention and the base branch (default: the remote's default branch, usually `main`).

## 1. Locate the repo root

```
ROOT=$(git rev-parse --path-format=absolute --git-common-dir)
BASE=$(git -C "$ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
```

Use the argument as the root when given. If you're not inside a repo and no path was given, stop and
ask which repo. Fall back to `main` for `BASE` if `origin/HEAD` isn't set, unless the profile's
`## Layout` names another. The base worktree is `$ROOT/$BASE` (per `## Layout`; for a normal,
non-bare clone it's the main checkout).

## 2. Update the base branch

```
git -C "$ROOT/$BASE" fetch --prune origin
git -C "$ROOT/$BASE" pull --ff-only
```

If the base worktree is dirty or the pull can't fast-forward, STOP and report. Never delete anything
against a stale or diverged base.

## 3. Identify what is safely merged

Enumerate worktrees (`git worktree list --porcelain`) and local branches
(`git for-each-ref refs/heads --format='%(refname:short) %(objectname)'`).

A branch is **safely merged** iff `git merge-base --is-ancestor <branch> origin/$BASE`.

That's authoritative for repos that merge with real merge commits. If a branch is NOT an ancestor but
`gh pr list --state merged --head <branch>` shows a merged PR (squash or rebase merge suspect), do NOT
delete it: list it for the user to decide. (If the project env sets `GH_USER`, run gh through
`pdo with-gh-user`; never `gh auth switch`.)

Never candidates, whatever their merge state: the base branch, the bare root itself, the worktree
this session runs from, and any long-lived branches the profile's `## Layout` or `## Do not` keeps
(e.g. a `qc-fixtures` or `documentation` branch).

## 4. Remove merged worktrees

For each worktree whose checked-out branch is safely merged:

1. `git -C <worktree> status --porcelain` (tracked changes and untracked files). Non-empty: SKIP it and
   list the files. Even a merged branch's worktree may hold uncommitted work.
2. Clean: `git worktree remove <worktree>` (never `--force`).
3. Removal fails with "Permission denied" (typically build caches created as another user, e.g. by a
   container): git usually still deregisters the worktree and only the directory remnant remains. Run
   `git worktree prune`, confirm with `git worktree list` that it's gone, add the leftover directory
   to the **sudo list**, and continue. Don't attempt sudo yourself; it can't prompt for a password here.

## 5. Delete merged branches

From the base worktree, for every safely merged branch (including those with no worktree):
`git -C "$ROOT/$BASE" branch -d <branch>`. Use `-d` only, never `-D`. A branch still checked out in a
skipped (dirty) worktree can't be deleted: report it. Never delete remote branches.

## 6. Report

- **Deleted:** worktrees removed and branches deleted.
- **Kept (not merged):** branches and worktrees whose commits aren't in the base.
- **Skipped (dirty):** merged worktrees with uncommitted or untracked files, with the file list.
- **Needs user decision:** squash-merge suspects from step 3.

If the sudo list is non-empty, end with one copy-pasteable command in a code block, for the user to
run in a real terminal:

```
sudo rm -rf <dir1> <dir2> ... && git -C <ROOT> worktree prune
```

Include the trailing `worktree prune` only if any of those worktrees were still registered after step 4.
