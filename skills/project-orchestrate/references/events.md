# Orchestrator events and prompts

> `pdo <name>` is an engine command (else `<engine checkout>/bin/<name>`). Paths written `$PDO_STATE_DIR`, `$PDO_INBOX` or `$PDO_HOME` (the engine checkout) mean the values `pdo project-env <KEY>` prints; agent sessions don't have them set.

`<p>` is the project; pass `--project <p>` to every script that takes it (all but `rebase-mark`). State paths are under `$PDO_STATE_DIR`.
Label and status names are the engine defaults ("Claude Work This", `ready for QC`,
`QC complete - ready to review`); a project may rename them in its env (`CWT_STATUS`,
`LABEL_QC_READY`, `LABEL_QC_DONE`; `pdo project-env <KEY>` prints the value in use).

## Event table

| Event | Action |
|---|---|
| `urgent` | A queue item is P1-urgent AND on the queue status. Spawn it now (step 3, urgent bypass) even when `free_slots` is 0 or usage is over the ceiling. |
| `slot_freed` | Go to step 3. |
| `new_claude_work_this` | Go to step 3. This item outranks everything. |
| `design_ready` | A design run finished and labelled its epic `route:build`. Don't wait for any human design review. Close the design workspace you spawned (`herdr workspace close <workspace_id>`), then immediately `pdo spawn <repo> <n> --route build --brief "<2-3 words> build"`. It doesn't count against the tick's slot budget: it replaces the design run. If spawn refuses because a workspace still exists, report it. If the design PR already merged and its branch is stale, pass `--base origin/<base branch>` (spawn defaults `--base` to the design branch). |
| `pr_conflict` | An agent's PR became CONFLICTING. Don't act on the event; step 2b handles every entry in `conflicting`. |
| `pr_cap_reached` | `open_awaiting_human` PRs ≥ `cap` (default 10, file `$PDO_STATE_DIR/<p>-pr-cap`). `free_slots` is now 0, so nothing new spawns (urgent bypass excepted). Report it once with the count, and say that merging or closing PRs resumes new work. |
| `qc_feedback` | A trusted `QC:` comment on a PR (from remote QC, see the profile's `## QC preview`). Find the agent with `pdo pr-agent <number>`, then send the **remote QC feedback prompt** (below) with `pdo resume-agent <repo> <issue#> --prompt "…"`. Then `gh pr edit <n> --remove-label "ready for QC"`. Exit 3 (question pending): leave the label, report it, retry next tick. No agent metadata (someone else's PR): report it. |
| `qc_complete` | The human approved QC. If `$PDO_STATE_DIR/qc/handled/<Repo>-<pr#>` exists, `/project-qc-review` already told the agent: do nothing. Otherwise send the **QC approved prompt** with `pdo resume-agent`. It works whether the agent is open or hibernated. Exit 3: leave it for the human. |
| `pr_merged` | Check the issue closed (`gh issue view`). If its board card isn't Done, set it (`pdo claim` refuses a closed issue and self-heals its card to Done). Report that the workspace can be closed and `/project-cleanup-worktrees` run. Don't close workspaces yourself. |
| `stalled` | Read the last ~60 lines with `herdr agent read <pane_id>`. If it's clearly waiting on something that has finished (a background agent, CI), or ended a turn mid-phase with no question, nudge it once with the **check-in prompt** (`herdr agent prompt <pane_id> "…"`). If it looks confused or errored, don't nudge: report it. |
| `agent_gone` | A workspace closed. If its issue is open and it has no merged PR, report it. Leave the claim alone; the human decides. |
| `usage_ceiling` | Stop spawning. Report the weekly and 5-hour figures. The weekly reserve is for manual or hot work. |
| `closed_out` | Informational. The watcher released a finished agent: PR merged, QC passed and it printed "wrap-up done", or its issue closed with no open PR (likely-fixed confirmed, won't-fix). Session kept. One line. |
| `hibernated` / `hibernate_failed` | Informational; they ride along with other events. The watcher released an agent parked at `ready for QC` (side processes stopped, workspace closed, session kept for `pdo resume-agent`). One line; for a failure include the reason and don't retry by hand. |
| `qc_pass_recorded` / `qc_pass_ignored` | Informational; they ride along with other events. A trusted `Claude, QC pass` comment: the watcher swapped `ready for QC` for `QC complete - ready to review` and replied (`qc_complete` follows on the next tick), or ignored it (`why`: not an open PR, not labelled ready, already complete, or the label edit failed). One line; for an ignored pass, include the reason so the human can apply the label by hand. |
| `first_run` / `heartbeat` | Nothing special. Continue to step 3. |

## Prompts

**Remote QC feedback** (`qc_feedback`):

```
Remote QC feedback from @<author> on PR #<n> (<url>):
<body>
The reporter reads GitHub, not this session: reply ON THE PR. If anything is unclear, ask there with an @<author> mention, then wait for their next 'QC:' comment. Fix, push, reply on the PR with what changed, then re-apply 'ready for QC'.
```

**QC approved** (`qc_complete`):

```
QC approved: the 'QC complete - ready to review' label is on <pr url>. Read any QC feedback in the PR comments and in this session, finish the PR per your dispatch brief (fixes, final push, final comment). Do not merge.
```

**Check-in** (`stalled`):

```
Orchestrator check-in: you've been idle for <n> min without a pending question. Continue your current phase, or state plainly what you're waiting on.
```

**Rebase** (step 2b):

```
Your PR #<n> now conflicts with its base (<base>), after other PRs merged. Rebase it: git fetch origin && git rebase origin/<base> (if <base> was merged or deleted, retarget the PR to the default branch with gh pr edit --base <default> and rebase onto origin/<default>). Resolve every conflict keeping both sides' intent, following any rebase notes in your project profile's Conventions section (e.g. generated files to regenerate rather than merge). Run the profile's Build & checks commands, then git push --force-with-lease. Keep all labels. Post one PR comment: 'Rebased onto <base> @ <sha>; conflicts resolved in: <files>' (say if behaviour may have changed and needs re-QC). Stop any dev server you started, then idle.
```
